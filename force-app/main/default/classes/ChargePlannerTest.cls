@IsTest
private class ChargePlannerTest {
  static final Date WED = Date.newInstance(2026, 11, 4);
  static final Date FRI = Date.newInstance(2026, 11, 6);

  static List<Charge__c> charges() {
    return [
      SELECT
        Pledge__c,
        Contact__c,
        Amount__c,
        Scheduled_Date__c,
        Run_Date__c,
        Slot__c,
        Status__c,
        Attempt_Number__c,
        ExternalUniqTranId__c,
        Attempt_Key__c,
        Not_Before__c
      FROM Charge__c
      ORDER BY Scheduled_Date__c, Slot__c
    ];
  }

  @IsTest
  static void regularMorningPlansOneAttemptPerPledge() {
    TestDataFactory.chargeEngine(TestDataFactory.WED_0800);
    List<Opportunity> once = TestDataFactory.activePledges(2, 'OnceDaily');
    TestDataFactory.activePledges(1, 'TwiceDaily');
    Assert.areEqual(3, ChargePlanner.plan(WED, 'AM'));
    Charge__c c = [
      SELECT
        Amount__c,
        Contact__c,
        Scheduled_Date__c,
        Run_Date__c,
        Slot__c,
        Status__c,
        Attempt_Number__c,
        ExternalUniqTranId__c,
        Attempt_Key__c,
        Not_Before__c
      FROM Charge__c
      WHERE Pledge__c = :once[0].Id
    ];
    String ext = 'PLG-' + String.valueOf(once[0].Id).left(15) + '-20261104-AM';
    Assert.areEqual(ext, c.ExternalUniqTranId__c, 'B2.3 format with the 15-character Id (N15)');
    Assert.areEqual(ext + '-A1', c.Attempt_Key__c);
    Assert.areEqual(3, c.Amount__c.intValue(), 'Charge_Amount__c snapshot (D16)');
    Assert.areEqual(once[0].Donor_Contact__c, c.Contact__c);
    Assert.areEqual('Pending', c.Status__c);
    Assert.areEqual(1, c.Attempt_Number__c.intValue());
    Assert.areEqual(WED, c.Run_Date__c);
    Assert.areEqual(TestDataFactory.WED_0800, c.Not_Before__c);
  }

  @IsTest
  static void eveningRunOnlyForTwiceDaily() {
    TestDataFactory.chargeEngine(Datetime.newInstance(2026, 11, 4, 20, 0, 0));
    TestDataFactory.activePledges(2, 'OnceDaily');
    List<Opportunity> twice = TestDataFactory.activePledges(1, 'TwiceDaily');
    Assert.areEqual(1, ChargePlanner.plan(WED, 'PM'));
    Assert.areEqual(twice[0].Id, [SELECT Pledge__c FROM Charge__c].Pledge__c);
  }

  @IsTest
  static void fridayChargesFridayAndShabbat() {
    // TC12
    TestDataFactory.chargeEngine(TestDataFactory.FRI_0600);
    Opportunity p = TestDataFactory.activePledges(1, 'OnceDaily')[0];
    Assert.areEqual(2, ChargePlanner.plan(FRI, 'AM'));
    List<Charge__c> cs = charges();
    Assert.areEqual(FRI, cs[0].Scheduled_Date__c);
    Assert.areEqual(FRI.addDays(1), cs[1].Scheduled_Date__c);
    Assert.areNotEqual(cs[0].ExternalUniqTranId__c, cs[1].ExternalUniqTranId__c);
    Assert.areEqual(FRI, cs[1].Run_Date__c, 'Shabbat charge is sent on Friday');
  }

  @IsTest
  static void erevRoshHashanaChargesThreeDays() {
    // TC13
    TestDataFactory.chargeEngine(Datetime.newInstance(2026, 9, 11, 6, 0, 0));
    TestDataFactory.activePledges(1, 'OnceDaily');
    Assert.areEqual(3, ChargePlanner.plan(Date.newInstance(2026, 9, 11), 'AM'));
  }

