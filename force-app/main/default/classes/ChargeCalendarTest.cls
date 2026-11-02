@IsTest
private class ChargeCalendarTest {
  /** Real auto-detect path pinned to 2026 (holidays of 2025–2027), no manual overrides. */
  static void setup2026() {
    TestDataFactory.settings();
    ChargeCalendar.todayOverride = Date.newInstance(2026, 11, 1);
    ChargeCalendar.manualOverridesForTest = new List<Charge_Holiday__mdt>();
  }

  static void assertDates(String runDate, List<Integer> days) {
    List<Date> got = ChargeCalendar.logicalDatesFor(Date.valueOf(runDate));
    List<Integer> gotDays = new List<Integer>();
    for (Date d : got)
      gotDays.add(d.day());
    Assert.areEqual(days, gotDays, 'logicalDatesFor(' + runDate + ')');
  }

  @IsTest
  static void multiplicityTableFromB66() {
    setup2026();
    assertDates('2026-09-11', new List<Integer>{ 11, 12, 13 }); // Fri, Erev RH → Fri + Shabbat/RH1 + RH2 (×3)
    assertDates('2026-09-20', new List<Integer>{ 20, 21 }); // Sun, Erev Yom Kippur (×2)
    assertDates('2026-09-25', new List<Integer>{ 25, 26 }); // Fri, Erev Sukkot on Shabbat (×2)
    assertDates('2026-10-02', new List<Integer>{ 2, 3 }); // Fri, Erev Shemini Atzeret on Shabbat (×2)
    assertDates('2026-04-01', new List<Integer>{ 1, 2 }); // Wed, Erev Pesach (×2)
    assertDates('2026-05-21', new List<Integer>{ 21, 22, 23 }); // Thu, Erev Shavuot on Friday (×3)
    assertDates('2026-11-06', new List<Integer>{ 6, 7 }); // regular Friday (×2)
    assertDates('2026-11-04', new List<Integer>{ 4 }); // regular Wednesday (×1)
    assertDates('2026-09-12', new List<Integer>()); // rest day: nothing
  }

  @IsTest
  static void shouldRunCasesFromB8() {
    setup2026();
    Date fri = Date.newInstance(2026, 11, 6), wed = Date.newInstance(2026, 11, 4), sat = Date.newInstance(2026, 11, 7);
    Assert.isTrue(ChargeCalendar.shouldRun('EveAM', fri));
    Assert.isTrue(ChargeCalendar.shouldRun('EvePM', fri));
    Assert.isFalse(ChargeCalendar.shouldRun('AM', fri));
    Assert.isFalse(ChargeCalendar.shouldRun('PM', fri));
    Assert.isTrue(ChargeCalendar.shouldRun('AM', wed));
    Assert.isTrue(ChargeCalendar.shouldRun('PM', wed));
    Assert.isFalse(ChargeCalendar.shouldRun('EveAM', wed));
    for (String k : ChargeCalendar.KINDS)
      Assert.isFalse(ChargeCalendar.shouldRun(k, sat), k + ' on Shabbat');
    Assert.isFalse(ChargeCalendar.shouldRun('Noon', wed));
    Assert.isTrue(ChargeCalendar.shouldRun('EveAM', Date.newInstance(2026, 9, 11)), 'Erev Rosh Hashana');
    Assert.isFalse(ChargeCalendar.shouldRun('AM', Date.newInstance(2026, 9, 13)), 'Rosh Hashana day 2 (Sunday)');
  }

  @IsTest
  static void slotsAndWeekdays() {
    Assert.areEqual('AM', ChargeCalendar.slotFor('AM'));
    Assert.areEqual('AM', ChargeCalendar.slotFor('EveAM'));
    Assert.areEqual('PM', ChargeCalendar.slotFor('PM'));
    Assert.areEqual('PM', ChargeCalendar.slotFor('EvePM'));
    try {
      ChargeCalendar.slotFor('X');
      Assert.fail('expected IllegalArgumentException');
    } catch (IllegalArgumentException e) {
      Assert.isTrue(e.getMessage().contains('X'));
    }
    Assert.areEqual(0, ChargeCalendar.dow(Date.newInstance(2026, 11, 1)), 'Sunday');
    Assert.areEqual(6, ChargeCalendar.dow(Date.newInstance(2026, 11, 7)), 'Saturday');
  }

