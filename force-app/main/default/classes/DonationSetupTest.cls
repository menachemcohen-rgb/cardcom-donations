@IsTest
private class DonationSetupTest {
  static final Integer LATER_JOBS = 5; // Retry, Receipts, Reconcile, Daily Alerts, Log Cleanup (classes from later prompts)

  static User user(String tz, Boolean withPermission) {
    User u;
    System.runAs(new User(Id = UserInfo.getUserId())) {
      String uniq = String.valueOf(Crypto.getRandomInteger()).replace('-', '');
      u = new User(
        ProfileId = UserInfo.getProfileId(),
        Username = 'donsetup-' + uniq + '@example.com.test',
        Email = 'donsetup@example.com',
        LastName = 'Setup',
        Alias = 'dsetup',
        TimeZoneSidKey = tz,
        LocaleSidKey = 'iw_IL',
        EmailEncodingKey = 'UTF-8',
        LanguageLocaleKey = 'en_US'
      );
      insert u;
      if (withPermission) {
        PermissionSet ps = new PermissionSet(Name = 'Test_Manage_Schedule_' + uniq, Label = 'Test Manage Schedule ' + uniq);
        insert ps;
        CustomPermission cp = [SELECT Id FROM CustomPermission WHERE DeveloperName = 'Manage_Charge_Schedule'];
        insert new SetupEntityAccess(ParentId = ps.Id, SetupEntityId = cp.Id);
        insert new PermissionSetAssignment(PermissionSetId = ps.Id, AssigneeId = u.Id);
      }
    }
    return u;
  }

  /** Jobs this test created: DonationSetup uses the 'TEST Donations ' prefix in a test run, so the org's real jobs never count. */
  static Integer donationJobs() {
    String pattern = DonationSetup.jobName('%');
    return [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name LIKE :pattern];
  }

  static String cronOf(String suffix) {
    String name = DonationSetup.jobName(suffix);
    return [SELECT CronExpression FROM CronTrigger WHERE CronJobDetail.Name = :name].CronExpression;
  }

  @IsTest
  static void testRunsUseTheirOwnJobNames() {
    Assert.areEqual('TEST Donations AM', DonationSetup.jobName('AM'), 'production keeps "Donations AM"; tests never touch it');
    Integer realJobs = [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name LIKE 'Donations %'];
    ChargeSettings.overrideValue = ChargeSettings.defaults();
    DonationSetup.scheduleAll();
    DonationSetup.unscheduleAll();
    Assert.areEqual(realJobs, [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name LIKE 'Donations %'], 'real jobs untouched');
  }

  @IsTest
  static void scheduleAllAndUnscheduleAll() {
    ChargeSettings.overrideValue = ChargeSettings.defaults();
    DonationSetup.scheduleAll();
    Integer missing = DonationSetup.lastSkipped.size();
    Assert.isTrue(missing <= LATER_JOBS, String.valueOf(DonationSetup.lastSkipped));
    Assert.areEqual(4 + 4 + (LATER_JOBS - missing), donationJobs(), '4 charge runs + 4 LP sweepers + later jobs that exist');
    Assert.areEqual('0 0 8 ? * SUN-FRI', cronOf('AM'));
    Assert.areEqual('0 0 20 ? * SUN-FRI', cronOf('PM'), 'PM is scheduled even when Runs_Per_Day__c = 1 (B9)');
    Assert.areEqual('0 0 6 ? * SUN-FRI', cronOf('Eve AM'));
    Assert.areEqual('0 0 11 ? * SUN-FRI', cronOf('Eve PM'));
    DonationSetup.unscheduleAll();
    Assert.areEqual(0, donationJobs());
  }

  @IsTest
  static void missingOrNonSchedulableClassesAreSkipped() {
    Assert.isFalse(DonationSetup.scheduleIfPresent(DonationSetup.jobName('X'), '0 0 1 * * ?', 'NoSuchClassAnywhere'));
    Assert.isFalse(DonationSetup.scheduleIfPresent(DonationSetup.jobName('Y'), '0 0 1 * * ?', 'MicroPledges'));
    Assert.areEqual(2, DonationSetup.lastSkipped.size());
  }

  @IsTest
  static void rescheduleAppliesNewTimes() {
    User u = user('Asia/Jerusalem', false);
    System.runAs(u) {
      ChargeSettings.overrideValue = ChargeSettings.defaults();
      DonationSetup.scheduleAll();
      ChargeSettings.overrideValue.AM_Time__c = '07:15';
      List<String> errs = DonationSetup.reschedule();
      Assert.isTrue(errs.isEmpty(), String.valueOf(errs));
      Assert.areEqual('0 15 7 ? * SUN-FRI', cronOf('AM'));
      String sweepers = DonationSetup.jobName('LP Sweeper%');
      Assert.areEqual(4, [SELECT COUNT() FROM CronTrigger WHERE CronJobDetail.Name LIKE :sweepers], 'fixed jobs untouched');
    }
    Assert.isNotNull(Charge_Settings__c.getOrgDefaults().Schedule_Applied_At__c);
  }

