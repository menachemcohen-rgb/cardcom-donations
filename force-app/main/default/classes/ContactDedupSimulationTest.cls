/**
 * Duplicate-prevention simulation for donor matching (B6.4, TC02–TC04): many spellings of the same donor must land on the
 * same Contact, and a new donor is created exactly once. Runs the SOQL path and the org's real duplicate-rule path.
 */
@IsTest
private class ContactDedupSimulationTest {
  static final String VALID_ID = '000000018';

  class Scenario {
    String name, email, phone, taxId, expectKey;
    Scenario(String name, String email, String phone, String taxId, String expectKey) {
      this.name = name;
      this.email = email;
      this.phone = phone;
      this.taxId = taxId;
      this.expectKey = expectKey;
    }
  }

  /** Existing donors with messy data: upper-case email, +972 mobile, landline-style Phone field only, ID only, email only. */
  static Map<String, Id> seed() {
    Database.DMLOptions o = new Database.DMLOptions();
    o.DuplicateRuleHeader.allowSave = true;
    List<Contact> cs = new List<Contact>{
      new Contact(FirstName = 'Avi', LastName = 'Cohen', Email = 'Avi@Example.COM', MobilePhone = '+972-52-111-1111'),
      new Contact(FirstName = 'Ben', LastName = 'Levi', Email = 'ben@example.com', Phone = '052 222 2222'),
      new Contact(LastName = 'Mizrahi', Donor_Tax_Id__c = VALID_ID),
      new Contact(FirstName = 'Dana', LastName = 'Katz', Email = 'dana@example.com')
    };
    Database.insert(cs, o);
    return new Map<String, Id>{ 'A' => cs[0].Id, 'B' => cs[1].Id, 'C' => cs[2].Id, 'D' => cs[3].Id };
  }

  static List<Scenario> scenarios() {
    return new List<Scenario>{
      new Scenario('email case + spaces', '  AVI@example.com ', null, null, 'A'),
      new Scenario('mobile local', 'n1@example.com', '0521111111', null, 'A'),
      new Scenario('mobile 972', 'n2@example.com', '972521111111', null, 'A'),
      new Scenario('mobile 00972 dashes', 'n3@example.com', '00972-52-1111111', null, 'A'),
      new Scenario('mobile no leading 0', 'n4@example.com', '52 111 1111', null, 'A'),
      new Scenario('phone stored in Phone field', 'n5@example.com', '052-2222222', null, 'B'),
      new Scenario('ID short form', 'n6@example.com', null, '18', 'C'),
      new Scenario('ID padded', 'n7@example.com', null, VALID_ID, 'C'),
      new Scenario('email upper, new mobile', 'DANA@EXAMPLE.COM', '0529990000', null, 'D'),
      new Scenario('new donor', 'fresh@example.com', '0523334444', null, 'NEW'),
      new Scenario('new donor again: case', 'FRESH@example.com', null, null, 'NEW'),
      new Scenario('new donor again: phone only', 'other-fresh@example.com', '+972 52-333-4444', null, 'NEW'),
      new Scenario('new donor again: both', ' Fresh@Example.com', '052-333-4444', null, 'NEW')
    };
  }

  static void runAll(Boolean skipRules) {
    ContactMatcher.skipDuplicateRules = skipRules;
    Map<String, Id> ids = seed();
    Integer before = [SELECT COUNT() FROM Contact];
    List<String> failures = new List<String>();
    for (Scenario s : scenarios()) {
      ContactMatcher.Result r = ContactMatcher.matchOrCreate(new ContactMatcher.DonorInput('Form', 'Donor', s.email, s.phone, s.taxId));
      if (s.expectKey == 'NEW' && !ids.containsKey('NEW')) {
        if (!r.created)
          failures.add(s.name + ': expected a new Contact');
        ids.put('NEW', r.contactId);
      } else if (r.contactId != ids.get(s.expectKey)) {
        failures.add(s.name + ': expected ' + s.expectKey + ', got ' + r.contactId + ' (' + r.method + ')');
      }
    }
    Assert.isTrue(failures.isEmpty(), String.join(failures, '\n'));
    Assert.areEqual(before + 1, [SELECT COUNT() FROM Contact], 'only the one genuinely new donor was created');
    Contact a = [SELECT Email, MobilePhone, FirstName FROM Contact WHERE Id = :ids.get('A')];
    Assert.areEqual('Avi@Example.COM', a.Email, 'existing values are never overwritten');
    Assert.areEqual('Avi', a.FirstName);
  }

  @IsTest
  static void soqlPathNeverDuplicates() {
    runAll(true);
  }

  @IsTest
  static void duplicateRulePathNeverDuplicates() {
    runAll(false); // FindDuplicates with whatever rules the org has, plus the SOQL complement
  }

  @IsTest
  static void sameDonorThreePledgesInOneJobGetsOneContact() {
    TestDataFactory.settings();
    ContactMatcher.skipDuplicateRules = true;
    List<Opportunity> ps = new List<Opportunity>{
      TestDataFactory.withToken(TestDataFactory.submittedPledge('lp-dedup-000001', 'Same@Example.com', '0524445555')),
      TestDataFactory.withToken(TestDataFactory.submittedPledge('lp-dedup-000002', 'same@example.com', '+972524445555')),
      TestDataFactory.withToken(TestDataFactory.submittedPledge('lp-dedup-000003', 'another@example.com', '052-444-5555'))
    };
    insert ps;
    Integer before = [SELECT COUNT() FROM Contact];
    Test.startTest();
    System.enqueueJob(new PledgeActivationJob(new List<Id>{ ps[0].Id, ps[1].Id, ps[2].Id }));
    Test.stopTest();
    Assert.areEqual(before + 1, [SELECT COUNT() FROM Contact], 'one donor Contact for three pledges');
    Set<Id> donors = new Set<Id>();
    for (Opportunity o : [SELECT Donor_Contact__c, StageName FROM Opportunity WHERE Id IN :ps]) {
      Assert.areEqual('Active', o.StageName);
      donors.add(o.Donor_Contact__c);
    }
    Assert.areEqual(1, donors.size());
  }

  @IsTest
  static void laterPledgeOfExistingDonorReusesContact() {
    TestDataFactory.settings();
    ContactMatcher.skipDuplicateRules = true;
    Opportunity first = TestDataFactory.withToken(TestDataFactory.submittedPledge('lp-dedup-000010', 'repeat@example.com', '0526667777'));
    insert first;
    Assert.isTrue(PledgeActivationService.tryActivate(first.Id));
    Id donor = [SELECT Donor_Contact__c FROM Opportunity WHERE Id = :first.Id].Donor_Contact__c;

    Opportunity second = TestDataFactory.withToken(TestDataFactory.submittedPledge('lp-dedup-000011', 'REPEAT@example.com', '0526667777'));
    insert second;
    Assert.isTrue(PledgeActivationService.tryActivate(second.Id));
    Opportunity s = [SELECT Donor_Contact__c, Match_Method__c FROM Opportunity WHERE Id = :second.Id];
    Assert.areEqual(donor, s.Donor_Contact__c);
    Assert.areEqual('Email', s.Match_Method__c);
    Assert.areEqual(1, [SELECT COUNT() FROM Contact WHERE Email_Normalized__c = 'repeat@example.com']);
  }
}
