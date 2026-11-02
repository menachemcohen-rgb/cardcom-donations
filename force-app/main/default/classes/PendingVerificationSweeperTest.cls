@IsTest
private class PendingVerificationSweeperTest {
  @IsTest
  static void rechecksOldPendingPledges() {
    TestDataFactory.settings();
    insert TestDataFactory.submittedPledge('lp-0000000001', 'a@example.com', '0521234567');
    CardcomMock m = CardcomMock.install().always('LowProfile/GetLpResult', 200, CardcomMock.lpFailed('lp-0000000001'));
    PendingVerificationSweeper.nowOverride = Datetime.now().addMinutes(20);
    Test.startTest();
    PendingVerificationSweeper.sweep();
    Test.stopTest();
    Assert.areEqual(1, m.requestsTo('LowProfile/GetLpResult').size());
    Assert.areEqual(1, [SELECT Lp_Check_Count__c FROM Opportunity].Lp_Check_Count__c);
  }

  @IsTest
  static void ignoresFreshPledgesAndOtherOpportunities() {
    TestDataFactory.settings();
    insert TestDataFactory.submittedPledge('lp-0000000001', 'a@example.com', '0521234567');
    TestDataFactory.otherOpportunity();
    Test.startTest();
    PendingVerificationSweeper.sweep(); // now: the pledge is younger than 10 minutes
    Test.stopTest();
    Assert.areEqual(0, [SELECT COUNT() FROM AsyncApexJob WHERE ApexClass.Name IN ('CardcomLpResultJob', 'PledgeActivationJob')]);
  }

  @IsTest
  static void activatesVerifiedSubmittedPledgesLeftPending() {
    TestDataFactory.settings();
    ContactMatcher.skipDuplicateRules = true;
    Opportunity stuck = TestDataFactory.withToken(TestDataFactory.submittedPledge('lp-0000000001', 'a@example.com', '0521234567'));
    insert stuck;
    PendingVerificationSweeper.nowOverride = Datetime.now().addMinutes(20);
    Test.startTest();
    PendingVerificationSweeper.sweep();
    Test.stopTest();
    Assert.areEqual('Active', [SELECT StageName FROM Opportunity WHERE Id = :stuck.Id].StageName);
  }

  @IsTest
  static void scheduleAllCreatesFourJobs() {
    Test.startTest();
    PendingVerificationSweeper.scheduleAll();
    Test.stopTest();
    Assert.areEqual(4, [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name LIKE 'Donations LP Sweeper%']);
  }

  @IsTest
  static void cardChangeHelpers() {
    Assert.isTrue(CardChangeService.isCardChange('CARD-a0X'));
    Assert.isFalse(CardChangeService.isCardChange('SIGNUP-x'));
    CardChangeService.complete('lp', new Map<String, Object>());
    CardChangeService.expireStale();
  }
}
