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
    String ext = 'PLG-' + String.valueOf(once[0].Id) + '-20261104-AM';
    Assert.areEqual(ext, c.ExternalUniqTranId__c, 'B2.3 format with the 18-character Id (N85)');
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
  static void fridayShacharitRunChargesOnlyFriday() {
    // D36: Shabbat goes with the eve's Mincha run
    TestDataFactory.chargeEngine(TestDataFactory.FRI_0600);
    TestDataFactory.activePledges(1, 'OnceDaily');
    TestDataFactory.activePledges(1, 'TwiceDaily');
    Assert.areEqual(2, ChargePlanner.plan(FRI, 'AM'));
    for (Charge__c c : charges()) {
      Assert.areEqual(FRI, c.Scheduled_Date__c);
      Assert.areEqual('AM', c.Slot__c);
    }
  }

  @IsTest
  static void fridayMinchaRunChargesFridayMinchaAndAllOfShabbat() {
    // TC12 (D36): Shacharit-only → Shabbat Shacharit; both → Friday Mincha + Shabbat Shacharit and Mincha; Mincha-only → Friday + Shabbat Mincha
    TestDataFactory.chargeEngine(Datetime.newInstance(2026, 11, 6, 11, 0, 0));
    Opportunity once = TestDataFactory.activePledges(1, 'OnceDaily')[0];
    Opportunity both = TestDataFactory.activePledges(1, 'TwiceDaily')[0];
    Opportunity mincha = TestDataFactory.activePledges(1, 'MinchaOnly')[0];
    Assert.areEqual(1 + 3 + 2, ChargePlanner.plan(FRI, 'PM'));
    Map<Id, List<String>> got = new Map<Id, List<String>>();
    for (Charge__c c : charges()) {
      if (!got.containsKey(c.Pledge__c))
        got.put(c.Pledge__c, new List<String>());
      got.get(c.Pledge__c).add(String.valueOf(c.Scheduled_Date__c.day()) + c.Slot__c);
      Assert.areEqual(FRI, c.Run_Date__c, 'all sent on Friday');
    }
    Assert.areEqual(new List<String>{ '7AM' }, got.get(once.Id));
    Assert.areEqual(new Set<String>{ '6PM', '7AM', '7PM' }, new Set<String>(got.get(both.Id)));
    Assert.areEqual(new Set<String>{ '6PM', '7PM' }, new Set<String>(got.get(mincha.Id)));
  }

  @IsTest
  static void erevRoshHashanaMinchaRunChargesTheTwoDaysOfChag() {
    // TC13 (D36): 11.9 Friday, 12–13.9 Rosh Hashana + Shabbat
    TestDataFactory.chargeEngine(Datetime.newInstance(2026, 9, 11, 11, 0, 0));
    TestDataFactory.activePledges(1, 'OnceDaily');
    Assert.areEqual(1, ChargePlanner.plan(Date.newInstance(2026, 9, 11), 'AM'));
    Assert.areEqual(2, ChargePlanner.plan(Date.newInstance(2026, 9, 11), 'PM'));
  }

  @IsTest
  static void minchaOnlyIsChargedOnlyInMinchaWithItsAmount() {
    TestDataFactory.chargeEngine(TestDataFactory.WED_0800);
    Opportunity m = TestDataFactory.activePledges(1, 'MinchaOnly')[0];
    update new Opportunity(Id = m.Id, Charge_Amount__c = null, Mincha_Amount__c = 7);
    Assert.areEqual(0, ChargePlanner.plan(WED, 'AM'));
    Assert.areEqual(1, ChargePlanner.plan(WED, 'PM'));
    Assert.areEqual(7, [SELECT Amount__c FROM Charge__c].Amount__c.intValue());
  }

  @IsTest
  static void separateShacharitAndMinchaAmounts() {
    TestDataFactory.chargeEngine(TestDataFactory.WED_0800);
    Opportunity b = TestDataFactory.activePledges(1, 'TwiceDaily')[0];
    update new Opportunity(Id = b.Id, Charge_Amount__c = 2, Mincha_Amount__c = 5);
    ChargePlanner.plan(WED, 'AM');
    ChargePlanner.plan(WED, 'PM');
    Map<String, Decimal> bySlot = new Map<String, Decimal>();
    for (Charge__c c : charges())
      bySlot.put(c.Slot__c, c.Amount__c);
    Assert.areEqual(2, bySlot.get('AM').intValue());
    Assert.areEqual(5, bySlot.get('PM').intValue());
  }

  @IsTest
  static void oneRunADayPlansEverySlot() {
    TestDataFactory.chargeEngine(TestDataFactory.FRI_0600);
    TestDataFactory.activePledges(1, 'TwiceDaily');
    Assert.areEqual(4, ChargePlanner.plan(FRI, 'AM', true), 'Friday and Shabbat, Shacharit and Mincha');
  }

  @IsTest
  static void runSlotsOnARegularDayAndOnAnEve() {
    Assert.areEqual(1, ChargePlanner.runSlots(WED, 'AM', false).size());
    Assert.areEqual(1, ChargePlanner.runSlots(WED, 'PM', false).size());
    Assert.areEqual(1, ChargePlanner.runSlots(FRI, 'AM', false).size());
    Assert.areEqual(3, ChargePlanner.runSlots(FRI, 'PM', false).size());
    Assert.areEqual(0, ChargePlanner.runSlots(FRI.addDays(1), 'PM', false).size(), 'Shabbat');
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
    Assert.isTrue(
      ChargePlanner.buildAll(new List<Opportunity>{ noToken }, new List<ChargePlanner.RunSlot>{ new ChargePlanner.RunSlot(WED, 'AM') }, WED)
        .isEmpty()
    );
  }

  @IsTest
  static void bulkFridayStaysInsideLimits() {
    TestDataFactory.chargeEngine(Datetime.newInstance(2026, 11, 6, 11, 0, 0));
    TestDataFactory.activePledges(200, 'TwiceDaily');
    Integer dmlBefore = Limits.getDmlStatements();
    Integer queriesBefore = Limits.getQueries();
    Assert.areEqual(600, ChargePlanner.plan(FRI, 'PM'), 'Friday Mincha + Shabbat Shacharit and Mincha');
    Assert.isTrue(Limits.getQueries() - queriesBefore <= 6, 'planning uses a constant number of queries');
    Assert.isTrue(Limits.getDmlStatements() - dmlBefore <= 3, 'one insert for all attempts (+ the lock)');
    Assert.areEqual(600, [SELECT COUNT() FROM Charge__c]);
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
