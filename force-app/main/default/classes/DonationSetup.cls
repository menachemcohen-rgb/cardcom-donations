/**
 * Schedules the Donations jobs from Charge_Settings__c (B9, B9.1, B9.2; Part C E6/E7).
 * Jobs whose classes come in later prompts (retry, receipts, reconciliation, daily alerts, log cleanup) are scheduled by name and
 * skipped while the class doesn't exist yet (spec-consistency N46). Re-run reschedule() after deploying them.
 * Scheduled jobs run as the user who schedules them, so admins never schedule directly: request() publishes a
 * Donation_Setup_Command__e whose trigger runs as the integration user (N42) and calls handleCommands().
 */
public with sharing class DonationSetup {
  /**
   * Every job name starts with PREFIX. Production: 'Donations ' (unchanged). In a test run: 'TEST Donations ', so tests never
   * collide with, count or abort the org's real scheduled jobs.
   */
  @TestVisible
  static final String PREFIX = Test.isRunningTest() ? 'TEST Donations ' : 'Donations ';

  public static String jobName(String suffix) {
    return PREFIX + suffix;
  }

  static final List<String> TIMED = new List<String>{
    jobName('AM'),
    jobName('PM'),
    jobName('Eve AM'),
    jobName('Eve PM'),
    jobName('Retry'),
    jobName('Receipts'),
    jobName('Reconcile')
  };
  @TestVisible
  static List<String> lastSkipped = new List<String>();

  public static void scheduleAll() {
    lastSkipped = new List<String>();
    scheduleTimed();
    scheduleFixed();
  }

  static void scheduleTimed() {
    Charge_Settings__c s = ChargeSettings.get();
    System.schedule(jobName('AM'), ChargeSettings.cron(s.AM_Time__c, 'SUN-FRI'), new DonationChargeScheduler('AM'));
    System.schedule(jobName('PM'), ChargeSettings.cron(s.PM_Time__c, 'SUN-FRI'), new DonationChargeScheduler('PM'));
    System.schedule(jobName('Eve AM'), ChargeSettings.cron(s.Eve_AM_Time__c, 'SUN-FRI'), new DonationChargeScheduler('EveAM'));
    System.schedule(jobName('Eve PM'), ChargeSettings.cron(s.Eve_PM_Time__c, 'SUN-FRI'), new DonationChargeScheduler('EvePM'));
    scheduleIfPresent(jobName('Retry'), '0 ' + s.Retry_Minute__c.intValue() + ' * ? * SUN-FRI', 'ChargeRetryScheduler');
    scheduleIfPresent(jobName('Receipts'), ChargeSettings.cron(s.Receipt_Time__c, '*'), 'MonthlyReceiptScheduler');
    scheduleIfPresent(jobName('Reconcile'), ChargeSettings.cron(s.Reconcile_Time__c, '*'), 'ReconciliationJob');
  }
  static void scheduleFixed() {
    PendingVerificationSweeper.scheduleAll();
    scheduleIfPresent(jobName('Daily Alerts'), '0 0 9 ? * SUN-FRI', 'StaffAlertService.Daily');
    scheduleIfPresent(jobName('Log Cleanup'), '0 0 3 ? * SUN', 'LogCleanupBatch');
    scheduleIfPresent(jobName('Donor Reminders'), '0 0 10 ? * SUN', 'DonorFailureReminderJob'); // D37: Sunday 10:00
  }

  /** Schedules `className` if it exists and is Schedulable; otherwise records it in lastSkipped. */
  @TestVisible
  static Boolean scheduleIfPresent(String jobName, String cron, String className) {
    Type t = Type.forName(className);
    Object o = t == null ? null : t.newInstance();
    if (!(o instanceof Schedulable)) {
      lastSkipped.add(jobName + ' (' + className + ')');
      System.debug(LoggingLevel.WARN, 'Not scheduled yet, class missing: ' + className);
      return false;
    }
    System.schedule(jobName, cron, (Schedulable) o);
    return true;
  }

  /** Re-applies time settings. Returns errors (empty = success). */
  public static List<String> reschedule() {
    Charge_Settings__c s = ChargeSettings.get();
    List<String> errs = ChargeSettings.validate(s);
    if (UserInfo.getTimeZone().getID() != 'Asia/Jerusalem')
      errs.add('אזור הזמן של המשתמש חייב להיות Asia/Jerusalem');
    if (ChargeRunLock.isChainActive())
      errs.add('חיוב פעיל כרגע — נסו שוב בעוד כמה דקות');
    if (!errs.isEmpty())
      return errs;
    for (CronTrigger ct : [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name IN :TIMED])
      System.abortJob(ct.Id);
    lastSkipped = new List<String>();
    scheduleTimed();
    Charge_Settings__c org = Charge_Settings__c.getOrgDefaults();
    if (org == null || org.Id == null) {
      org = ChargeSettings.defaults();
      org.SetupOwnerId = UserInfo.getOrganizationId();
    }
    org.Schedule_Applied_At__c = Datetime.now();
    upsert org;
    StaffAlertService.scheduleChanged(s); // "זמני חיוב עודכנו" + the new values (Prompt 6)
    return errs;
  }

  public static void unscheduleAll() {
    String pattern = PREFIX + '%';
    for (CronTrigger ct : [SELECT Id FROM CronTrigger WHERE CronJobDetail.Name LIKE :pattern])
      System.abortJob(ct.Id);
  }

  public static final Set<String> COMMANDS = new Set<String>{ 'SCHEDULE_ALL', 'RESCHEDULE', 'UNSCHEDULE_ALL' };

  /** Asks the integration user (via the platform event) to run a command. Anonymous Apex: DonationSetup.request('SCHEDULE_ALL'); */
  public static void request(String command) {
    if (!COMMANDS.contains(command))
      throw new IllegalArgumentException('Unknown command ' + command + '; use ' + COMMANDS);
    Donation_Setup_Command__e e = new Donation_Setup_Command__e(Command__c = command, Requested_By__c = UserInfo.getUserId());
    published.add(e);
    EventBus.publish(e);
  }
  @TestVisible
  static List<Donation_Setup_Command__e> published = new List<Donation_Setup_Command__e>();

  /** DonationSetupCommandTrigger (running as the integration user). Failures are reported to staff, never thrown. */
  public static void handleCommands(List<Donation_Setup_Command__e> events) {
    for (Donation_Setup_Command__e e : events) {
      List<String> errs = new List<String>();
      try {
        if (e.Command__c == 'RESCHEDULE') {
          errs = reschedule();
        } else if (e.Command__c == 'SCHEDULE_ALL') {
          if (UserInfo.getTimeZone().getID() != 'Asia/Jerusalem')
            errs.add('אזור הזמן של המשתמש חייב להיות Asia/Jerusalem');
          else {
            unscheduleAll();
            scheduleAll();
            StaffAlertService.scheduleChanged(ChargeSettings.get());
          }
        } else if (e.Command__c == 'UNSCHEDULE_ALL') {
          unscheduleAll();
        } else {
          errs.add('Unknown command ' + e.Command__c);
        }
      } catch (Exception ex) {
        errs.add(ex.getMessage());
      }
      if (!errs.isEmpty())
        StaffAlertService.scheduleFailed(e.Command__c, errs);
    }
  }

  public class Result {
    @InvocableVariable
    public Boolean ok;
    @InvocableVariable
    public String message;
  }
  /** "Apply charge schedule" button (B9.1): checks what it can now, then hands the re-schedule to the integration user (N42). */
  @InvocableMethod(label='Apply charge schedule' description='Re-schedules Donations jobs from Charge_Settings__c')
  public static List<Result> applyScheduleInvocable() {
    Result r = new Result();
    if (!FeatureManagement.checkPermission('Manage_Charge_Schedule')) {
      r.ok = false;
      r.message = 'אין הרשאה';
      return new List<Result>{ r };
    }
    List<String> errs = ChargeSettings.validate(ChargeSettings.get());
    if (ChargeRunLock.isChainActive())
      errs.add('חיוב פעיל כרגע — נסו שוב בעוד כמה דקות');
    r.ok = errs.isEmpty();
    if (r.ok) {
      request('RESCHEDULE');
      r.message = 'הבקשה נשלחה. זמני החיוב יעודכנו תוך דקה ותישלח הודעה לצוות.';
    } else {
      r.message = String.join(errs, '\n');
    }
    return new List<Result>{ r };
  }
}
