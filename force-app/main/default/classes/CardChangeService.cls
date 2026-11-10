/** Donor-portal card replacement (B6.10, B6.10.1), on the pledge Opportunity (Part C C2). */
public without sharing class CardChangeService {
  /** True if a GetLpResult ReturnValue belongs to a card change ('CARD-…', set by DonorPortalResource.card). */
  public static Boolean isCardChange(String returnValue) {
    return returnValue != null && returnValue.startsWith('CARD-');
  }

  /**
   * Apply a GetLpResult to the CCR. Idempotent: a CCR that is not Pending is returned as-is.
   * Must be called AFTER the GetLpResult callout (does DML). Returns the final CCR status.
   */
  public static String complete(String lpId, Map<String, Object> lpResult) {
    List<Card_Change_Request__c> rows = [
      SELECT
        Id,
        Status__c,
        Pledge__c,
        Link_Version__c,
        New_Amount__c,
        Cardcom_Terminal__c,
        Pledge__r.Cardcom_Terminal__c,
        Pledge__r.Charge_Amount__c,
        Pledge__r.Token__c,
        Pledge__r.CardExpirationMMYY__c,
        Pledge__r.Last4__c,
        Pledge__r.StageName
      FROM Card_Change_Request__c
      WHERE LowProfileId__c = :lpId
      FOR UPDATE
    ];
    if (rows.isEmpty())
      return 'Failed';
    Card_Change_Request__c ccr = rows[0];
    if (ccr.Status__c != 'Pending')
      return ccr.Status__c;
    Integer code = CardcomService.code(lpResult);
    if (code >= 5117 && code <= 5119)
      return 'Pending'; // donor still on the page
    CardcomService.CardData d = code == 0 ? CardcomService.cardFrom(lpResult) : null;
    if (d == null || ccr.Pledge__r.StageName != MicroPledges.STAGE_ACTIVE) {
      ccr.Status__c = 'Failed';
      ccr.Error_Message__c = (code + ' ' + String.valueOf(lpResult.get('Description'))).left(255);
      ccr.Completed_At__c = Datetime.now();
      update ccr; // old token untouched
      return 'Failed';
    }
    insert new Pledge_Card_History__c(
      Pledge__c = ccr.Pledge__c,
      Token__c = ccr.Pledge__r.Token__c,
      CardExpirationMMYY__c = ccr.Pledge__r.CardExpirationMMYY__c,
      Last4__c = ccr.Pledge__r.Last4__c,
      Cardcom_Terminal__c = CardcomService.terminalKey(ccr.Pledge__r.Cardcom_Terminal__c),
      Replaced_At__c = Datetime.now(),
      Replaced_By_Request__c = ccr.Id
    );
    Opportunity upd = new Opportunity(
      Id = ccr.Pledge__c,
      Token__c = d.token,
      CardExpirationMMYY__c = d.expMMYY,
      Token_Expiry_Date__c = d.tokenExpiry,
      Last4__c = d.last4,
      Cardcom_Terminal__c = CardcomService.terminalKey(ccr.Cardcom_Terminal__c), // D39: the new token's terminal
      Payment_Issue_Since__c = null, // D37: a new card ends the failed-charge reminders
      Failure_Reminders_Stopped__c = false
    ); // last4 null until next charge (B5.3)
    List<Pledge_Change_Log__c> logs = new List<Pledge_Change_Log__c>();
    Boolean amountChanged = ccr.New_Amount__c != null && ccr.New_Amount__c != ccr.Pledge__r.Charge_Amount__c;
    if (amountChanged) {
      upd.Charge_Amount__c = ccr.New_Amount__c; // chosen with the card on the donor page; D16: from the next created charge
      logs.add(
        new Pledge_Change_Log__c(
          Pledge__c = ccr.Pledge__c,
          Change_Type__c = 'Amount',
          Old_Value__c = String.valueOf(ccr.Pledge__r.Charge_Amount__c),
          New_Value__c = String.valueOf(ccr.New_Amount__c),
          Source__c = 'Donor_Portal',
          Link_Version__c = ccr.Link_Version__c
        )
      );
    }
    update upd;
    logs.add(
      new Pledge_Change_Log__c(
        Pledge__c = ccr.Pledge__c,
        Change_Type__c = 'Card',
        Old_Value__c = ccr.Pledge__r.Last4__c == null ? null : '****' + ccr.Pledge__r.Last4__c,
        New_Value__c = d.last4 == null ? 'כרטיס חדש' : '****' + d.last4,
        Source__c = 'Donor_Portal',
        Link_Version__c = ccr.Link_Version__c
      )
    );
    insert logs;
    ccr.Status__c = 'Completed';
    ccr.Completed_At__c = Datetime.now();
    update ccr;
    return 'Completed';
  }

  /** CCRs still Pending after 30 minutes → Expired (called by PendingVerificationSweeper). */
  public static void expireStale() {
    Datetime cutoff = Datetime.now().addMinutes(-30);
    List<Card_Change_Request__c> old = [
      SELECT Id
      FROM Card_Change_Request__c
      WHERE Status__c = 'Pending' AND CreatedDate < :cutoff
      LIMIT 500
    ];
    for (Card_Change_Request__c c : old)
      c.Status__c = 'Expired';
    update old;
  }
}