  @IsTest
  static void manualOverridesAddAndRemoveRestDays() {
    setup2026();
    ChargeCalendar.manualOverridesForTest = new List<Charge_Holiday__mdt>{
      new Charge_Holiday__mdt(Date__c = Date.newInstance(2026, 9, 21), Mode__c = 'Remove_Rest_Day'), // Yom Kippur (Mon) removed
      new Charge_Holiday__mdt(Date__c = Date.newInstance(2026, 11, 4), Mode__c = 'Add_Rest_Day'), // e.g. election day
      new Charge_Holiday__mdt(Date__c = null, Mode__c = 'Add_Rest_Day')
    };
    Assert.isFalse(ChargeCalendar.isRestDay(Date.newInstance(2026, 9, 21)));
    Assert.isFalse(ChargeCalendar.isEve(Date.newInstance(2026, 9, 20)));
    Assert.isTrue(ChargeCalendar.isRestDay(Date.newInstance(2026, 11, 4)));
    Assert.isTrue(ChargeCalendar.isEve(Date.newInstance(2026, 11, 3)));
    Assert.areEqual(2, ChargeCalendar.logicalDatesFor(Date.newInstance(2026, 11, 3)).size());
  }

  @IsTest
  static void autoDetectCanBeTurnedOff() {
    setup2026();
    CardcomService.settingsOverride.Holiday_Auto_Detect__c = false;
    Assert.isFalse(ChargeCalendar.isRestDay(Date.newInstance(2026, 9, 21)), 'only Shabbat and manual overrides');
    Assert.isTrue(ChargeCalendar.isRestDay(Date.newInstance(2026, 9, 12)), 'Shabbat');
  }

  @IsTest
  static void holidaysOverrideWins() {
    ChargeCalendar.holidaysOverride = new Set<Date>{ Date.newInstance(2030, 1, 1) };
    Assert.areEqual(ChargeCalendar.holidaysOverride, ChargeCalendar.holidays());
  }

  @IsTest
  static void retryWindow() {
    setup2026();
    ChargeSettings.overrideValue = ChargeSettings.defaults();
    Assert.isTrue(ChargeCalendar.isRetryWindowOpen(Datetime.newInstance(2026, 11, 6, 10, 0, 0)), 'Friday 10:00');
    Assert.isFalse(ChargeCalendar.isRetryWindowOpen(Datetime.newInstance(2026, 11, 6, 14, 0, 0)), 'Friday 14:00 = cutoff');
    Assert.isFalse(ChargeCalendar.isRetryWindowOpen(Datetime.newInstance(2026, 11, 7, 10, 0, 0)), 'Shabbat');
    Assert.isTrue(ChargeCalendar.isRetryWindowOpen(Datetime.newInstance(2026, 11, 4, 23, 0, 0)), 'regular Wednesday night');
    Assert.isFalse(ChargeCalendar.isRetryWindowOpen(Datetime.newInstance(2026, 9, 20, 15, 0, 0)), 'Erev Yom Kippur after cutoff');
    ChargeSettings.overrideValue.Friday_Cutoff_Hour__c = 16;
    Assert.areEqual(16, ChargeCalendar.fridayCutoffHour());
    Assert.isTrue(ChargeCalendar.isRetryWindowOpen(Datetime.newInstance(2026, 11, 6, 15, 0, 0)), 'Friday 15:00 with cutoff 16');
  }

  @IsTest
  static void nextWorkingMorning() {
    setup2026();
    ChargeSettings.overrideValue = ChargeSettings.defaults();
    Datetime open = Datetime.newInstance(2026, 11, 4, 10, 0, 0);
    Assert.areEqual(open, ChargeCalendar.nextWorkingMorning(open), 'open window → unchanged');
    Assert.areEqual(
      Datetime.newInstance(2026, 11, 8, 8, 0, 0),
      ChargeCalendar.nextWorkingMorning(Datetime.newInstance(2026, 11, 6, 15, 0, 0)),
      'Friday after cutoff → Sunday 08:00'
    );
    Assert.areEqual(
      Datetime.newInstance(2026, 11, 8, 8, 0, 0),
      ChargeCalendar.nextWorkingMorning(Datetime.newInstance(2026, 11, 7, 10, 0, 0)),
      'Shabbat → Sunday 08:00'
    );
    Assert.areEqual(
      Datetime.newInstance(2026, 9, 14, 8, 0, 0),
      ChargeCalendar.nextWorkingMorning(Datetime.newInstance(2026, 9, 11, 15, 0, 0)),
      'Erev Rosh Hashana after cutoff → Monday after RH2'
    );
    ChargeSettings.overrideValue.AM_Time__c = '07:30';
    Assert.areEqual(
      Datetime.newInstance(2026, 11, 8, 7, 30, 0),
      ChargeCalendar.nextWorkingMorning(Datetime.newInstance(2026, 11, 7, 10, 0, 0))
    );
  }
}