  @IsTest
  static void restDayPlansNothingAndRerunIsIdempotent() {
    TestDataFactory.chargeEngine(TestDataFactory.WED_0800);
    TestDataFactory.activePledges(2, 'OnceDaily');
    Assert.areEqual(0, ChargePlanner.plan(Date.newInstance(2026, 11, 7), 'AM'), 'Shabbat');
    Assert.areEqual(2, ChargePlanner.plan(WED, 'AM'));
    Assert.areEqual(0, ChargePlanner.plan(WED, 'AM'), 'duplicate Attempt_Key__c ignored (B6.13 E8)');
    Assert.areEqual(2, [SELECT COUNT() FROM Charge__c]);
  }

  @IsTest
  static void onlyActivePledgesOfTheRecordTypeArePlanned() {
    TestDataFactory.chargeEngine(TestDataFactory.WED_0800);
    Contact c = TestDataFactory.contact('Ben', 'Levi', 'ben@example.com', '0522222222');
    Opportunity stopped = TestDataFactory.withToken(TestDataFactory.submittedPledge('lp-stopped-0001', c.Email, c.MobilePhone));
    stopped.StageName = 'Stopped';
    stopped.Stop_Reason__c = 'Donor_Request';
    stopped.Donor_Contact__c = c.Id;
    Opportunity ended = TestDataFactory.withToken(TestDataFactory.submittedPledge('lp-ended-00001', c.Email, c.MobilePhone));
    ended.StageName = 'Active';
    ended.Donor_Contact__c = c.Id;
    ended.End_Date__c = WED.addDays(-1);
    insert new List<Opportunity>{ stopped, ended };
    TestDataFactory.otherOpportunity();
    Assert.areEqual(0, ChargePlanner.plan(WED, 'AM'));
  }

  @IsTest
  static void amountChangeAfterPlanningKeepsTheSnapshot() {
    // D16 / B6.13 E11
    TestDataFactory.chargeEngine(TestDataFactory.WED_0800);
    Opportunity p = TestDataFactory.activePledges(1, 'OnceDaily')[0];
    ChargePlanner.plan(WED, 'AM');
    update new Opportunity(Id = p.Id, Charge_Amount__c = 5);
    Assert.areEqual(3, [SELECT Amount__c FROM Charge__c].Amount__c.intValue());
  }

  @IsTest
  static void blankTokenIsSkippedInApex() {
    // E15: no Token__c condition in the SOQL; checked here instead.
    Opportunity noToken = new Opportunity(Frequency__c = 'OnceDaily', Charge_Amount__c = 3);
    Assert.isTrue(ChargePlanner.buildAll(new List<Opportunity>{ noToken }, new List<Date>{ WED }, 'AM', WED).isEmpty());
  }

  @IsTest
  static void bulkFridayStaysInsideLimits() {
    TestDataFactory.chargeEngine(TestDataFactory.FRI_0600);
    TestDataFactory.activePledges(200, 'TwiceDaily');
    Integer dmlBefore = Limits.getDmlStatements();
    Integer queriesBefore = Limits.getQueries();
    Assert.areEqual(400, ChargePlanner.plan(FRI, 'AM'));
    Assert.isTrue(Limits.getQueries() - queriesBefore <= 6, 'planning uses a constant number of queries');
    Assert.isTrue(Limits.getDmlStatements() - dmlBefore <= 3, 'one insert for all attempts (+ the lock)');
    Assert.areEqual(400, [SELECT COUNT() FROM Charge__c]);
  }

  @IsTest
  static void largeVolumesPlanInABatch() {
    TestDataFactory.chargeEngine(TestDataFactory.WED_0800);
    TestDataFactory.activePledges(3, 'OnceDaily');
    CardcomMock.install().always('Transactions/Transaction', 200, TestDataFactory.txSuccess(1, '1234'));
    ChargePlanner.SYNC_MAX = 1;
    Test.startTest();
    Assert.areEqual(0, ChargePlanner.plan(WED, 'AM'), 'handed to ChargePlannerBatch');
    Test.stopTest();
    Assert.areEqual(3, [SELECT COUNT() FROM Charge__c]);
  }
}
