/** Picks the next ripe batch and enqueues one ChargeQueueable (B6.5.1). Safe to call from Planner, RetryScheduler, and the chain. */
public without sharing class ChargeDispatcher {
  @TestVisible
  static List<Id> lastBatch; // ids of the last enqueued batch (tests)

  public static void start() {
    Datetime now = ChargeCalendar.now();
    if (ChargeSettings.get().Charging_Enabled__c != true) {
      ChargeRunLock.release(); // emergency switch stops every Cardcom charge, retries included (N55)
      return;
    }
    if (ChargeCalendar.isRestDay(now.date())) {
      ChargeRunLock.release(); // Shabbat / Chag: nothing is sent
      return;
    }
    // Friday / Erev Chag after Friday_Cutoff_Hour__c: first attempts of the scheduled runs are still sent;
    // retries (Attempt_Number__c > 1) wait for the next working day (ChargeRetryPolicy.nextWindow).
    Integer maxAttempt = ChargeCalendar.isRetryWindowOpen(now) ? 99 : 1;
    Decimal bs = CardcomService.settings().Batch_Size__c;
    Integer size = bs == null ? 30 : bs.intValue();
    String pledgeType = MicroPledges.TYPE;
    List<Id> ids = new List<Id>();
    for (Charge__c c : [
      SELECT Id
      FROM Charge__c
      WHERE
        Status__c = 'Pending'
        AND Pledge__r.StageName = :MicroPledges.STAGE_ACTIVE
        AND Pledge__r.Type = :pledgeType
        AND (Not_Before__c = NULL
        OR Not_Before__c <= :now)
        AND Attempt_Number__c <= :maxAttempt
      ORDER BY Scheduled_Date__c, Attempt_Number__c, CreatedDate
      LIMIT :size
    ])
      ids.add(c.Id);
    if (ids.isEmpty()) {
      ChargeRunLock.release();
      StaffAlertService.runFailures(); // D38: many failures in the last hours → staff alert (at most every 4 hours)
      return;
    } // chain finished
    ChargeRunLock.acquire(); // extended on every link
    if (Test.isRunningTest() && Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs())
      return;
    lastBatch = ids;
    System.enqueueJob(new ChargeQueueable(ids));
  }
}
