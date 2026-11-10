/**
 * Nightly reconciliation against Cardcom ListTransactions (B6.12, Part C E2, spec-consistency N11).
 * Schedulable at Charge_Settings__c.Reconcile_Time__c (DonationSetup) → Queueable for yesterday (Run_Date__c = day).
 * Match key = TranzactionId. The only automatic fix: an attempt with an unknown outcome that Cardcom confirms as successful.
 * Issues are upserted by Issue_Key__c, so a re-run never duplicates them and never reopens one staff resolved.
 * A class that is Schedulable can't be enqueued, so the callouts run in the inner Queueable Job.
 *
 * List unusable (N86): the day has Success charges but none of their TranzactionIds is in the list (empty list, or another
 * terminal's deals — seen with the sandbox credentials and LimitForTerminal). Then nothing is compared against the list
 * (no Missing_In_Cardcom / Missing_In_Salesforce from it), staff get one alert a day, and each Success charge is looked up
 * by the key sent to Cardcom (GetTransactionByExternalUniqTran) instead, FALLBACK_PER_JOB per job, chained in FallbackJob.
 */
public without sharing class ReconciliationJob implements Schedulable {
  @TestVisible
  static Date dayOverride;
  @TestVisible
  static final Integer MAX_PAGES = 20; // 20 × 1,000 rows; + 50 lookups < 100 callouts
  @TestVisible
  static final Integer MAX_LOOKUPS = 50;
  @TestVisible
  static Integer FALLBACK_PER_JOB = 40; // callouts per job for the per-charge fallback (also bounded by the callout limit)
  @TestVisible
  static List<Id> chainedFallback; // tests: what would have been enqueued
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

  /** Continues the per-charge fallback for the charges the previous job had no callouts left for. */
  public class FallbackJob implements Queueable, Database.AllowsCallouts {
    final Date day;
    final List<Id> chargeIds;
    public FallbackJob(Date d, List<Id> ids) {
      day = d;
      chargeIds = ids;
    }
    public void execute(QueueableContext qc) {
      new ReconciliationJob(day).fallback(chargeIds);
    }
  }

  @TestVisible
  void run() {
    Cardcom_Setting__mdt s = CardcomService.settings();
    Integer pageSize = s.Recon_Page_Size__c == null ? 1000 : s.Recon_Page_Size__c.intValue();

    // ---- reads + callouts (no DML before them) ----
    Map<String, CardcomService.TxnSummary> cc = new Map<String, CardcomService.TxnSummary>();
    try {
      // D39: one list per terminal, merged (TranzactionId is Cardcom's own deal number)
      for (String terminal : CardcomService.terminals()) {
        for (Integer page = 1; page <= MAX_PAGES; page++) {
          List<CardcomService.TxnSummary> rows = CardcomService.listTransactions(terminal, day, page, pageSize);
          for (CardcomService.TxnSummary t : rows) {
            CardcomService.TxnSummary prev = cc.get(t.tranzactionId);
            if (prev == null || t.isRefundOrCancel)
              cc.put(t.tranzactionId, t);
          }
          if (rows.size() < pageSize)
            break; // a partial page is the last one
        }
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
      SELECT Id, Attempt_Key__c, ExternalUniqTranId__c, Amount__c, Cardcom_Terminal__c
      FROM Charge__c
      WHERE Needs_Reconciliation__c = TRUE AND Cardcom_Tranzaction_Id__c = NULL AND Run_Date__c >= :since
      ORDER BY Run_Date__c
      LIMIT :MAX_LOOKUPS
    ];
    Map<Id, Map<String, Object>> found = new Map<Id, Map<String, Object>>();
    Set<Id> notFound = new Set<Id>();
    for (Charge__c c : unknown) {
      try {
        Map<String, Object> t = CardcomService.findSuccessByExternalId(c.Cardcom_Terminal__c, c.Attempt_Key__c);
        if (t != null)
          found.put(c.Id, t);
        else
          notFound.add(c.Id);
      } catch (Exception e) {
        /* try again tomorrow */
      }
    }

    List<Charge__c> daySuccess = successCharges(null);
    Boolean listUsable = isListUsable(cc, daySuccess);
    Verification fb = new Verification();
    List<Id> deferred = new List<Id>();
    if (!listUsable) {
      List<Charge__c> slice = new List<Charge__c>();
      for (Charge__c c : daySuccess) {
        if (slice.size() < fallbackBudget())
          slice.add(c);
        else
          deferred.add(c.Id);
      }
      fb = verify(slice); // callouts, still before any DML
    }

    // ---- DML ----
    List<Reconciliation_Issue__c> issues = new List<Reconciliation_Issue__c>();
    Map<Id, Charge__c> fix = new Map<Id, Charge__c>();
    if (!listUsable)
      issues.addAll(fallbackIssues(fb, fix));
    for (Charge__c c : listUsable ? daySuccess : new List<Charge__c>()) {
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
    if (listUsable && s.Recon_Report_Unknown__c != false && !cc.isEmpty()) {
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
    if (!listUsable) {
      StaffAlertService.reconciliationUnavailable(day, daySuccess.size(), fb.checked());
      chain(deferred);
    }
  }

  // ---------------------------------------------------------------- fallback (N86)
  /** The list can be compared only if it contains at least one of the day's Success TranzactionIds (or there is nothing to compare). */
  @TestVisible
  static Boolean isListUsable(Map<String, CardcomService.TxnSummary> cc, List<Charge__c> daySuccess) {
    if (daySuccess.isEmpty())
      return true;
    for (Charge__c c : daySuccess)
      if (cc.containsKey(c.Cardcom_Tranzaction_Id__c))
        return true;
    return false;
  }

  List<Charge__c> successCharges(List<Id> onlyIds) {
    Date d = day; // dynamic SOQL binds local variables
    List<Id> ids = onlyIds;
    String q =
      'SELECT Id, Amount__c, Cardcom_Tranzaction_Id__c, ExternalUniqTranId__c, Attempt_Key__c, Verify_Attempt_Key__c, ' +
      'Error_Code__c, Needs_Reconciliation__c, Cardcom_Terminal__c FROM Charge__c ' +
      'WHERE Run_Date__c = :d AND Status__c = \'Success\' AND Cardcom_Tranzaction_Id__c != NULL' +
      (ids == null ? '' : ' AND Id IN :ids') +
      ' ORDER BY Id';
    return Database.query(q);
  }

  /** Callouts left for fallback lookups in this transaction (keeps a margin of 2). */
  static Integer fallbackBudget() {
    return Math.max(0, Math.min(FALLBACK_PER_JOB, Limits.getLimitCallouts() - Limits.getCallouts() - 2));
  }

  /** The key Cardcom was actually charged with: an ALREADY_CHARGED record carries the earlier attempt's key (B6.5.2). */
  @TestVisible
  static String chargedKey(Charge__c c) {
    return c.Error_Code__c == 'ALREADY_CHARGED' && String.isNotBlank(c.Verify_Attempt_Key__c) ? c.Verify_Attempt_Key__c : c.Attempt_Key__c;
  }

  public class Verification {
    public List<Charge__c> charges = new List<Charge__c>();
    public Map<Id, Map<String, Object>> found = new Map<Id, Map<String, Object>>();
    public Set<Id> notFound = new Set<Id>();
    public Integer checked() {
      return found.size() + notFound.size();
    }
  }

  /** One GetTransactionByExternalUniqTran per charge. A failed lookup leaves the charge unverified (no issue). */
  static Verification verify(List<Charge__c> charges) {
    Verification v = new Verification();
    v.charges = charges;
    for (Charge__c c : charges) {
      try {
        Map<String, Object> t = CardcomService.findSuccessByExternalId(c.Cardcom_Terminal__c, chargedKey(c));
        if (t != null)
          v.found.put(c.Id, t);
        else
          v.notFound.add(c.Id);
      } catch (Exception e) {
        System.debug(LoggingLevel.WARN, 'Reconciliation lookup failed for ' + c.Id + ': ' + e.getMessage());
      }
    }
    return v;
  }

  /** Not found → Missing_In_Cardcom; found with another amount → Amount_Mismatch; found and equal → flag cleared. */
  List<Reconciliation_Issue__c> fallbackIssues(Verification v, Map<Id, Charge__c> fix) {
    List<Reconciliation_Issue__c> out = new List<Reconciliation_Issue__c>();
    for (Charge__c c : v.charges) {
      if (v.notFound.contains(c.Id)) {
        out.add(issue('Missing_In_Cardcom', c.Cardcom_Tranzaction_Id__c, c, null));
      } else if (v.found.containsKey(c.Id)) {
        Object raw = v.found.get(c.Id).get('Amount');
        CardcomService.TxnSummary t = new CardcomService.TxnSummary();
        t.tranzactionId = String.valueOf(v.found.get(c.Id).get('TranzactionId'));
        t.amount = raw == null ? null : Decimal.valueOf(String.valueOf(raw));
        if (t.amount != null && t.amount != c.Amount__c)
          out.add(issue('Amount_Mismatch', c.Cardcom_Tranzaction_Id__c, c, t));
        else if (c.Needs_Reconciliation__c)
          fix.put(c.Id, new Charge__c(Id = c.Id, Needs_Reconciliation__c = false));
      }
    }
    return out;
  }

  /** Runs in FallbackJob: the next slice of charges, then chains the rest. */
  @TestVisible
  void fallback(List<Id> chargeIds) {
    List<Charge__c> all = successCharges(chargeIds);
    List<Charge__c> slice = new List<Charge__c>();
    List<Id> rest = new List<Id>();
    for (Charge__c c : all) {
      if (slice.size() < fallbackBudget())
        slice.add(c);
      else
        rest.add(c.Id);
    }
    Verification v = verify(slice);
    Map<Id, Charge__c> fix = new Map<Id, Charge__c>();
    List<Reconciliation_Issue__c> issues = fallbackIssues(v, fix);
    if (!fix.isEmpty())
      Database.update(fix.values(), false);
    if (!issues.isEmpty()) {
      Database.upsert(issues, Reconciliation_Issue__c.Issue_Key__c, false);
      StaffAlertService.reconciliationOpen();
    }
    chain(rest);
  }

  void chain(List<Id> rest) {
    if (rest.isEmpty())
      return;
    chainedFallback = rest;
    if (!Test.isRunningTest())
      System.enqueueJob(new FallbackJob(day, rest));
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
