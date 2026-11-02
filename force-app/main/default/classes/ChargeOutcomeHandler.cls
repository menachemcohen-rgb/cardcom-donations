/** Charge outcome handling (B6.5.2, authoritative). Callers do all callouts first; commitResults does all DML. */
public without sharing class ChargeOutcomeHandler {
  public class Result {
    public Charge__c charge;
    public Charge__c nextAttempt;
    public Boolean configError = false;
  }

  public static Result stopped(Charge__c c) {
    Result r = new Result();
    r.charge = c;
    c.Status__c = 'Skipped';
    c.Error_Code__c = 'STOPPED';
    c.Error_Message__c = 'חיובים הופסקו';
    c.Executed_At__c = Datetime.now();
    return r;
  }

  public static Result noToken(Charge__c c) {
    Result r = new Result();
    r.charge = c;
    c.Status__c = 'Failed';
    c.Error_Code__c = 'NO_TOKEN';
    c.Error_Category__c = 'Config';
    c.Is_Final_Failure__c = false;
    c.Executed_At__c = Datetime.now();
    r.configError = true;
    return r;
  }

  /** Previous attempt (Verify_Attempt_Key__c) turned out successful in Cardcom → no new charge. */
  public static Result alreadyCharged(Charge__c c, Map<String, Object> prev) {
    Result r = new Result();
    r.charge = c;
    markSuccess(c, prev); // the logical charge is paid; this record carries the Cardcom data
    c.Error_Code__c = 'ALREADY_CHARGED';
    c.Error_Message__c = ('הניסיון הקודם (' + c.Verify_Attempt_Key__c + ') הצליח ב-Cardcom').left(255);
    c.Executed_At__c = Datetime.now();
    return r;
  }

  public static Result fromResponse(Charge__c c, Map<String, Object> resp) {
    Result r = new Result();
    r.charge = c;
    c.Executed_At__c = Datetime.now();
    c.Raw_Response__c = CardcomService.redact(resp);
    Integer code = CardcomService.code(resp);
    c.Error_Code__c = String.valueOf(code);
    c.Error_Message__c = resp.get('Description') == null ? null : String.valueOf(resp.get('Description')).left(255);
    if (code == 0) {
      markSuccess(c, resp);
      return r;
    }
    if (code == 608) {
      // only if ExternalUniqUniqTranIdResponse=false was sent (B5.4) — fallback
      c.Status__c = 'Skipped';
      c.Error_Category__c = 'Duplicate';
      c.Needs_Reconciliation__c = true;
      return r;
    }
    String cat = ChargeErrorClassifier.classify(code);
    if (cat == 'Pending' || cat == 'Duplicate')
      cat = 'Retryable'; // LP-only / 608-only categories; not valid here (N12)
    c.Error_Category__c = cat;
    c.Status__c = 'Failed';
    if (cat == 'Card_Dead') {
      c.Is_Final_Failure__c = true;
      return r;
    } // D11/D12: no retry; next scheduled charges continue
    if (cat == 'Config') {
      r.configError = true;
      return r;
    } // no retry, not counted in streak
    return scheduleRetry(r, false); // Card_Declined / Retryable
  }

  public static Result fromConfigError(Charge__c c, String kind, Exception e) {
    Result r = new Result();
    r.charge = c;
    c.Executed_At__c = Datetime.now();
    c.Status__c = 'Failed';
    c.Error_Code__c = kind;
    c.Error_Category__c = 'Config';
    c.Error_Message__c = e.getMessage().left(255);
    r.configError = true;
    return r;
  }

  /** Outcome unknown (timeout / 5xx / exception): next attempt must verify this attempt's key first. */
  public static Result fromException(Charge__c c, String kind, Exception e) {
    Result r = new Result();
    r.charge = c;
    c.Executed_At__c = Datetime.now();
    c.Status__c = 'Failed';
    c.Error_Code__c = kind;
    c.Error_Category__c = 'Unknown';
    c.Error_Message__c = e.getMessage() == null ? null : e.getMessage().left(255);
    c.Needs_Reconciliation__c = true;
    return scheduleRetry(r, true);
  }

  static void markSuccess(Charge__c c, Map<String, Object> m) {
    c.Status__c = 'Success';
    c.Is_Final_Failure__c = false;
    c.Error_Category__c = null;
    c.Needs_Reconciliation__c = false;
    String tid = String.valueOf(m.get('TranzactionId')); // ✔ TransactionInfo.TranzactionId (B5.4)
    c.Cardcom_Tranzaction_Id__c = tid;
    c.Cardcom_Deal_Number__c = tid; // DealNumber for CreateDocument (B5.7, U4)
    c.Cardcom_Approval_Number__c = m.get('ApprovalNumber') == null ? null : String.valueOf(m.get('ApprovalNumber'));
    c.Error_Code__c = null;
    c.Error_Message__c = null;
  }

  static Result scheduleRetry(Result r, Boolean unknownOutcome) {
    Charge__c c = r.charge;
    Integer max = ChargeSettings.get().Max_Retries__c.intValue();
    Integer n = c.Attempt_Number__c.intValue();
    if (n >= max) {
      c.Is_Final_Failure__c = true;
      return r;
    }
    Datetime nb = ChargeRetryPolicy.nextWindow(ChargeCalendar.now().addMinutes(ChargeRetryPolicy.delayMinutes(n)));
    r.nextAttempt = new Charge__c(
      Pledge__c = c.Pledge__c,
      Contact__c = c.Contact__c,
      Amount__c = c.Amount__c,
      Scheduled_Date__c = c.Scheduled_Date__c,
      Run_Date__c = nb.date(),
      Slot__c = c.Slot__c,
      Status__c = 'Pending',
      Attempt_Number__c = n + 1,
      ExternalUniqTranId__c = c.ExternalUniqTranId__c,
      Attempt_Key__c = c.ExternalUniqTranId__c + '-A' + (n + 1),
      Not_Before__c = nb,
      Verify_Attempt_Key__c = unknownOutcome ? c.Attempt_Key__c : null
    );
    return r;
  }

  /**
   * All DML for one link. Partial success (spec-consistency N53): a row that fails to save stays Pending and is re-sent with the
   * same Attempt_Key__c, which Cardcom answers with the original transaction (ExternalUniqUniqTranIdResponse=true) — no double charge.
   */
  public static void commitResults(List<Result> results) {
    List<Charge__c> upd = new List<Charge__c>();
    for (Result r : results)
      upd.add(r.charge);
    if (upd.isEmpty())
      return;
    List<Database.SaveResult> srs = Database.update(upd, false); // ChargeTrigger → PledgeRollupService (B6.7)
    List<Charge__c> ins = new List<Charge__c>();
    List<Id> successIds = new List<Id>();
    Boolean cfg = false;
    for (Integer i = 0; i < results.size(); i++) {
      Result r = results[i];
      if (!srs[i].isSuccess()) {
        System.debug(LoggingLevel.ERROR, 'Charge update failed ' + r.charge.Id + ': ' + srs[i].getErrors()[0].getMessage());
        continue;
      }
      if (r.nextAttempt != null)
        ins.add(r.nextAttempt);
      if (r.charge.Status__c == 'Success')
        successIds.add(r.charge.Id);
      cfg |= r.configError;
    }
    if (!ins.isEmpty())
      Database.insert(ins, false); // duplicate Attempt_Key → ignored (idempotent)
    if (!successIds.isEmpty())
      EventBus.publish(new Charge_Success__e(Charge_Ids__c = String.join(successIds, ',')));
    if (cfg)
      StaffAlertService.configErrorOncePerDay();
  }
}
