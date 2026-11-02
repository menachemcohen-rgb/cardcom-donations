@IsTest
private class ChargeSettingsTest {
  @IsTest
  static void defaultsAreValid() {
    Assert.isTrue(ChargeSettings.validate(ChargeSettings.defaults()).isEmpty());
    Charge_Settings__c s = ChargeSettings.get(); // no Org Default record in a test → defaults
    Assert.areEqual('08:00', s.AM_Time__c);
    Assert.areEqual(2, s.Runs_Per_Day__c.intValue());
  }

  @IsTest
  static void orgDefaultRecordWins() {
    insert new Charge_Settings__c(
      SetupOwnerId = UserInfo.getOrganizationId(),
      AM_Time__c = '07:45',
      PM_Time__c = '19:00',
      Eve_AM_Time__c = '06:00',
      Eve_PM_Time__c = '11:00',
      Runs_Per_Day__c = 1,
      Retry_Minute__c = 30,
      Friday_Cutoff_Hour__c = 14,
      Max_Retries__c = 3,
      Receipt_Day_Of_Month__c = 1,
      Receipt_Time__c = '07:00',
      Reconcile_Time__c = '02:30',
      Charging_Enabled__c = true
    );
    Assert.areEqual('07:45', ChargeSettings.get().AM_Time__c);
    Assert.areEqual(1, ChargeSettings.get().Runs_Per_Day__c.intValue());
  }

  @IsTest
  static void validateCatchesEveryRule() {
    Charge_Settings__c bad = ChargeSettings.defaults();
    bad.AM_Time__c = '25:00';
    List<String> errs = ChargeSettings.validate(bad);
    Assert.areEqual(1, errs.size());
    Assert.isTrue(errs[0].startsWith('AM_Time__c'), errs[0]);

    Charge_Settings__c s = ChargeSettings.defaults();
    s.AM_Time__c = '21:00'; // after PM
    s.Eve_AM_Time__c = '12:00'; // after Eve PM
    s.Eve_PM_Time__c = '11:30';
    s.Friday_Cutoff_Hour__c = 11; // Eve PM after cutoff
    s.Runs_Per_Day__c = 3;
    s.Retry_Minute__c = 60;
    s.Max_Retries__c = 0;
    s.Receipt_Day_Of_Month__c = 29;
    errs = ChargeSettings.validate(s);
    Assert.areEqual(7, errs.size(), String.join(errs, ' | '));
  }

  @IsTest
  static void cronAndTimes() {
    Assert.areEqual('0 5 8 ? * SUN-FRI', ChargeSettings.cron('08:05', 'SUN-FRI'));
    Assert.areEqual('0 30 2 * * ?', ChargeSettings.cron('02:30', '*'));
    Assert.areEqual(new List<Integer>{ 6, 0 }, ChargeSettings.hm(' 06:00 '));
    for (String v : new List<String>{ null, '8:00', '08:60', 'x' }) {
      try {
        ChargeSettings.hm(v);
        Assert.fail('expected SettingsException for ' + v);
      } catch (ChargeSettings.SettingsException e) {
        Assert.isTrue(e.getMessage().startsWith('זמן לא תקין'));
      }
    }
  }
}
