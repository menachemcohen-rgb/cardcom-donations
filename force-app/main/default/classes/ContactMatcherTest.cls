@IsTest
private class ContactMatcherTest {
  static final String VALID_ID = '123456782';

  @TestSetup
  static void setup() {
    TestDataFactory.contact('Avi', 'Cohen', 'avi@example.com', '0521111111');
    TestDataFactory.contact('Ben', 'Levi', 'ben@example.com', '0522222222');
  }

  static ContactMatcher.DonorInput input(String email, String phone, String taxId) {
    return input('Avi', email, phone, taxId);
  }

  static ContactMatcher.DonorInput input(String firstName, String email, String phone, String taxId) {
    return new ContactMatcher.DonorInput(firstName, 'Donor', email, phone, taxId);
  }

  static Contact byEmail(String email) {
    return [
      SELECT Id, FirstName, LastName, Email, MobilePhone, OtherPhone, Donor_Tax_Id__c, Needs_Review__c, Review_Reason__c
      FROM Contact
      WHERE Email = :email
    ];
  }

  @IsTest
  static void normalizationHelpers() {
    Assert.areEqual('0521234567', ContactMatcher.normPhone('+972-52-123-4567'));
    Assert.areEqual('0521234567', ContactMatcher.normPhone('00972521234567'));
    Assert.areEqual('0521234567', ContactMatcher.normPhone('521234567'));
    Assert.areEqual('031234567', ContactMatcher.normPhone('03-1234567'), 'any number is accepted (N124)');
    Assert.areEqual('+14702280495', ContactMatcher.normPhone('+1 (470) 228-0495'), 'foreign numbers keep +');
    Assert.areEqual('+447911123456', ContactMatcher.normPhone('0044 7911 123456'));
    Assert.areEqual('+14702280495', ContactMatcher.normPhone('14702280495'), 'same number without + matches');
    Assert.areEqual('+14702280495', ContactMatcher.normPhone('001-470-228-0495'));
    Assert.isNull(ContactMatcher.normPhone('12345'), 'too short');
    Assert.isNull(ContactMatcher.normPhone('+1234567890123456'), 'too long');
    Assert.isNull(ContactMatcher.normPhone(' '));
    Assert.areEqual('a@b.co', ContactMatcher.normEmail(' A@B.co '));
    Assert.isTrue(ContactMatcher.validIsraeliId(VALID_ID));
    Assert.isTrue(ContactMatcher.validIsraeliId('18'), 'left-padded to 000000018');
    Assert.isFalse(ContactMatcher.validIsraeliId('123456789'));
    Assert.isFalse(ContactMatcher.validIsraeliId('12345678a'));
    Assert.isFalse(ContactMatcher.validIsraeliId(''));
    Assert.isNull(ContactMatcher.taxIdHash('123456789'));
    Assert.areEqual(64, ContactMatcher.taxIdHash(VALID_ID).length());
  }

  @IsTest
  static void matchesByEmailAndFillsOtherPhone() {
    ContactMatcher.skipDuplicateRules = true;
    Integer before = [SELECT COUNT() FROM Contact];
    ContactMatcher.Result r = ContactMatcher.matchOrCreate(input('AVI@example.com', '0529999999', null));
    Contact c = byEmail('avi@example.com');
    Assert.areEqual(c.Id, r.contactId);
    Assert.areEqual('Email', r.method);
    Assert.isFalse(r.created);
    Assert.areEqual(before, [SELECT COUNT() FROM Contact], 'no new Contact');
    Assert.areEqual('0529999999', c.OtherPhone, 'different mobile goes to OtherPhone (B6.4)');
    Assert.areEqual('0521111111', c.MobilePhone, 'mobile is never overwritten');
    Assert.areEqual('Avi', c.FirstName, 'name is never overwritten');
  }

