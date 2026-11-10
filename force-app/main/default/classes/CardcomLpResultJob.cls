/**
 * Reads LowProfile/GetLpResult for webhook / sweeper LowProfileIds and stores the token on the pledge Opportunity
 * (Part A 7.5, B5.3, B6.3, Part C C2). Idempotent: a pledge with Lp_Processed__c=true is never called again.
 * Callouts happen before any DML. Queries and DML are bulk (spec-consistency N37): one query, one insert, one update.
 * D39 (two terminals): a LowProfileId exists only on the terminal that created it. The first terminal asked is the card
 * change's, else the pledge's, else the one named on the webhook URL, else the primary. For a signup none of these is trusted:
 * when the answer is neither a token nor "donor still on the page", the other terminal is asked too. The terminal that returned
 * the token is stored on the pledge.
 */
public without sharing class CardcomLpResultJob implements Queueable, Database.AllowsCallouts {
  @TestVisible
  static final Integer MAX_CALLOUTS = 90; // one GetLpResult per LowProfileId; platform limit is 100
  @TestVisible
  static final Integer MAX_LP_CHECKS = 6; // B5.3: 6 checks (90 min) → Verification_Failed
  final List<String> lpIds;
  final Map<String, String> hints; // lower-case LowProfileId → terminal from the webhook URL
  public CardcomLpResultJob(List<String> lpIds) {
    this(lpIds, null);
  }
  public CardcomLpResultJob(List<String> lpIds, Map<String, String> hints) {
    this.lpIds = lpIds;
    this.hints = hints == null ? new Map<String, String>() : hints;
  }

  public void execute(QueueableContext ctx) {
    run();
  }

  /** GetLpResult on one terminal; null when the call failed (HTTP error, timeout). */
  static Map<String, Object> lpResult(String terminal, String lp) {
    try {
      return CardcomService.getLpResult(terminal, lp);
    } catch (Exception e) {
      System.debug(LoggingLevel.WARN, 'GetLpResult (' + terminal + ') failed for ' + lp + ': ' + e.getMessage());
      return null;
    }
  }

  @TestVisible
  void run() {
    String pledgeType = MicroPledges.TYPE;
    // 1) reads + callouts first (no DML before them)
    Set<String> cardChange = new Set<String>();
    Map<String, String> firstTerminal = new Map<String, String>(); // lower-case LowProfileId → terminal to ask first
    for (Card_Change_Request__c c : [
      SELECT LowProfileId__c, Cardcom_Terminal__c
      FROM Card_Change_Request__c
      WHERE LowProfileId__c IN :lpIds
    ]) {
      cardChange.add(c.LowProfileId__c);
      firstTerminal.put(c.LowProfileId__c.toLowerCase(), c.Cardcom_Terminal__c);
    }
    Set<String> done = new Set<String>();
    for (Opportunity p : [
      SELECT LowProfileId__c, Lp_Processed__c, Cardcom_Terminal__c
      FROM Opportunity
      WHERE LowProfileId__c IN :lpIds AND Type = :pledgeType
    ]) {
      if (p.Lp_Processed__c)
        done.add(p.LowProfileId__c.toLowerCase());
      else if (p.Cardcom_Terminal__c != null)
        firstTerminal.put(p.LowProfileId__c.toLowerCase(), p.Cardcom_Terminal__c);
    }
    Map<String, Map<String, Object>> results = new Map<String, Map<String, Object>>();
    Map<String, String> terminalOf = new Map<String, String>(); // LowProfileId → terminal whose answer is in results
    Boolean two = CardcomService.hasSecondary();
    for (String lp : lpIds) {
      if (String.isBlank(lp) || done.contains(lp.toLowerCase()) || results.containsKey(lp))
        continue; // webhook retries 2..7 → no-op
      if (results.size() >= MAX_CALLOUTS || Limits.getCallouts() + 2 > Limits.getLimitCallouts())
        break; // the sweeper picks up the rest
      String key = lp.toLowerCase();
      String guess = firstTerminal.get(key) != null ? firstTerminal.get(key) : hints.get(key);
      String ask = two ? CardcomService.terminalKey(guess) : CardcomService.PRIMARY;
      Map<String, Object> r = lpResult(ask, lp);
      String used = ask;
      if (two && !cardChange.contains(lp) && (r == null || !CardcomService.isLpKnown(r))) {
        Map<String, Object> r2 = lpResult(CardcomService.otherTerminal(ask), lp);
        if (r2 != null && CardcomService.isLpKnown(r2)) {
          r = r2;
          used = CardcomService.otherTerminal(ask);
        }
      }
      if (r == null)
        continue; // sweeper will retry
      results.put(lp, r);
      terminalOf.put(lp, used);
    }
    if (results.isEmpty())
      return;

    // 2) DML
    Map<String, Opportunity> existing = new Map<String, Opportunity>();
    List<Opportunity> locked = [
      SELECT Id, LowProfileId__c, StageName, Lp_Check_Count__c
      FROM Opportunity
      WHERE LowProfileId__c IN :results.keySet() AND Type = :pledgeType
      FOR UPDATE
    ];
    for (Opportunity p : locked)
      existing.put(p.LowProfileId__c.toLowerCase(), p);
    List<Opportunity> inserts = new List<Opportunity>();
    List<Opportunity> updates = new List<Opportunity>();
    Set<String> verified = new Set<String>();
    for (String lp : results.keySet()) {
      Map<String, Object> r = results.get(lp);
      if (cardChange.contains(lp)) {
        CardChangeService.complete(lp, r);
        continue;
      }
      String rv = r.get('ReturnValue') == null ? null : String.valueOf(r.get('ReturnValue'));
      if (CardChangeService.isCardChange(rv))
        continue; // CCR not inserted yet (race) → status poll / sweeper handles it
      Integer code = CardcomService.code(r);
      if (code >= 5117 && code <= 5119)
        continue; // donor still on the payment page (B5.3)
      CardcomService.CardData d = code == 0 ? CardcomService.cardFrom(r) : null;
      Opportunity ex = existing.get(lp.toLowerCase());
      Opportunity p = ex == null ? MicroPledges.newPending(lp) : new Opportunity(Id = ex.Id);
      if (d != null) {
        p.Token__c = d.token;
        p.CardExpirationMMYY__c = d.expMMYY;
        p.Token_Expiry_Date__c = d.tokenExpiry;
        p.Cardcom_Terminal__c = terminalOf.get(lp); // the token is charged on the terminal that created it
        if (d.last4 != null)
          p.Last4__c = d.last4;
        p.Lp_Processed__c = true;
        p.Verified_At__c = Datetime.now();
        verified.add(lp.toLowerCase());
      } else {
        Decimal n = (ex == null || ex.Lp_Check_Count__c == null ? 0 : ex.Lp_Check_Count__c) + 1;
        p.Lp_Check_Count__c = n;
        if (n >= MAX_LP_CHECKS) {
          p.StageName = MicroPledges.STAGE_VERIFICATION_FAILED;
          p.Lp_Processed__c = true;
        }
      }
      if (ex == null)
        inserts.add(p);
      else
        updates.add(p);
    }
    if (!updates.isEmpty())
      update updates;
    if (!inserts.isEmpty()) {
      // A failed insert means a parallel submit created the pledge first (unique LowProfileId); the sweeper retries it.
      List<Database.SaveResult> srs = Database.insert(inserts, false);
      for (Integer i = 0; i < srs.size(); i++) {
        if (!srs[i].isSuccess()) {
          System.debug(
            LoggingLevel.WARN,
            'Pledge insert failed for ' + inserts[i].LowProfileId__c + ': ' + srs[i].getErrors()[0].getMessage()
          );
        }
      }
    }
    List<Cardcom_Webhook_Log__c> logs = [
      SELECT Id
      FROM Cardcom_Webhook_Log__c
      WHERE LowProfileId__c IN :results.keySet() AND Processed__c = FALSE
    ];
    for (Cardcom_Webhook_Log__c l : logs)
      l.Processed__c = true;
    update logs;

    // 3) Contact matching + activation (integration user); activates only if Donor_Submitted__c (B6.4)
    List<Id> toActivate = new List<Id>();
    for (Opportunity p : updates)
      if (p.Lp_Processed__c == true && p.Token__c != null)
        toActivate.add(p.Id);
    for (Opportunity p : inserts)
      if (p.Id != null && p.Token__c != null)
        toActivate.add(p.Id);
    PledgeActivationService.activateAll(toActivate);
  }
}
