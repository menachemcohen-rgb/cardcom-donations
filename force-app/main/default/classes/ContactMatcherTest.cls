@IsTest
private class ContactMatcherTest {
  static final String VALID_ID = '123456782';

  @TestSetup
  static void setup() {
    TestDataFactory.contact('Avi', 'Cohen', 'avi@example.com', '0521111111');
    TestDataFactory.contact('Ben', 'Levi', 'ben@example.com', '0522222222');
  }

  static ContactMatcher.DonorInput input(String email, String phone, String taxId) {
    return new ContactMatcher.DonorInput('Form', 'Donor', email, phone, taxId);
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
    Assert.isNull(ContactMatcher.normPhone('03-1234567'), 'landlines are not matched');
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
    // email → Avi, phone → Ben (TC04)
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
  static void reviewReasonAccumulates() {
    String first = ContactMatcher.appendReason(null, 'one');
    String second = ContactMatcher.appendReason(first, 'two');
    Assert.areEqual(2, second.split('\n').size());
    Assert.isTrue(second.endsWith(' two'));
    Assert.isTrue(ContactMatcher.appendReason('x'.repeat(2000), 'new').endsWith(' new'), 'keeps the newest text');
    Assert.areEqual(9, ContactMatcher.rank(new Contact(), 'a', 'b', 'c'));
  }
}