  @IsTest
  static void matchesByPhoneAndFlagsDifferentEmail() {
    ContactMatcher.skipDuplicateRules = true;
    ContactMatcher.Result r = ContactMatcher.matchOrCreate(input('other@example.com', '052-111-1111', null));
    Contact c = byEmail('avi@example.com');
    Assert.areEqual(c.Id, r.contactId);
    Assert.areEqual('Phone', r.method);
    Assert.areEqual('avi@example.com', c.Email, 'email is never overwritten');
    Assert.isTrue(c.Needs_Review__c);
    Assert.isTrue(c.Review_Reason__c.contains('אימייל שונה: other@example.com'), c.Review_Reason__c);
  }

  @IsTest
  static void matchesByTaxIdHashOnly() {
    ContactMatcher.skipDuplicateRules = true;
    Contact withId = new Contact(LastName = 'Mizrahi', Donor_Tax_Id__c = VALID_ID);
    insert withId;
    ContactMatcher.Result r = ContactMatcher.matchOrCreate(input('new@example.com', '0527777777', VALID_ID));
    Assert.areEqual(withId.Id, r.contactId);
    Assert.areEqual('TaxId', r.method);
  }

  @IsTest
  static void conflictingKeysPickEmailAndFlagReview() {
    ContactMatcher.skipDuplicateRules = true;
    // email → Avi, phone → Ben (TC04); both named Avi, so both are candidates (N126)
    update new Contact(Id = byEmail('ben@example.com').Id, FirstName = 'Avi');
    ContactMatcher.Result r = ContactMatcher.matchOrCreate(input('avi@example.com', '0522222222', null));
    Contact avi = byEmail('avi@example.com');
    Contact ben = byEmail('ben@example.com');
    Assert.areEqual(avi.Id, r.contactId);
    Assert.areEqual('Email', r.method);
    Assert.isTrue(avi.Needs_Review__c);
    Assert.isTrue(avi.Review_Reason__c.contains('נמצאו 2 תורמים מתאימים'), avi.Review_Reason__c);
    Assert.isTrue(avi.Review_Reason__c.contains(ben.Id), 'review lists both ids');
  }

  @IsTest
  static void differentTaxIdIsNotOverwritten() {
    ContactMatcher.skipDuplicateRules = true;
    Contact c = new Contact(LastName = 'Peretz', Email = 'peretz@example.com', Donor_Tax_Id__c = VALID_ID);
    insert c;
    ContactMatcher.matchOrCreate(input('peretz@example.com', null, '000000018'));
    c = byEmail('peretz@example.com');
    Assert.areEqual(VALID_ID, c.Donor_Tax_Id__c);
    Assert.isTrue(c.Review_Reason__c.contains('ת"ז שונה'));
  }

  @IsTest
  static void createsNewDonorWhenNothingMatches() {
    ContactMatcher.skipDuplicateRules = true;
    ContactMatcher.Result r = ContactMatcher.match(input('fresh@example.com', '0523333333', VALID_ID));
    Assert.isTrue(r.created);
    Assert.areEqual('New', r.method);
    Contact c = [SELECT Donor_Source__c, Donor_Tax_Id__c, Email_Normalized__c, Tax_Id_Hash__c FROM Contact WHERE Id = :r.contactId];
    Assert.areEqual('WP_Micro', c.Donor_Source__c);
    Assert.areEqual(VALID_ID, c.Donor_Tax_Id__c);
    Assert.areEqual('fresh@example.com', c.Email_Normalized__c);
    Assert.areEqual(ContactMatcher.taxIdHash(VALID_ID), c.Tax_Id_Hash__c);
  }

  @IsTest
  static void duplicateRuleLookupDoesNotFailWithoutActiveRule() {
    // Real FindDuplicates path: must never throw, whatever rules the org has.
    ContactMatcher.Result r = ContactMatcher.matchOrCreate(input('ben@example.com', null, null));
    Assert.isNotNull(r.contactId);
  }