  @IsTest
  static void rescheduleRefusesWrongTimeZoneInvalidSettingsAndActiveChain() {
    System.runAs(user('Europe/London', false)) {
      ChargeSettings.overrideValue = ChargeSettings.defaults();
      List<String> errs = DonationSetup.reschedule();
      Assert.areEqual(1, errs.size());
      Assert.isTrue(errs[0].contains('Asia/Jerusalem'));
    }
    User jlm = user('Asia/Jerusalem', false);
    System.runAs(jlm) {
      ChargeSettings.overrideValue = ChargeSettings.defaults();
      ChargeSettings.overrideValue.AM_Time__c = '21:00';
      Assert.isFalse(DonationSetup.reschedule().isEmpty(), 'invalid settings');
      ChargeSettings.overrideValue = ChargeSettings.defaults();
      ChargeRunLock.acquire();
      List<String> errs = DonationSetup.reschedule();
      Assert.areEqual(1, errs.size());
      Assert.isTrue(errs[0].startsWith('חיוב פעיל כרגע'));
      Assert.areEqual(0, donationJobs(), 'nothing scheduled');
    }
  }

  @IsTest
  static void invocableRequiresManageChargeSchedule() {
    System.runAs(user('Asia/Jerusalem', false)) {
      DonationSetup.Result r = DonationSetup.applyScheduleInvocable()[0];
      Assert.isFalse(r.ok);
      Assert.areEqual('אין הרשאה', r.message);
    }
    System.runAs(user('Asia/Jerusalem', true)) {
      ChargeSettings.overrideValue = ChargeSettings.defaults();
      DonationSetup.Result r = DonationSetup.applyScheduleInvocable()[0];
      Assert.isTrue(r.ok, r.message);
      Assert.isTrue(r.message.startsWith('הבקשה נשלחה'), r.message);
      Assert.areEqual(1, DonationSetup.published.size(), 'handed to the integration user (N42)');
      Assert.areEqual('RESCHEDULE', DonationSetup.published[0].Command__c);
      Assert.areEqual(0, donationJobs(), 'the admin schedules nothing itself');
      ChargeSettings.overrideValue.AM_Time__c = 'bad';
      r = DonationSetup.applyScheduleInvocable()[0];
      Assert.isFalse(r.ok, 'invalid settings are refused at once');
      Assert.areEqual(1, DonationSetup.published.size());
    }
  }

  @IsTest
  static void commandsRunAsTheSubscriberUser() {
    System.runAs(user('Asia/Jerusalem', false)) {
      TestDataFactory.chargeEngine(TestDataFactory.WED_0800);
      DonationSetup.handleCommands(new List<Donation_Setup_Command__e>{ new Donation_Setup_Command__e(Command__c = 'SCHEDULE_ALL') });
      Assert.areEqual(4 + 4 + LATER_JOBS, donationJobs());
      String amJob = DonationSetup.jobName('AM');
      Assert.areEqual(UserInfo.getUserId(), [SELECT OwnerId FROM CronTrigger WHERE CronJobDetail.Name = :amJob].OwnerId);
      ChargeSettings.overrideValue.AM_Time__c = '07:15';
      DonationSetup.handleCommands(new List<Donation_Setup_Command__e>{ new Donation_Setup_Command__e(Command__c = 'RESCHEDULE') });
      Assert.areEqual('0 15 7 ? * SUN-FRI', cronOf('AM'));
      DonationSetup.handleCommands(new List<Donation_Setup_Command__e>{ new Donation_Setup_Command__e(Command__c = 'UNSCHEDULE_ALL') });
      Assert.areEqual(0, donationJobs());
    }
    System.runAs(user('Europe/London', false)) {
      TestDataFactory.chargeEngine(TestDataFactory.WED_0800);
      Integer before = StaffAlertService.sentCount;
      DonationSetup.handleCommands(new List<Donation_Setup_Command__e>{ new Donation_Setup_Command__e(Command__c = 'SCHEDULE_ALL') });
      Assert.areEqual(0, donationJobs(), 'wrong time zone: nothing scheduled');
      Assert.areEqual(before + 1, StaffAlertService.sentCount, '"זמני החיוב לא עודכנו" sent to staff');
    }
  }

  @IsTest
  static void publishedCommandRunsTheTrigger() {
    // DonationSetupCommandTrigger (N42): the event reaches handleCommands; nothing is scheduled, so UNSCHEDULE_ALL is a no-op
    Test.startTest();
    DonationSetup.request('UNSCHEDULE_ALL');
    Test.getEventBus().deliver();
    Test.stopTest();
    Assert.areEqual(1, DonationSetup.published.size());
    Assert.areEqual(0, donationJobs());
  }

  @IsTest
  static void requestRejectsUnknownCommands() {
    try {
      DonationSetup.request('DROP');
      Assert.fail('expected an exception');
    } catch (IllegalArgumentException e) {
      Assert.isTrue(e.getMessage().contains('SCHEDULE_ALL'));
    }
    DonationSetup.request('SCHEDULE_ALL');
    Assert.areEqual(1, DonationSetup.published.size());
  }
}
