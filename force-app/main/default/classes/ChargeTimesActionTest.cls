@IsTest
private class ChargeTimesActionTest {
  static User user(Boolean withPermission) {
    User u;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      String uniq = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
      u = new User(
        ProfileId = UserInfo.getProfileId(),
        Username = 'chtimes-' + uniq + '@example.com.test',
        Email = 'chtimes@example.com',
        LastName = 'Times',
        Alias = 'chtimes',
        TimeZoneSidKey = 'Asia/Jerusalem',
        LocaleSidKey = 'iw_IL',
        EmailEncodingKey = 'UTF-8',
        LanguageLocaleKey = 'en_US'
      );
      insert u;
      if (withPermission) {
        PermissionSet ps = new PermissionSet(Name = 'Test_Charge_Times_' + uniq, Label = 'Test Charge Times ' + uniq);
        insert ps;
        CustomPermission cp = [SELECT Id FROM CustomPermission WHERE DeveloperName = 'Manage_Charge_Schedule'];
        insert new SetupEntityAccess(ParentId = ps.Id, SetupEntityId = cp.Id);
        insert new PermissionSetAssignment(PermissionSetId = ps.Id, AssigneeId = u.Id);
      }
    }
    return u;
  }

  static ChargeTimesAction.Request req(String sh, String mi, String eveSh, String eveMi) {
    ChargeTimesAction.Request q = new ChargeTimesAction.Request();
    q.shacharitTime = sh;
    q.minchaTime = mi;
    q.eveShacharitTime = eveSh;
    q.eveMinchaTime = eveMi;
    return q;
  }

  @IsTest
  static void savesTheTimesAndAsksToReschedule() {
    System.runAs(user(true)) {
      ChargeTimesAction.Result r = ChargeTimesAction.save(new List<ChargeTimesAction.Request>{ req('07:30', ' 18:45 ', '06:15', '11:30') })[0];
      Assert.isTrue(r.ok, r.message);
      Charge_Settings__c s = Charge_Settings__c.getOrgDefaults();
      Assert.areEqual('07:30', s.AM_Time__c);
      Assert.areEqual('18:45', s.PM_Time__c);
      Assert.areEqual('06:15', s.Eve_AM_Time__c);
      Assert.areEqual('11:30', s.Eve_PM_Time__c);
      Assert.areEqual(1, DonationSetup.published.size());
      Assert.areEqual('RESCHEDULE', DonationSetup.published[0].Command__c);
    }
  }

  @IsTest
  static void invalidTimesAreRefusedAndNothingIsSaved() {
    System.runAs(user(true)) {
      ChargeTimesAction.Result r = ChargeTimesAction.save(new List<ChargeTimesAction.Request>{ req('25:00', '18:00', '06:00', '15:00') })[0];
      Assert.isFalse(r.ok);
      Assert.isTrue(String.isNotBlank(r.message));
      Charge_Settings__c s = Charge_Settings__c.getOrgDefaults();
      Assert.isTrue(s == null || s.Id == null || s.AM_Time__c != '25:00', 'not saved');
      Assert.areEqual(0, DonationSetup.published.size());
    }
  }

  @IsTest
  static void withoutThePermissionNothingChanges() {
    System.runAs(user(false)) {
      ChargeTimesAction.Result r = ChargeTimesAction.save(new List<ChargeTimesAction.Request>{ req('07:30', '18:45', '06:15', '11:30') })[0];
      Assert.isFalse(r.ok);
      Assert.areEqual('אין הרשאה', r.message);
    }
  }
}
