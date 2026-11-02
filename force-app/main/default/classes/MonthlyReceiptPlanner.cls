/**
 * Groups last month's successful charges by Contact into one Monthly_Receipt__c each (B6.11.1). Scope = Contacts that have such
 * charges (semi-join query locator instead of the spec's GROUP BY iterable, so the batch is not capped by aggregate-row limits, N77).
 * A receipt that already left Pending is never touched again (N78): late charges stay unlinked for the "Success without receipt" report.
 */
public without sharing class MonthlyReceiptPlanner implements Database.Batchable<SObject>, Database.Stateful {
  final Date period;
  final Date fromD;
  final Date toD;

  public MonthlyReceiptPlanner(Date periodStart) {
    period = periodStart.toStartOfMonth();
    fromD = period;
    toD = period.addMonths(1).addDays(-1);
  }

  public Database.QueryLocator start(Database.BatchableContext bc) {
    return Database.getQueryLocator(
      [
        SELECT Id
        FROM Contact
        WHERE
          Id IN (
            SELECT Contact__c
            FROM Charge__c
            WHERE
              Status__c = 'Success'
              AND Monthly_Receipt__c = NULL
              AND Needs_Reconciliation__c = FALSE
              AND Run_Date__c >= :fromD
              AND Run_Date__c <= :toD
              AND Cardcom_Deal_Number__c != NULL
          )
      ]
    );
  }

  public void execute(Database.BatchableContext bc, List<Contact> scope) {
    Set<Id> contactIds = new Map<Id, Contact>(scope).keySet();
    Map<Id, List<Charge__c>> byContact = new Map<Id, List<Charge__c>>();
    for (Charge__c ch : [
      SELECT Id, Contact__c, Amount__c, Cardcom_Deal_Number__c
      FROM Charge__c
      WHERE
        Contact__c IN :contactIds
        AND Status__c = 'Success'
        AND Monthly_Receipt__c = NULL
        AND Needs_Reconciliation__c = FALSE
        AND Cardcom_Deal_Number__c != NULL
        AND Run_Date__c >= :fromD
        AND Run_Date__c <= :toD
      ORDER BY Run_Date__c, Slot__c
    ]) {
      if (!byContact.containsKey(ch.Contact__c))
        byContact.put(ch.Contact__c, new List<Charge__c>());
      byContact.get(ch.Contact__c).add(ch);
    }
    String ym = Datetime.newInstance(period, Time.newInstance(12, 0, 0, 0)).format('yyyyMM');
    Set<String> keys = new Set<String>();
    for (Id cid : byContact.keySet())
      keys.add(cid + '-' + ym);
    Set<Id> locked = new Set<Id>();
    for (Monthly_Receipt__c r : [SELECT Contact__c FROM Monthly_Receipt__c WHERE Receipt_Key__c IN :keys AND Status__c != 'Pending'])
      locked.add(r.Contact__c);

    List<Monthly_Receipt__c> rs = new List<Monthly_Receipt__c>();
    for (Id cid : byContact.keySet()) {
      if (locked.contains(cid))
        continue;
      Decimal total = 0;
      List<Object> deals = new List<Object>();
      for (Charge__c ch : byContact.get(cid)) {
        total += ch.Amount__c;
        deals.add(Long.valueOf(ch.Cardcom_Deal_Number__c));
      }
      rs.add(
        new Monthly_Receipt__c(
          Contact__c = cid,
          Period_Month__c = period,
          Receipt_Key__c = cid + '-' + ym,
          Status__c = 'Pending',
          Total_Amount__c = total,
          Charge_Count__c = deals.size(),
          Deal_Numbers__c = JSON.serialize(deals)
        )
      );
    }
    if (rs.isEmpty())
      return;
    upsert rs Receipt_Key__c;
    List<Charge__c> link = new List<Charge__c>();
    for (Monthly_Receipt__c r : rs)
      for (Charge__c ch : byContact.get(r.Contact__c))
        link.add(new Charge__c(Id = ch.Id, Monthly_Receipt__c = r.Id));
    update link;
  }

  public void finish(Database.BatchableContext bc) {
    if (!Test.isRunningTest())
      MonthlyReceiptQueueable.start(period); // tests call start() themselves
  }
}
