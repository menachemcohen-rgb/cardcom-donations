@IsTest
private class PledgeActivationServiceTest {
  @IsTest
  static void activatesOnlyWhenSubmittedAndVerified() {
    TestDataFactory.settings();
    ContactMatcher.skipDuplicateRules = true;
    Opportunity notSubmitted = TestDataFactory.withToken(TestDataFactory.pledge('lp-0000000001'));
    Opportunity notVerified = TestDataFactory.submittedPledge('lp-0000000002', 'a@example.com', '0521234567');
    insert new List<Opportunity>{ notSubmitted, notVerified };
    Assert.isFalse(PledgeActivationService.tryActivate(notSubmitted.Id));
    Assert.isFalse(PledgeActivationService.tryActivate(notVerified.Id));
    Opportunity other = TestDataFactory.otherOpportunity(); // null when the org has no non-pledge record type for this user
    if (other != null)
      Assert.isFalse(PledgeActivationService.tryActivate(other.Id), 'non-pledge Opportunity ignored');
  }

  @IsTest
  static void activationLinksExistingDonorAndAddsContactRole() {
    TestDataFactory.settings();
    ContactMatcher.skipDuplicateRules = true;
    Contact existing = TestDataFactory.contact('Avi', 'Cohen', 'avi@example.com', '0521111111');
    Opportunity p = TestDataFactory.withToken(TestDataFactory.submittedPledge('lp-0000000001', 'avi@example.com', '0529999999'));
    insert p;
    Assert.isTrue(PledgeActivationService.activate(p.Id));
    Opportunity a = [
      SELECT StageName, Donor_Contact__c, Match_Method__c, CloseDate, Start_Date__c, Name, Pledge_Number__c
      FROM Opportunity
      WHERE Id = :p.Id
    ];
    Assert.areEqual('Active', a.StageName);
    Assert.areEqual(existing.Id, a.Donor_Contact__c);
    Assert.areEqual('Email', a.Match_Method__c);
    Assert.areEqual(Date.today(), a.CloseDate);
    Assert.areEqual(Date.today(), a.Start_Date__c);
    Assert.areEqual(MicroPledges.fullName('ישראלי', 'ישראל', a.Pledge_Number__c), a.Name);
    OpportunityContactRole r = [SELECT ContactId, Role, IsPrimary FROM OpportunityContactRole WHERE OpportunityId = :p.Id];
    Assert.areEqual(existing.Id, r.ContactId);
    Assert.areEqual('Donor', r.Role);
    Assert.isTrue(r.IsPrimary);

    Assert.isFalse(PledgeActivationService.tryActivate(p.Id), 'idempotent');
    Assert.areEqual(1, [SELECT COUNT() FROM OpportunityContactRole WHERE OpportunityId = :p.Id]);
  }

  @IsTest
  static void jobActivatesAList() {
    TestDataFactory.settings();
    ContactMatcher.skipDuplicateRules = true;
    Opportunity a = TestDataFactory.withToken(TestDataFactory.submittedPledge('lp-0000000001', 'a@example.com', '0521234567'));
    Opportunity b = TestDataFactory.withToken(TestDataFactory.submittedPledge('lp-0000000002', 'b@example.com', '0527654321'));
    insert new List<Opportunity>{ a, b };
    Test.startTest();
    System.enqueueJob(new PledgeActivationJob(new List<Id>{ a.Id, b.Id }));
    Test.stopTest();
    Assert.areEqual(2, [SELECT COUNT() FROM Opportunity WHERE StageName = 'Active']);
    Assert.isTrue(PledgeActivationService.hasHeadroom());
  }
}
