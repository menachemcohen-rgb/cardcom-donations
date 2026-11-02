/**
 * Manual re-run after a Config error is fixed (B6.13 E21, spec-consistency N6). From Anonymous Apex, as the integration user:
 *   ChargeAdmin.requeueFailedConfig(Date.today());
 * Creates the next attempt for every Config-failed charge of that run date that has no later attempt, then starts the chain.
 */
public without sharing class ChargeAdmin {
  public static Integer requeueFailedConfig(Date runDate) {
    Id rt = MicroPledges.recordTypeId();
    List<Charge__c> failed = [
      SELECT Id, Pledge__c, Contact__c, Amount__c, Scheduled_Date__c, Slot__c, Attempt_Number__c, ExternalUniqTranId__c, Attempt_Key__c
      FROM Charge__c
      WHERE
        Status__c = 'Failed'
        AND Error_Category__c = 'Config'
        AND Run_Date__c = :runDate
        AND Pledge__r.StageName = :MicroPledges.STAGE_ACTIVE
        AND Pledge__r.RecordTypeId = :rt
    ];
    Set<String> logical = new Set<String>();
    for (Charge__c c : failed)
      logical.add(c.ExternalUniqTranId__c);
    Map<String, Decimal> latest = new Map<String, Decimal>();
    for (AggregateResult ar : [
      SELECT ExternalUniqTranId__c ext, MAX(Attempt_Number__c) n
      FROM Charge__c
      WHERE ExternalUniqTranId__c IN :logical
      GROUP BY ExternalUniqTranId__c
    ]) {
      latest.put((String) ar.get('ext'), (Decimal) ar.get('n'));
    }
    Datetime now = ChargeCalendar.now();
    List<Charge__c> next = new List<Charge__c>();
    for (Charge__c c : failed) {
      if (latest.get(c.ExternalUniqTranId__c) != c.Attempt_Number__c)
        continue; // a later attempt already exists
      Integer n = c.Attempt_Number__c.intValue() + 1;
      next.add(
        new Charge__c(
          Pledge__c = c.Pledge__c,
          Contact__c = c.Contact__c,
          Amount__c = c.Amount__c,
          Scheduled_Date__c = c.Scheduled_Date__c,
          Run_Date__c = now.date(),
          Slot__c = c.Slot__c,
          Status__c = 'Pending',
          Attempt_Number__c = n,
          ExternalUniqTranId__c = c.ExternalUniqTranId__c,
          Attempt_Key__c = c.ExternalUniqTranId__c + '-A' + n,
          Not_Before__c = now
        )
      );
    }
    Integer created = ChargePlanner.insertAttempts(next);
    if (created > 0 && !ChargeRunLock.isChainActive())
      ChargeDispatcher.start();
    return created;
  }
}
