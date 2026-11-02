/**
 * Weekly clean-up (B9 "Donations Log Cleanup", Sunday 03:00): deletes Cardcom_Webhook_Log__c older than 90 days and empties the Raw_*
 * fields of charges and monthly receipts older than 90 days (B2.3 "נמחק אחרי 90 יום"). Long text can't be filtered in SOQL, so the
 * raw-field stages look at a 35-day band of creation dates just past the 90 days — weekly runs cover it with overlap (N73).
 * Stages run one after the other: 0 webhook logs → 1 charges → 2 receipts.
 */
public without sharing class LogCleanupBatch implements Database.Batchable<SObject>, Schedulable {
  @TestVisible
  static final Integer KEEP_DAYS = 90;
  @TestVisible
  static final Integer BAND_DAYS = 35;
  final Integer stage;

  public LogCleanupBatch() {
    this(0);
  }
  public LogCleanupBatch(Integer stage) {
    this.stage = stage;
  }

  public void execute(SchedulableContext sc) {
    Database.executeBatch(new LogCleanupBatch(0), 500);
  }

  public Database.QueryLocator start(Database.BatchableContext bc) {
    Datetime cutoff = Datetime.now().addDays(-KEEP_DAYS);
    Datetime bandStart = cutoff.addDays(-BAND_DAYS);
    if (stage == 0)
      return Database.getQueryLocator([SELECT Id FROM Cardcom_Webhook_Log__c WHERE CreatedDate < :cutoff]);
    if (stage == 1)
      return Database.getQueryLocator(
        [SELECT Id, Raw_Response__c FROM Charge__c WHERE CreatedDate < :cutoff AND CreatedDate >= :bandStart]
      );
    return Database.getQueryLocator(
      [SELECT Id, Raw_Request__c, Raw_Response__c FROM Monthly_Receipt__c WHERE CreatedDate < :cutoff AND CreatedDate >= :bandStart]
    );
  }

  public void execute(Database.BatchableContext bc, List<SObject> scope) {
    if (stage == 0) {
      Database.delete(scope, false);
      return;
    }
    List<SObject> changed = new List<SObject>();
    for (SObject r : scope) {
      Boolean dirty = false;
      for (String f : stage == 1 ? new List<String>{ 'Raw_Response__c' } : new List<String>{ 'Raw_Request__c', 'Raw_Response__c' }) {
        if (r.get(f) != null) {
          r.put(f, null);
          dirty = true;
        }
      }
      if (dirty)
        changed.add(r);
    }
    if (!changed.isEmpty())
      Database.update(changed, false);
  }

  public void finish(Database.BatchableContext bc) {
    if (stage < 2 && !Test.isRunningTest())
      Database.executeBatch(new LogCleanupBatch(stage + 1), 500);
  }
}
