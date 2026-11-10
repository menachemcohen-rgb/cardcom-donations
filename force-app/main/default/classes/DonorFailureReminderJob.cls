/**
 * Every Sunday at 10:00 (D37, "Donations Donor Reminders"): reminds donors whose charge failed and whose payment issue is still
 * open (Payment_Issue_Since__c set), the pledge is Active, and staff haven't ticked Failure_Reminders_Stopped__c. A donor who got
 * the first failure email in the last 3 days is skipped this week. Batch of 50 pledges per execute (one sendEmail call each).
 */
public without sharing class DonorFailureReminderJob implements Schedulable, Database.Batchable<SObject> {
  @TestVisible
  static Datetime nowOverride;

  /** Scheduled by name (DonationSetup). */
  public DonorFailureReminderJob() {
  }

  public void execute(SchedulableContext sc) {
    Database.executeBatch(new DonorFailureReminderJob(), 50);
  }

  public Database.QueryLocator start(Database.BatchableContext bc) {
    String pledgeType = MicroPledges.TYPE;
    String active = MicroPledges.STAGE_ACTIVE;
    Datetime recent = (nowOverride != null ? nowOverride : Datetime.now()).addDays(-3);
    return Database.getQueryLocator(
      [
        SELECT Id
        FROM Opportunity
        WHERE
          Type = :pledgeType
          AND StageName = :active
          AND Payment_Issue_Since__c != NULL
          AND Failure_Reminders_Stopped__c = FALSE
          AND (Last_Failure_Email_At__c = NULL
          OR Last_Failure_Email_At__c < :recent)
      ]
    );
  }

  public void execute(Database.BatchableContext bc, List<Opportunity> scope) {
    DonorEmailService.sendPaymentFailed(new Map<Id, Opportunity>(scope).keySet(), true);
  }

  public void finish(Database.BatchableContext bc) {
    StaffAlertService.weeklyFailedDigest(); // D38: staff list of the open payment issues, with what to do
  }
}
