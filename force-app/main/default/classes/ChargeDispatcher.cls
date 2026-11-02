/** Picks the next ripe batch and enqueues one ChargeQueueable (B6.5.1). Safe to call from Planner, RetryScheduler, and the chain. */
public without sharing class ChargeDispatcher {
  public static void start() {
    Datetime now = ChargeCalendar.now();
    if (ChargeSettings.get().Charging_Enabled__c != true) {
      ChargeRunLock.release(); // emergency switch stops every Cardcom charge, retries included (N55)
      return;
    }
    if (!ChargeCalendar.isRetryWindowOpen(now)) {
      ChargeRunLock.release();
      return;
    }
    Decimal bs = CardcomService.settings().Batch_Size__c;
    Integer size = bs == null ? 30 : bs.intValue();
    Id rt = MicroPledges.recordTypeId();
    List<Id> ids = new List<Id>();
    for (Charge__c c : [
      SELECT Id
      FROM Charge__c
      WHERE
        Status__c = 'Pending'
        AND Pledge__r.StageName = :MicroPledges.STAGE_ACTIVE
        AND Pledge__r.RecordTypeId = :rt
        AND (Not_Before__c = NULL
        OR Not_Before__c <= :now)
      ORDER BY Scheduled_Date__c, Attempt_Number__c, CreatedDate
      LIMIT :size
    ])
      ids.add(c.Id);
    if (ids.isEmpty()) {
      ChargeRunLock.release();
      return;
    } // chain finished
    ChargeRunLock.acquire(); // extended on every link
    if (Test.isRunningTest() && Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs())
      return;
    System.enqueueJob(new ChargeQueueable(ids));
  }
}
