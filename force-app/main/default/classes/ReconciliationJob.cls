/**
 * Nightly reconciliation against Cardcom ListTransactions (B6.12, Part C E2, spec-consistency N11).
 * Schedulable at Charge_Settings__c.Reconcile_Time__c (DonationSetup) → Queueable for yesterday (Run_Date__c = day).
 * Match key = TranzactionId. The only automatic fix: an attempt with an unknown outcome that Cardcom confirms as successful.
 * Issues are upserted by Issue_Key__c, so a re-run never duplicates them and never reopens one staff resolved.
 * A class that is Schedulable can't be enqueued, so the callouts run in the inner Queueable Job.
 */
public without sharing class ReconciliationJob implements Schedulable {
  @TestVisible
  static Date dayOverride;
  @TestVisible
  static final Integer MAX_PAGES = 20; // 20 × 1,000 rows; + 50 lookups < 100 callouts
  @TestVisible
  static final Integer MAX_LOOKUPS = 50;
  final Date day;

  public ReconciliationJob() {
  }
  @TestVisible
  ReconciliationJob(Date d) {
    day = d;
  }

  public void execute(SchedulableContext sc) {
    enqueue(dayOverride != null ? dayOverride : Date.today().addDays(-1));
  }

  /** Manual re-run of one day: ReconciliationJob.enqueue(Date.newInstance(2026, 11, 5)); */
  public static Id enqueue(Date d) {
    return System.enqueueJob(new Job(d));
  }

  public class Job implements Queueable, Database.AllowsCallouts {
    final Date day;
    Job(Date d) {
      day = d;
    }
    public void execute(QueueableContext qc) {
      new ReconciliationJob(day).run();
    }
  }

  @TestVisible
  void run() {
    Cardcom_Setting__mdt s = CardcomService.settings();
    Integer pageSize = s.Recon_Page_Size__c == null ? 1000 : s.Recon_Page_Size__c.intValue();

    // ---- reads + callouts (no DML before them) ----
    Map<String, CardcomService.TxnSummary> cc = new Map<String, CardcomService.TxnSummary>();
    try {
      for (Integer page = 1; page <= MAX_PAGES; page++) {
        List<CardcomService.TxnSummary> rows = CardcomService.listTransactions(day, page, pageSize);
        for (CardcomService.TxnSummary t : rows) {
          CardcomService.TxnSummary prev = cc.get(t.tranzactionId);
          if (prev == null || t.isRefundOrCancel)
            cc.put(t.tranzactionId, t);
        }
        if (rows.size() < pageSize)
          break; // a partial page is the last one
      }
    } catch (Exception e) {
      System.debug(LoggingLevel.ERROR, 'Reconciliation ' + day + ' aborted: ' + e.getMessage());
      if (e instanceof CardcomService.CardcomHttpException) {
        Integer st = ((CardcomService.CardcomHttpException) e).status;
        if (st == 401 || st == 400)
          StaffAlertService.configErrorOncePerDay();
      }
      return; // nothing half-done; tomorrow's run retries
    }
    Date since = day.addDays(-7);
    List<Charge__c> unknown = [
      SELECT Id, Attempt_Key__c, ExternalUniqTranId__c, Amount__c
      FROM Charge__c
      WHERE Needs_Reconciliation__c = TRUE AND Cardcom_Tranzaction_Id__c = NULL AND Run_Date__c >= :since
      ORDER BY Run_Date__c
      LIMIT :MAX_LOOKUPS
    ];
    Map<Id, Map<String, Object>> found = new Map<Id, Map<String, Object>>();
    Set<Id> notFound = new Set<Id>();
    for (Charge__c c : unknown) {
      try {
        Map<String, Object> t = CardcomService.findSuccessByExternalId(c.Attempt_Key__c);
        if (t != null)
          found.put(c.Id, t);
        else
          notFound.add(c.Id);
      } catch (Exception e) {
        /* try again tomorrow */
      }
    }

    // ---- DML ----
    List<Reconciliation_Issue__c> issues = new List<Reconciliation_Issue__c>();
    Map<Id, Charge__c> fix = new Map<Id, Charge__c>();
    for (Charge__c c : [
      SELECT Id, Amount__c, Cardcom_Tranzaction_Id__c, ExternalUniqTranId__c, Needs_Reconciliation__c
      FROM Charge__c
      WHERE Run_Date__c = :day AND Status__c = 'Success' AND Cardcom_Tranzaction_Id__c != NULL
    ]) {
      CardcomService.TxnSummary t = cc.get(c.Cardcom_Tranzaction_Id__c);
      if (t == null || !t.isSuccess)
        issues.add(issue('Missing_In_Cardcom', c.Cardcom_Tranzaction_Id__c, c, null));
      else if (t.isRefundOrCancel)
        issues.add(issue('Status_Mismatch', c.Cardcom_Tranzaction_Id__c, c, t));
      else if (t.amount != null && t.amount != c.Amount__c)
        issues.add(issue('Amount_Mismatch', c.Cardcom_Tranzaction_Id__c, c, t));
      else if (c.Needs_Reconciliation__c)
        fix.put(c.Id, new Charge__c(Id = c.Id, Needs_Reconciliation__c = false));
    }
    if (s.Recon_Report_Unknown__c != false && !cc.isEmpty()) {
      Set<String> known = new Set<String>();
      for (Map<String, Object> t : found.values())
        known.add(String.valueOf(t.get('TranzactionId'))); // fixed below
      for (Charge__c c : [SELECT Cardcom_Tranzaction_Id__c FROM Charge__c WHERE Cardcom_Tranzaction_Id__c IN :cc.keySet()])
        known.add(c.Cardcom_Tranzaction_Id__c);
      for (CardcomService.TxnSummary t : cc.values())
        if (t.isSuccess && !t.isRefundOrCancel && !known.contains(t.tranzactionId))
          issues.add(issue('Missing_In_Salesforce', t.tranzactionId, null, t));
    }
    // Logical charges that already have a Success, with its TranzactionId (N11: same id = the verified retry, not a duplicate)
    Map<String, String> successTidByLogical = new Map<String, String>();
    Set<String> logicals = new Set<String>();
    for (Charge__c c : unknown)
      logicals.add(c.ExternalUniqTranId__c);
    for (Charge__c c : [
      SELECT ExternalUniqTranId__c, Cardcom_Tranzaction_Id__c
      FROM Charge__c
      WHERE ExternalUniqTranId__c IN :logicals AND Status__c = 'Success'
    ]) {
      successTidByLogical.put(c.ExternalUniqTranId__c, c.Cardcom_Tranzaction_Id__c);
    }
    for (Charge__c c : unknown) {
      if (found.containsKey(c.Id)) {
        String tid = String.valueOf(found.get(c.Id).get('TranzactionId'));
        if (successTidByLogical.containsKey(c.ExternalUniqTranId__c)) {
          if (successTidByLogical.get(c.ExternalUniqTranId__c) != tid) {
            issues.add(issue('Duplicate_In_Cardcom', tid, c, null)); // two real charges for one logical charge
          }
          fix.put(c.Id, new Charge__c(Id = c.Id, Needs_Reconciliation__c = false)); // ALREADY_CHARGED case cleared (B6.5.2)
        } else {
          fix.put(
            c.Id,
            new Charge__c(
              Id = c.Id,
              Status__c = 'Success',
              Is_Final_Failure__c = false,
              Error_Category__c = null,
              Cardcom_Tranzaction_Id__c = tid,
              Cardcom_Deal_Number__c = tid,
              Needs_Reconciliation__c = false,
              Error_Code__c = 'RECONCILED',
              Error_Message__c = 'אומת ב-GetTransactionByExternalUniqTran'
            )
          );
          successTidByLogical.put(c.ExternalUniqTranId__c, tid);
        }
      } else if (notFound.contains(c.Id)) {
        fix.put(c.Id, new Charge__c(Id = c.Id, Needs_Reconciliation__c = false));
      }
    }
    if (!fix.isEmpty())
      Database.update(fix.values(), false); // ChargeTrigger recalculates roll-ups
    if (!issues.isEmpty()) {
      Database.upsert(issues, Reconciliation_Issue__c.Issue_Key__c, false);
      StaffAlertService.reconciliationOpen();
    }
  }

  Reconciliation_Issue__c issue(String type, String key, Charge__c c, CardcomService.TxnSummary t) {
    return new Reconciliation_Issue__c(
      Issue_Type__c = type,
      Issue_Key__c = (type + '-' + key).left(120),
      Charge__c = c == null ? null : c.Id,
      Business_Date__c = day,
      ExternalUniqTranId__c = c == null ? null : c.ExternalUniqTranId__c,
      Cardcom_Tranzaction_Id__c = key,
      Cardcom_Amount__c = t == null ? null : t.amount,
      SF_Amount__c = c == null ? null : c.Amount__c,
      Detected_At__c = Datetime.now()
    );
  }
}