  @IsTest
  static void sameEmailOtherFirstNameIsANewDonor() {
    // N126: a family member using the same email gets their own Contact; both are flagged for review
    ContactMatcher.skipDuplicateRules = true;
    Contact avi = byEmail('avi@example.com');
    ContactMatcher.Result r = ContactMatcher.matchOrCreate(input('Sara', 'avi@example.com', '0521111111', null));
    Assert.isTrue(r.created);
    Assert.areEqual('New', r.method);
    Contact sara = [SELECT FirstName, Email, Needs_Review__c, Review_Reason__c FROM Contact WHERE Id = :r.contactId];
    Assert.areEqual('Sara', sara.FirstName);
    Assert.isTrue(sara.Needs_Review__c);
    Assert.isTrue(sara.Review_Reason__c.contains(avi.Id), sara.Review_Reason__c);
    avi = [SELECT FirstName, Needs_Review__c, Review_Reason__c FROM Contact WHERE Id = :avi.Id];
    Assert.areEqual('Avi', avi.FirstName, 'the existing donor is not changed');
    Assert.isTrue(avi.Needs_Review__c);
    Assert.isTrue(avi.Review_Reason__c.contains(sara.Id), avi.Review_Reason__c);

    // Sara again: now she matches her own Contact, not Avi's
    ContactMatcher.Result again = ContactMatcher.matchOrCreate(input(' sara ', 'avi@example.com', null, null));
    Assert.areEqual(sara.Id, again.contactId);
    Assert.areEqual('Email', again.method);
  }

  @IsTest
  static void samePhoneOtherFirstNameIsANewDonor() {
    ContactMatcher.skipDuplicateRules = true;
    ContactMatcher.Result r = ContactMatcher.matchOrCreate(input('Dan', 'dan@example.com', '052-111-1111', null));
    Assert.isTrue(r.created);
  }

  @IsTest
  static void firstNameSpellingNoiseStillMatches() {
    ContactMatcher.skipDuplicateRules = true;
    Contact c = TestDataFactory.contact('בן-ציון', 'Katz', 'bz@example.com', null);
    Assert.areEqual(c.Id, ContactMatcher.matchOrCreate(input('בן ציון', 'BZ@example.com', null, null)).contactId);
    Contact noFirst = new Contact(LastName = 'Gold', Email = 'gold@example.com');
    insert noFirst;
    ContactMatcher.Result r = ContactMatcher.matchOrCreate(input('Moshe', 'gold@example.com', null, null));
    Assert.areEqual(noFirst.Id, r.contactId, 'a Contact without a first name still matches');
    Assert.areEqual('Moshe', [SELECT FirstName FROM Contact WHERE Id = :noFirst.Id].FirstName, 'blank first name is filled');
    Assert.areEqual('benzion', ContactMatcher.normName(' Ben-Zi\'on. '));
    Assert.areEqual('יצחק', ContactMatcher.normName('יצ״חק'));
    Assert.isNull(ContactMatcher.normName(' - '));
  }

  @IsTest
  static void israeliIdMatchesEvenWithAnotherFirstName() {
    ContactMatcher.skipDuplicateRules = true;
    Contact withId = new Contact(FirstName = 'Yossi', LastName = 'Mizrahi', Donor_Tax_Id__c = VALID_ID);
    insert withId;
    ContactMatcher.Result r = ContactMatcher.matchOrCreate(input('Yosef', 'yosef@example.com', null, VALID_ID));
    Assert.areEqual(withId.Id, r.contactId);
    Assert.areEqual('TaxId', r.method);
    Assert.areEqual(0, ContactMatcher.rank(new Contact(FirstName = 'X', Email_Normalized__c = 'a'), 'a', null, null, 'Y'));
  }

  @IsTest
  static void reviewReasonAccumulates() {
    String first = ContactMatcher.appendReason(null, 'one');
    String second = ContactMatcher.appendReason(first, 'two');
    Assert.areEqual(2, second.split('\n').size());
    Assert.isTrue(second.endsWith(' two'));
    Assert.isTrue(ContactMatcher.appendReason('x'.repeat(2000), 'new').endsWith(' new'), 'keeps the newest text');
    Assert.areEqual(9, ContactMatcher.rank(new Contact(), 'a', 'b', 'c'));
  }
}
