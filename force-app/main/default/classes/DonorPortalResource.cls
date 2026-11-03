/**
 * Donor portal API for the WordPress page (B4 /donor/*, B6.10, B6.10.1), adapted to the pledge Opportunity (Part C):
 * amount = Charge_Amount__c (D16: applies to charges created after the change), status = StageName.
 * Called server-to-server by WordPress through the External Client App (D27); the browser never talks to Salesforce.
 */
@RestResource(urlMapping='/donor/*')
global without sharing class DonorPortalResource {
  class PortalException extends Exception {
    Integer status;
    String code;
  }
  static PortalException err(Integer s, String c) {
    PortalException e = new PortalException(c);
    e.status = s;
    e.code = c;
    return e;
  }

  @HttpPost
  global static void handle() {
    RestResponse res = RestContext.response;
    res.addHeader('Content-Type', 'application/json; charset=utf-8');
    Map<String, Object> out;
    try {
      Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(RestContext.request.requestBody.toString());
      String path = RestContext.request.requestURI.substringAfter('/donor/').removeEnd('/');
      String token = (String) body.get('token');
      String ip = (String) body.get('clientIp');
      switch on path {
        when 'context' {
          out = context(token, ip, (String) body.get('verifyCode'));
        }
        when 'amount' {
          out = amount(token, ip, body.get('amount'));
        }
        when 'card' {
          out = card(token, ip, (String) body.get('returnUrlBase'), body.get('amount'));
        }
        when 'stop' {
          out = stop(token, ip);
        }
        when 'card/status' {
          out = cardStatus(token, ip, (String) body.get('lowProfileId'));
        }
        when else {
          throw err(404, 'NOT_FOUND');
        }
      }
      res.statusCode = 200;
    } catch (DonorLinkToken.LinkException e) {
      res.statusCode = 403;
      out = new Map<String, Object>{ 'error' => 'LINK_INVALID' };
    } catch (PortalException e) {
      res.statusCode = e.status;
      out = new Map<String, Object>{ 'error' => e.code };
    } catch (IllegalArgumentException e) {
      res.statusCode = 400;
      out = new Map<String, Object>{ 'error' => 'BAD_RETURN_URL' }; // N69
    } catch (Exception e) {
      System.debug(LoggingLevel.ERROR, 'DonorPortal ' + e.getMessage() + ' ' + e.getStackTraceString());
      res.statusCode = 500;
      out = new Map<String, Object>{ 'error' => 'INTERNAL' };
    }
    DonorLinkLog.flush();
    res.responseBody = Blob.valueOf(JSON.serialize(out));
  }

  /**
   * Either email link (card or amount) may do every action: the page shows all tabs, and the card step can carry a new amount.
   * Both links go to the same donor; the action in the token only picks the tab that opens first (N92).
   */
  static Set<String> BOTH = new Set<String>{ 'card', 'amount' };

  static Map<String, Object> context(String token, String ip, String verifyCode) {
    Opportunity p = DonorLinkToken.verify(token, BOTH, ip);
    Cardcom_Setting__mdt s = CardcomService.settings();
    if (s.Optional_Verify_On_Open__c == true)
      checkVerifyCode(p, verifyCode, ip); // B6.9.6 (off by default)
    List<Integer> presets = new List<Integer>();
    for (String x : s.Amount_Presets__c.split(','))
      presets.add(Integer.valueOf(x.trim()));
    return new Map<String, Object>{
      'action' => DonorLinkToken.parse(token).action,
      'firstName' => String.isNotBlank(p.Donor_Contact__r.FirstName) ? p.Donor_Contact__r.FirstName : p.Donor_First_Name__c,
      'amount' => p.Charge_Amount__c,
      'frequency' => p.Frequency__c,
      'last4' => p.Last4__c,
      'expMMYY' => p.CardExpirationMMYY__c,
      'status' => p.StageName,
      'minAmount' => s.Min_Amount__c,
      'maxAmount' => s.Max_Amount__c,
      'presets' => presets
    };
  }

  static void checkVerifyCode(Opportunity p, String code, String ip) {
    Datetime hourAgo = Datetime.now().addHours(-1);
    Integer bad = [SELECT COUNT() FROM Donor_Link_Use__c WHERE Pledge__c = :p.Id AND Result__c = 'Bad_Verify' AND Used_At__c >= :hourAgo];
    if (bad >= 5)
      throw err(429, 'LOCKED');
    if (String.isBlank(code))
      throw err(401, 'VERIFY_REQUIRED');
    if (String.isBlank(p.Donor_Phone__c) || code != p.Donor_Phone__c.right(4)) {
      DonorLinkLog.write(p.Id, 'view', p.Link_Version__c == null ? 1 : p.Link_Version__c.intValue(), 'Bad_Verify', ip);
      throw err(401, 'VERIFY_FAILED');
    }
  }

  /** Amount per charge within Min/Max with at most 2 decimals, else 400 AMOUNT_RANGE. */
  static Decimal validAmount(Object rawAmount) {
    Cardcom_Setting__mdt s = CardcomService.settings();
    Decimal a;
    try {
      a = Decimal.valueOf(String.valueOf(rawAmount));
    } catch (Exception e) {
      throw err(400, 'AMOUNT_RANGE');
    }
    if (a.scale() > 2 || a < s.Min_Amount__c || a > s.Max_Amount__c)
      throw err(400, 'AMOUNT_RANGE');
    return a.setScale(2);
  }

  static Map<String, Object> amount(String token, String ip, Object rawAmount) {
    Opportunity p = DonorLinkToken.verify(token, BOTH, ip);
    Decimal a = validAmount(rawAmount);
    if (a == p.Charge_Amount__c)
      return new Map<String, Object>{ 'ok' => true, 'amount' => a, 'changed' => false };
    Decimal old = p.Charge_Amount__c;
    update new Opportunity(Id = p.Id, Charge_Amount__c = a); // D16: applies from the next created charge
    insert new Pledge_Change_Log__c(
      Pledge__c = p.Id,
      Change_Type__c = 'Amount',
      Old_Value__c = String.valueOf(old),
      New_Value__c = String.valueOf(a),
      Source__c = 'Donor_Portal',
      Client_Ip__c = ip == null ? null : ip.left(45),
      Link_Version__c = p.Link_Version__c
    );
    return new Map<String, Object>{ 'ok' => true, 'amount' => a, 'changed' => true };
  }

  /**
   * Starts a card replacement. Optional `amount`: a new amount per charge chosen in the same step; it is stored on the request
   * and applied only when the new card is saved (CardChangeService.complete), so a failed card change leaves the amount alone.
   */
  static Map<String, Object> card(String token, String ip, String returnUrlBase, Object rawAmount) {
    Opportunity p = DonorLinkToken.verify(token, BOTH, ip);
    DonationLowProfileResource.assertAllowedReturnUrl(returnUrlBase); // same host allow-list as signup (7.3)
    Decimal newAmount = rawAmount == null || String.isBlank(String.valueOf(rawAmount)) ? null : validAmount(rawAmount);
    if (newAmount == p.Charge_Amount__c)
      newAmount = null; // unchanged
    Integer today = [SELECT COUNT() FROM Card_Change_Request__c WHERE Pledge__c = :p.Id AND CreatedDate = TODAY];
    if (today >= 5)
      throw err(429, 'TOO_MANY');
    String key = 'CARD-' + UUID.randomUUID().toString();
    Map<String, Object> lp = CardcomService.createTokenLowProfile(key, returnUrlBase, 'עדכון כרטיס להוראת תרומה'); // callout first
    insert new Card_Change_Request__c(
      Pledge__c = p.Id,
      LowProfileId__c = (String) lp.get('LowProfileId'),
      Status__c = 'Pending',
      Link_Version__c = p.Link_Version__c,
      Client_Ip__c = ip == null ? null : ip.left(45),
      New_Amount__c = newAmount
    );
    return new Map<String, Object>{
      'lowProfileId' => lp.get('LowProfileId'),
      'url' => lp.get('Url'),
      'expiresAt' => Datetime.now().addMinutes(20).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'')
    };
  }

  static Map<String, Object> cardStatus(String token, String ip, String lpId) {
    Opportunity p = DonorLinkToken.verify(token, BOTH, ip);
    List<Card_Change_Request__c> cc = [
      SELECT Id, Status__c, CreatedDate
      FROM Card_Change_Request__c
      WHERE LowProfileId__c = :lpId AND Pledge__c = :p.Id
      LIMIT 1
    ];
    if (cc.isEmpty())
      throw err(404, 'NOT_FOUND');
    String st = cc[0].Status__c;
    // Webhook may be late: after 10 s pull GetLpResult ourselves (idempotent with the webhook path)
    if (st == 'Pending' && cc[0].CreatedDate < Datetime.now().addSeconds(-10)) {
      Map<String, Object> r = CardcomService.getLpResult(lpId);
      Integer code = CardcomService.code(r);
      if (code == 0 || !(code >= 5117 && code <= 5119))
        st = CardChangeService.complete(lpId, r);
    }
    Id rt = MicroPledges.recordTypeId();
    Opportunity now = [SELECT Last4__c, Charge_Amount__c FROM Opportunity WHERE Id = :p.Id AND RecordTypeId = :rt];
    return new Map<String, Object>{
      'status' => st,
      'last4' => st == 'Completed' ? now.Last4__c : null,
      'amount' => now.Charge_Amount__c
    };
  }

  /**
   * The donor stops the pledge from the donor page (with either link). Same effect as staff "הפסקת חיובים" (B6.8): Stopped,
   * reason Donor_Request; OpportunityTrigger skips the Pending charges and logs it (source Donor_Portal). Staff are emailed.
   * Resuming stays a staff action. Links stop working afterwards (verify requires Active).
   */
  static Map<String, Object> stop(String token, String ip) {
    Opportunity p = DonorLinkToken.verify(token, BOTH, ip);
    OpportunityTriggerHandler.sourceOverride = 'Donor_Portal';
    update new Opportunity(
      Id = p.Id,
      StageName = MicroPledges.STAGE_STOPPED,
      Stop_Reason__c = 'Donor_Request',
      Stop_Reason_Details__c = 'הופסק ע"י התורם בדף האישי',
      Stopped_At__c = Datetime.now(),
      Stopped_By__c = UserInfo.getUserId()
    );
    OpportunityTriggerHandler.sourceOverride = null;
    StaffAlertService.donorStopped(p.Id);
    return new Map<String, Object>{ 'ok' => true, 'status' => MicroPledges.STAGE_STOPPED };
  }
}
