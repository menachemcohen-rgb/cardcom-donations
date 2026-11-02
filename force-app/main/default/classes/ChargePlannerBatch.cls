/** Chunked planning for large pledge volumes (spec-consistency N50). Same rules as ChargePlanner; 200 pledges per chunk. */
public with sharing class ChargePlannerBatch implements Database.Batchable<SObject> {
  final Date runDate;
  final String slot;
  public ChargePlannerBatch(Date runDate, String slot) {
    this.runDate = runDate;
    this.slot = slot;
  }

  public Database.QueryLocator start(Database.BatchableContext bc) {
    Id rt = MicroPledges.recordTypeId();
    Date rd = runDate;
    return Database.getQueryLocator(
      [
        SELECT Id
        FROM Opportunity
        WHERE RecordTypeId = :rt AND StageName = :MicroPledges.STAGE_ACTIVE AND (End_Date__c = NULL OR End_Date__c >= :rd)
      ]
    );
  }

  public void execute(Database.BatchableContext bc, List<Opportunity> scope) {
    Set<Id> ids = new Map<Id, Opportunity>(scope).keySet();
    ChargePlanner.insertAttempts(
      ChargePlanner.buildAll(ChargePlanner.queryPledges(runDate, ids), ChargeCalendar.logicalDatesFor(runDate), slot, runDate)
    );
  }

  public void finish(Database.BatchableContext bc) {
    if (!ChargeRunLock.isChainActive())
      ChargeDispatcher.start();
  }
}
