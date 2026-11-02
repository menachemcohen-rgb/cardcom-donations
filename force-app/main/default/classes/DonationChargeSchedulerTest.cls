@IsTest
private class DonationChargeSchedulerTest {
  static final Date WED = Date.newInstance(2026, 11, 4);
  static final Date FRI = Date.newInstance(2026, 11, 6);
  static final Date SAT = Date.newInstance(2026, 11, 7);

  static void setup() {
    TestDataFactory.settings();
    ChargeCalendar.todayOverride = Date.newInstance(2026, 11, 1);
    ChargeCalendar.manualOverridesForTest = new List<Charge_Holiday__mdt>();
    ChargeSettings.overrideValue = ChargeSettings.defaults();
  }

  @IsTest
  static void runsOnlyOnItsDays() {
    setup();
    Assert.isTrue(new DonationChargeScheduler('AM').run(WED));
    Assert.isTrue(new DonationChargeScheduler('PM').run(WED));
    Assert.isFalse(new DonationChargeScheduler('EveAM').run(WED));
    Assert.isTrue(new DonationChargeScheduler('EveAM').run(FRI));
    Assert.isTrue(new DonationChargeScheduler('EvePM').run(FRI));
    Assert.isFalse(new DonationChargeScheduler('AM').run(FRI));
    Assert.isFalse(new DonationChargeScheduler('EveAM').run(SAT));
    Assert.isFalse(new DonationChargeScheduler('AM').run(Date.newInstance(2026, 9, 12)), 'Rosh Hashana (TC14)');
  }

  @IsTest
  static void emergencySwitchStopsEveryRun() {
    setup();
    ChargeSettings.overrideValue.Charging_Enabled__c = false;
    Assert.isFalse(new DonationChargeScheduler('AM').run(WED));
    Assert.isFalse(new DonationChargeScheduler('EveAM').run(FRI));
  }

  @IsTest
  static void oneRunPerDaySkipsEveningRuns() {
    setup();
    ChargeSettings.overrideValue.Runs_Per_Day__c = 1;
    Assert.isFalse(new DonationChargeScheduler('PM').run(WED));
    Assert.isFalse(new DonationChargeScheduler('EvePM').run(FRI));
    Assert.isTrue(new DonationChargeScheduler('AM').run(WED));
    Assert.isTrue(new DonationChargeScheduler('EveAM').run(FRI));
  }

  @IsTest
  static void rejectsUnknownKind() {
    try {
      new DonationChargeScheduler('Noon');
      Assert.fail('expected IllegalArgumentException');
    } catch (IllegalArgumentException e) {
      Assert.isTrue(e.getMessage().contains('Noon'));
    }
  }

  @IsTest
  static void executesWhenScheduled() {
    setup();
    Test.startTest();
    String id = System.schedule('Test charge run', '0 0 8 ? * SUN-FRI', new DonationChargeScheduler('AM'));
    Test.stopTest();
    Assert.isNotNull(id);
  }
}
