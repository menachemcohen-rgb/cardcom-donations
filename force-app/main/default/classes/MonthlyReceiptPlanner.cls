/**
 * Groups last month's successful charges by Contact into one Monthly_Receipt__c each (B6.11.1). Scope = Contacts that have such
 * charges (semi-join query locator instead of the spec's GROUP BY iterable, so the batch is not capped by aggregate-row limits, N77).
 * A receipt that already left Pending is never touched again (N78): late charges stay unlinked for the "Success without receipt" report.
 * MonthlyReceiptPlanner(period, contactIds) limits planning and sending to those Contacts, so a sandbox run can't send documents
 * to real donors (the scheduled run always passes null = everyone).
 * Deal_Numbers__c holds one entry per charge: {"d": deal number, "sum": amount, "date": yyyy-MM-dd (Israel), "auth": approval
 * number}, so the receipt can carry one credit card line per charge (Receipt_Payment_Mode__c = CreditCardLines). Receipts planned
 * before this format hold plain deal numbers; MonthlyReceiptService reads both.
 */
public without sharing class MonthlyReceiptPlanner implements Database.Batchable<SObject>, Database.Stateful {
  final Date period;
  final Date fromD;
  final Date toD;
  final Set<Id> onlyContactIds;

  public MonthlyReceiptPlanner(Date periodStart) {
    this(periodStart, null);
  }

  /** onlyContactIds: plan and send only for these Contacts (null = everyone). */
  public MonthlyReceiptPlanner(Date periodStart, Set<Id> onlyContactIds) {
    period = periodStart.toStartOfMonth();
    fromD = period;
    toD = period.addMonths(1).addDays(-1);
    this.onlyContactIds = onlyContactIds == null ? null : new Set<Id>(onlyContactIds);
  }

  public Database.QueryLocator start(Database.BatchableContext bc) {
    Date f = fromD;
    Date t = toD;
    Set<Id> only = onlyContactIds;
    return Database.getQueryLocator(
      'SELECT Id FROM Contact WHERE Id IN (SELECT Contact__c FROM Charge__c WHERE Status__c = \'Success\'' +
        ' AND Monthly_Receipt__c = NULL AND Needs_Reconciliation__c = FALSE AND Run_Date__c >= :f AND Run_Date__c <= :t' +
        ' AND Cardcom_Deal_Number__c != NULL)' +
        (only == null ? '' : ' AND Id IN :only')
    );
  }

  public void execute(Database.BatchableContext bc, List<Contact> scope) {
    Set<Id> contactIds = new Map<Id, Contact>(scope).keySet();
    Map<Id, List<Charge__c>> byContact = new Map<Id, List<Charge__c>>();
    for (Charge__c ch : [
      SELECT Id, Contact__c, Amount__c, Cardcom_Deal_Number__c, Cardcom_Approval_Number__c, Executed_At__c, Run_Date__c
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
        deals.add(entry(ch));
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

  /** One charge in Deal_Numbers__c (see the class comment). */
  @TestVisible
  static Map<String, Object> entry(Charge__c ch) {
    Map<String, Object> e = new Map<String, Object>{
      'd' => Long.valueOf(ch.Cardcom_Deal_Number__c),
      'sum' => ch.Amount__c,
      'date' => ch.Executed_At__c != null
        ? ch.Executed_At__c.format('yyyy-MM-dd', 'Asia/Jerusalem')
        : Datetime.newInstance(ch.Run_Date__c, Time.newInstance(12, 0, 0, 0)).format('yyyy-MM-dd')
    };
    if (String.isNotBlank(ch.Cardcom_Approval_Number__c))
      e.put('auth', ch.Cardcom_Approval_Number__c);
    return e;
  }

  public void finish(Database.BatchableContext bc) {
    if (!Test.isRunningTest())
      MonthlyReceiptQueueable.start(period, onlyContactIds); // tests call start() themselves
  }
}
