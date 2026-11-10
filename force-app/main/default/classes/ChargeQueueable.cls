/**
 * One link of the charge chain (B6.5.1). Order: (1) SELECT, no DML; (2) per charge: verify the previous unknown attempt (B5.5),
 * else charge the token with ExternalUniqTranId = Attempt_Key__c (B5.4); (3) all DML at the end; (4) enqueue the next link.
 * Stops calling out when the transaction's callout budget runs low; the rest stay Pending for the next link (spec-consistency N51).
 */
public without sharing class ChargeQueueable implements Queueable, Database.AllowsCallouts {
  @TestVisible
  static Integer CALLOUT_BUDGET_MS = 90000; // platform limit: 120 s of callout time per transaction
  @TestVisible
  static Integer CALLOUTS_PER_CHARGE = 2; // verify + charge
  final List<Id> chargeIds;
  public ChargeQueueable(List<Id> ids) {
    chargeIds = ids;
  }

  public void execute(QueueableContext ctx) {
    List<Charge__c> charges = [
      SELECT
        Id,
        Pledge__c,
        Contact__c,
        Amount__c,
        Scheduled_Date__c,
        Run_Date__c,
        Slot__c,
        Attempt_Number__c,
        Attempt_Key__c,
        ExternalUniqTranId__c,
        Verify_Attempt_Key__c,
        Status__c,
        Cardcom_Terminal__c,
        Pledge__r.Cardcom_Terminal__c,
        Pledge__r.StageName,
        Pledge__r.Token__c,
        Pledge__r.CardExpirationMMYY__c,
        Pledge__r.Last4__c
      FROM Charge__c
      WHERE Id IN :chargeIds AND Status__c = 'Pending'
    ];
    List<ChargeOutcomeHandler.Result> results = new List<ChargeOutcomeHandler.Result>();
    Map<Id, String> last4ByPledge = new Map<Id, String>();
    Long started = System.currentTimeMillis();
    for (Charge__c c : charges) {
      if (c.Pledge__r.StageName != MicroPledges.STAGE_ACTIVE) {
        results.add(ChargeOutcomeHandler.stopped(c));
        continue;
      }
      if (String.isBlank(c.Pledge__r.Token__c)) {
        results.add(ChargeOutcomeHandler.noToken(c));
        continue;
      }
      if (
        System.currentTimeMillis() - started > CALLOUT_BUDGET_MS ||
        Limits.getCallouts() + CALLOUTS_PER_CHARGE > Limits.getLimitCallouts()
      )
        break; // left Pending for the next link
      try {
        // 1) previous attempt ended with unknown outcome → ask Cardcom before charging again
        // D39: the previous attempt's terminal was copied to this attempt (ChargeOutcomeHandler.scheduleRetry); the card, and
        // with it the terminal, may have been replaced since.
        String terminal = CardcomService.terminalKey(c.Pledge__r.Cardcom_Terminal__c);
        if (String.isNotBlank(c.Verify_Attempt_Key__c)) {
          String prevTerminal = c.Cardcom_Terminal__c == null ? terminal : c.Cardcom_Terminal__c;
          Map<String, Object> prev = CardcomService.findSuccessByExternalId(prevTerminal, c.Verify_Attempt_Key__c);
          if (prev != null) {
            results.add(ChargeOutcomeHandler.alreadyCharged(c, prev));
            continue;
          }
        }
        // 2) charge (ExternalUniqTranId = per-attempt key, ExternalUniqUniqTranIdResponse = true)
        c.Cardcom_Terminal__c = terminal; // the terminal this attempt is sent to
        Map<String, Object> resp = CardcomService.chargeToken(
          terminal,
          c.Pledge__r.Token__c,
          c.Pledge__r.CardExpirationMMYY__c,
          c.Amount__c,
          c.Attempt_Key__c
        );
        ChargeOutcomeHandler.Result r = ChargeOutcomeHandler.fromResponse(c, resp);
        results.add(r);
        String l4 = resp.get('Last4CardDigitsString') == null ? null : String.valueOf(resp.get('Last4CardDigitsString'));
        if (c.Status__c == 'Success' && String.isNotBlank(l4) && l4 != c.Pledge__r.Last4__c)
          last4ByPledge.put(c.Pledge__c, l4);
      } catch (CardcomService.TerminalConfigException e) {
        results.add(ChargeOutcomeHandler.fromConfigError(c, 'CONFIG_ERROR', e)); // terminal number missing: nothing was sent
      } catch (CardcomService.CardcomHttpException e) {
        results.add(
          e.status == 401 ||
            e.status == 400
            ? ChargeOutcomeHandler.fromConfigError(c, 'HTTP_' + e.status, e)
            : ChargeOutcomeHandler.fromException(c, 'HTTP_' + e.status, e)
        );
      } catch (System.CalloutException e) {
        // No access to the Named/External Credential: nothing reached Cardcom → Config (no retry, staff alert), not TIMEOUT
        results.add(
          isCredentialError(e)
            ? ChargeOutcomeHandler.fromConfigError(c, 'CONFIG_ERROR', e)
            : ChargeOutcomeHandler.fromException(c, 'TIMEOUT', e)
        );
      } catch (Exception e) {
        results.add(ChargeOutcomeHandler.fromException(c, 'EXCEPTION', e));
      }
    }
    // ---- all DML after all callouts ----
    ChargeOutcomeHandler.commitResults(results);
    if (!last4ByPledge.isEmpty()) {
      List<Opportunity> ps = new List<Opportunity>();
      for (Id pid : last4ByPledge.keySet())
        ps.add(new Opportunity(Id = pid, Last4__c = last4ByPledge.get(pid)));
      update ps;
    }
    if (!Test.isRunningTest())
      ChargeDispatcher.start(); // next link
  }

  /**
   * The callout never left Salesforce because the running user can't use the credential ("We couldn't access the credential(s)…",
   * missing Named Credential, or an unauthorized endpoint). Everything else (e.g. "Read timed out") is an unknown outcome.
   */
  @TestVisible
  static Boolean isCredentialError(Exception e) {
    String m = e.getMessage() == null ? '' : e.getMessage().toLowerCase();
    return m.contains('credential') || m.contains('unauthorized endpoint');
  }
}
