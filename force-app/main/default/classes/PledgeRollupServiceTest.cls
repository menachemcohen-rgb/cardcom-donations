@IsTest
private class PledgeRollupServiceTest {
  static Opportunity pledge;
  static Integer seq = 0;

  static void setup() {
    TestDataFactory.chargeEngine(TestDataFactory.WED_0800);
    pledge = TestDataFactory.activePledges(1, 'TwiceDaily')[0];
  }

  /** One logical charge (day offset from 2026-11-01, AM) with its attempts' final state; inserting fires ChargeTrigger → recalc. */
  static void logical(Integer day, String status, Boolean finalFailure) {
    Charge__c c = TestDataFactory.charge(pledge, Date.newInstance(2026, 11, day), 'AM');
    c.Status__c = status;
    c.Is_Final_Failure__c = finalFailure;
    c.Executed_At__c = Datetime.now().addMinutes(seq++);
    insert c;
  }

  static Opportunity reload() {
    return [
      SELECT
        StageName,
        Amount,
        Total_Collected__c,
        Successful_Charge_Count__c,
        Last_Successful_Charge_Date__c,
        Consecutive_Failures__c,
        Failure_Alert_Sent_At__c
      FROM Opportunity
      WHERE Id = :pledge.Id
    ];
  }

  @IsTest
  static void totalsMirrorAmountAndUseTheScheduledDate() {
    setup();
    logical(1, 'Success', false);
    logical(2, 'Success', false);
    logical(3, 'Failed', true);
    Opportunity p = reload();
    Assert.areEqual(6, p.Total_Collected__c.intValue());
    Assert.areEqual(6, p.Amount.intValue(), 'standard Amount mirrors Total_Collected__c (D25)');
    Assert.areEqual(2, p.Successful_Charge_Count__c.intValue());
    Assert.areEqual(Date.newInstance(2026, 11, 2), p.Last_Successful_Charge_Date__c, 'MAX(Scheduled_Date__c) (B6.7, N14)');
    Assert.areEqual(1, p.Consecutive_Failures__c.intValue());
  }

  @IsTest
  static void threeFailuresAlertOnceAndTheFourthDoesNot() {
    // TC18
    setup();
    logical(1, 'Failed', true);
    logical(2, 'Failed', true);
    Assert.isNull(reload().Failure_Alert_Sent_At__c);
    logical(3, 'Failed', true);
    Opportunity p = reload();
    Assert.areEqual(3, p.Consecutive_Failures__c.intValue());
    Assert.isNotNull(p.Failure_Alert_Sent_At__c);
    Assert.areEqual(1, StaffAlertService.sentCount);
    Assert.areEqual('Active', p.StageName, 'no automatic stop (D9)');
    logical(4, 'Failed', true);
    Assert.areEqual(4, reload().Consecutive_Failures__c.intValue());
    Assert.areEqual(1, StaffAlertService.sentCount, 'one alert per streak');
  }

  @IsTest
  static void successResetsTheStreakAndReArmsTheAlert() {
    // TC19
    setup();
    logical(1, 'Failed', true);
    logical(2, 'Failed', true);
    logical(3, 'Failed', true);
    logical(4, 'Success', false);
    Opportunity p = reload();
    Assert.areEqual(0, p.Consecutive_Failures__c.intValue());
    Assert.isNull(p.Failure_Alert_Sent_At__c);
  }

  @IsTest
  static void skippedConfigAndPendingAreNeutral() {
    setup();
    logical(1, 'Failed', true);
    logical(2, 'Skipped', false); // STOPPED / duplicate: neither counts nor breaks
    logical(3, 'Failed', false); // Config failure: not final, not counted
    logical(4, 'Failed', true);
    Assert.areEqual(2, reload().Consecutive_Failures__c.intValue());

    // A logical charge still retrying (A1 failed, A2 pending) is not counted yet.
    Charge__c a1 = TestDataFactory.charge(pledge, Date.newInstance(2026, 11, 5), 'AM');
    a1.Status__c = 'Failed';
    Charge__c a2 = TestDataFactory.charge(pledge, Date.newInstance(2026, 11, 5), 'AM');
    a2.Attempt_Number__c = 2;
    a2.Attempt_Key__c = a2.ExternalUniqTranId__c + '-A2';
    insert new List<Charge__c>{ a1, a2 };
    Assert.areEqual(2, reload().Consecutive_Failures__c.intValue());
  }

  @IsTest
  static void retriedLogicalChargeThatSucceedsCountsAsSuccess() {
    setup();
    logical(1, 'Failed', true);
    Charge__c a1 = TestDataFactory.charge(pledge, Date.newInstance(2026, 11, 2), 'AM');
    a1.Status__c = 'Failed';
    Charge__c a2 = TestDataFactory.charge(pledge, Date.newInstance(2026, 11, 2), 'AM');
    a2.Attempt_Number__c = 2;
    a2.Attempt_Key__c = a2.ExternalUniqTranId__c + '-A2';
    a2.Status__c = 'Success';
    insert new List<Charge__c>{ a1, a2 };
    Opportunity p = reload();
    Assert.areEqual(0, p.Consecutive_Failures__c.intValue());
    Assert.areEqual(1, p.Successful_Charge_Count__c.intValue());
  }

  @IsTest
  static void otherOpportunitiesAreIgnored() {
    setup();
    Opportunity other = TestDataFactory.otherOpportunity();
    PledgeRollupService.recalc(new Set<Id>{ other.Id });
    PledgeRollupService.recalc(new Set<Id>());
    Assert.isNull([SELECT Amount FROM Opportunity WHERE Id = :other.Id].Amount);
  }
}
