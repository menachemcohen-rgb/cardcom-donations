/** Cardcom API v11 client. CLAUDE.md B5.9 (authoritative, Part C E8). Credentials come from Named Credential merge fields only. */
public without sharing class CardcomService {
  public class CardcomException extends Exception {
  }
  public class CardcomHttpException extends Exception {
    public Integer status;
  }
  @TestVisible
  static Cardcom_Setting__mdt settingsOverride;
  static final String API = 'callout:Cardcom/api/v11/';
  static final String AN = '{!$Credential.Cardcom_EC.ApiName}';
  static final String AP = '{!$Credential.Cardcom_EC.ApiPassword}';

  public static Cardcom_Setting__mdt settings() {
    return settingsOverride != null ? settingsOverride : Cardcom_Setting__mdt.getInstance('Default');
  }
  static Long terminal() {
    return settings().Terminal_Number__c.longValue();
  }
  static Map<String, Object> withTerminal() {
    return new Map<String, Object>{ 'TerminalNumber' => terminal(), 'ApiName' => AN };
  }

  /** POST; returns parsed body. HTTP 401/400 → CardcomHttpException (Config). HTTP 5xx → CardcomHttpException (Retryable). */
  public static Map<String, Object> post(String path, Map<String, Object> body) {
    HttpRequest req = new HttpRequest();
    req.setEndpoint(API + path);
    req.setMethod('POST');
    req.setHeader('Content-Type', 'application/json; charset=utf-8');
    req.setTimeout(30000);
    req.setBody(JSON.serialize(body, true)); // suppress nulls
    HttpResponse res = new Http().send(req);
    Integer sc = res.getStatusCode();
    if (sc != 200) {
      CardcomHttpException e = new CardcomHttpException('HTTP ' + sc + ' ' + path + ' ' + res.getBody().left(200));
      e.status = sc;
      throw e;
    }
    return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
  }

  public static Integer code(Map<String, Object> r) {
    Object c = r == null ? null : r.get('ResponseCode');
    return c == null ? -1 : Integer.valueOf(String.valueOf(c));
  }

  // ---- B5.1 ----
  public static Map<String, Object> createTokenLowProfile(String returnValue, String returnUrlBase, String productName) {
    Map<String, Object> b = withTerminal();
    b.put('Operation', 'CreateTokenOnly');
    b.put('ReturnValue', returnValue);
    b.put('Amount', 1);
    b.put('SuccessRedirectUrl', returnUrlBase + '?s=ok');
    b.put('FailedRedirectUrl', returnUrlBase + '?s=fail');
    b.put('CancelRedirectUrl', returnUrlBase + '?s=fail');
    b.put('WebHookUrl', settings().Webhook_Url__c);
    b.put('ProductName', productName.left(50));
    b.put('Language', 'he');
    b.put('ISOCoinId', 1);
    b.put(
      'UIDefinition',
      new Map<String, Object>{
        'IsHideCardOwnerName' => false,
        'IsHideCardOwnerEmail' => true,
        'IsHideCardOwnerPhone' => true,
        'IsHideCardOwnerIdentityNumber' => false,
        'IsHideCVV' => false
      }
    );
    Integer jv = settings().Lp_JValidate_Type__c == null ? 2 : settings().Lp_JValidate_Type__c.intValue();
    b.put('AdvancedDefinition', new Map<String, Object>{ 'JValidateType' => jv, 'ThreeDSecureState' => 'Auto' });
    Map<String, Object> r = post('LowProfile/Create', b);
    if (code(r) != 0 || String.isBlank((String) r.get('Url')))
      throw new CardcomException('LP_CREATE:' + code(r) + ' ' + r.get('Description'));
    return r; // LowProfileId, Url
  }

  // ---- B5.3 ----
  public static Map<String, Object> getLpResult(String lowProfileId) {
    Map<String, Object> b = withTerminal();
    b.put('LowProfileId', lowProfileId);
    return post('LowProfile/GetLpResult', b);
  }

  /** Parsed card data from GetLpResult (Last4 may be null for CreateTokenOnly — B5.3). */
  public class CardData {
    public String token, expMMYY, last4;
    public Date tokenExpiry;
  }
  public static CardData cardFrom(Map<String, Object> lp) {
    Map<String, Object> ti = (Map<String, Object>) lp.get('TokenInfo');
    if (ti == null || String.isBlank((String) ti.get('Token')))
      return null;
    CardData d = new CardData();
    d.token = (String) ti.get('Token');
    Integer mm = Integer.valueOf(String.valueOf(ti.get('CardMonth')));
    String yy = String.valueOf(ti.get('CardYear')).right(2);
    d.expMMYY = String.valueOf(mm).leftPad(2, '0') + yy;
    String ex = (String) ti.get('TokenExDate');
    if (String.isNotBlank(ex) && ex.length() == 8)
      d.tokenExpiry = Date.newInstance(Integer.valueOf(ex.left(4)), Integer.valueOf(ex.mid(4, 2)), Integer.valueOf(ex.right(2)));
    Map<String, Object> tr = (Map<String, Object>) lp.get('TranzactionInfo'); // normally null for CreateTokenOnly
    if (tr != null && tr.get('Last4CardDigitsString') != null)
      d.last4 = String.valueOf(tr.get('Last4CardDigitsString'));
    return d;
  }

  // ---- B5.4 ----
  public static Map<String, Object> chargeToken(String token, String expMMYY, Decimal amount, String attemptKey) {
    Map<String, Object> b = withTerminal();
    b.put('Amount', amount.setScale(2));
    b.put('Token', token);
    b.put('CardExpirationMMYY', expMMYY);
    b.put('ExternalUniqTranId', attemptKey);
    b.put('ExternalUniqUniqTranIdResponse', true);
    b.put('ISOCoinId', 1);
    b.put('NumOfPayments', 1);
    Map<String, Object> adv = new Map<String, Object>{ 'SendNote' => false };
    if (settings().Is_Recurring_Terminal__c == true)
      adv.put('IsAutoRecurringPayment', true);
    b.put('Advanced', adv);
    return post('Transactions/Transaction', b);
  }

  // ---- B5.5 ----
  /** @return TranzactionInfo map if a SUCCESSFUL transaction exists for the key, else null. */
  public static Map<String, Object> findSuccessByExternalId(String attemptKey) {
    Map<String, Object> b = withTerminal();
    b.put('ExternalUniqTranId', attemptKey);
    Map<String, Object> r = post('Transactions/GetTransactionByExternalUniqTran', b);
    Object tid = r.get('TranzactionId');
    return (code(r) == 0 && tid != null && Long.valueOf(String.valueOf(tid)) > 0) ? r : null;
  }

  // ---- B5.6 ----
  public class TxnSummary {
    public String tranzactionId;
    public Decimal amount;
    public Boolean isSuccess, isRefundOrCancel;
    public Datetime created;
  }
  /** One page. Caller loops while result.size() == pageSize. */
  public static List<TxnSummary> listTransactions(Date d, Integer page, Integer pageSize) {
    String dd = Datetime.newInstance(d, Time.newInstance(12, 0, 0, 0)).format('ddMMyyyy');
    Map<String, Object> b = new Map<String, Object>{
      'ApiName' => AN,
      'ApiPassword' => AP,
      'FromDate' => dd,
      'ToDate' => dd,
      'TranStatus' => 'All',
      'Page' => page,
      'Page_size' => pageSize,
      'LimitForTerminal' => terminal()
    };
    Map<String, Object> r = post('Transactions/ListTransactions', b);
    if (code(r) != 0)
      throw new CardcomException('LIST:' + code(r) + ' ' + r.get('Description'));
    List<TxnSummary> out = new List<TxnSummary>();
    List<Object> rows = (List<Object>) r.get('Tranzactions');
    if (rows == null)
      return out;
    for (Object o : rows) {
      Map<String, Object> t = (Map<String, Object>) o;
      TxnSummary s = new TxnSummary();
      s.tranzactionId = String.valueOf(t.get('TranzactionId'));
      s.amount = t.get('Amount') == null ? null : Decimal.valueOf(String.valueOf(t.get('Amount')));
      s.isSuccess = code(t) == 0;
      String dt = String.valueOf(t.get('DealType'));
      s.isRefundOrCancel = t.get('IsRefund') == true || dt == 'Cancel' || dt == 'Refund';
      out.add(s);
    }
    return out;
  }

  // ---- B5.7 ----
  public static Map<String, Object> createDocument(Map<String, Object> body) {
    body.put('ApiName', AN);
    body.put('ApiPassword', AP);
    return post('Documents/CreateDocument', body);
  }

  /** Remove secrets/token before persisting. */
  public static String redact(Map<String, Object> m) {
    if (m == null)
      return null;
    Map<String, Object> c = m.clone();
    for (String k : new List<String>{ 'Token', 'ApiPassword', 'ApiName', 'CardOwnerIdentityNumber' })
      c.remove(k);
    if (c.get('TokenInfo') instanceof Map<String, Object>) {
      Map<String, Object> ti = ((Map<String, Object>) c.get('TokenInfo')).clone();
      ti.remove('Token');
      ti.remove('CardOwnerIdentityNumber');
      c.put('TokenInfo', ti);
    }
    return JSON.serialize(c).left(32768);
  }
}
