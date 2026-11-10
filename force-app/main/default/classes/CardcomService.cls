/**
 * Cardcom API v11 client. CLAUDE.md B5.9 (authoritative, Part C E8). Credentials come from Named Credential merge fields only.
 * D39: two terminals in one Cardcom account, so one Named Credential (Cardcom) and one API user serve both; only the
 * terminal number differs. PRIMARY (Terminal_Number__c) takes every card except Diners; SECONDARY (Secondary_Terminal_Number__c)
 * is the Diners terminal. A token works only on the terminal that created it, so every call names its terminal; a blank
 * terminal means PRIMARY (pledges older than D39).
 */
public without sharing class CardcomService {
  public class CardcomException extends Exception {
  }
  public class CardcomHttpException extends Exception {
    public Integer status;
  }
  @TestVisible
  static Cardcom_Setting__mdt settingsOverride;
  /** The terminal has no number in Cardcom_Setting__mdt. Nothing was sent to Cardcom. */
  public class TerminalConfigException extends Exception {
  }
  public static final String PRIMARY = 'Primary';
  public static final String SECONDARY = 'Secondary';

  /** PRIMARY unless the value is exactly SECONDARY (blank, unknown and legacy values → PRIMARY). */
  public static String terminalKey(String t) {
    return t == SECONDARY ? SECONDARY : PRIMARY;
  }
  public static String otherTerminal(String t) {
    return terminalKey(t) == SECONDARY ? PRIMARY : SECONDARY;
  }
  public static Boolean hasSecondary() {
    return settings().Secondary_Terminal_Number__c != null;
  }
  /** Terminals that have a number: PRIMARY, then SECONDARY when configured. */
  public static List<String> terminals() {
    List<String> out = new List<String>{ PRIMARY };
    if (hasSecondary())
      out.add(SECONDARY);
    return out;
  }
  // One account for both terminals (D39): same Named Credential and API user; the terminal is chosen by TerminalNumber.
  static final String API = 'callout:Cardcom/api/v11/';
  static final String AN = '{!$Credential.Cardcom_EC.ApiName}';
  static final String AP = '{!$Credential.Cardcom_EC.ApiPassword}';

  public static Cardcom_Setting__mdt settings() {
    return settingsOverride != null ? settingsOverride : Cardcom_Setting__mdt.getInstance('Default');
  }
  static Long terminalNumber(String t) {
    Decimal n = terminalKey(t) == SECONDARY ? settings().Secondary_Terminal_Number__c : settings().Terminal_Number__c;
    if (n == null)
      throw new TerminalConfigException('Cardcom terminal not configured: ' + terminalKey(t));
    return n.longValue();
  }
  static Map<String, Object> withTerminal(String t) {
    return new Map<String, Object>{ 'TerminalNumber' => terminalNumber(t), 'ApiName' => AN };
  }
  static Boolean isRecurring(String t) {
    return (terminalKey(t) == SECONDARY ? settings().Secondary_Is_Recurring_Terminal__c : settings().Is_Recurring_Terminal__c) == true;
  }

  /** POST; returns parsed body. HTTP 401/400 → CardcomHttpException (Config). HTTP 5xx → CardcomHttpException (Retryable). */
  public static Map<String, Object> post(String path, Map<String, Object> body) {
    return post(PRIMARY, path, body);
  }
  public static Map<String, Object> post(String terminal, String path, Map<String, Object> body) {
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
    return createTokenLowProfile(PRIMARY, returnValue, returnUrlBase, productName);
  }
  public static Map<String, Object> createTokenLowProfile(String terminal, String returnValue, String returnUrlBase, String productName) {
    Map<String, Object> b = withTerminal(terminal);
    b.put('Operation', 'CreateTokenOnly');
    b.put('ReturnValue', returnValue);
    b.put('Amount', 1);
    b.put('SuccessRedirectUrl', returnUrlBase + '?s=ok');
    b.put('FailedRedirectUrl', returnUrlBase + '?s=fail');
    b.put('CancelRedirectUrl', returnUrlBase + '?s=fail');
    b.put('WebHookUrl', webhookUrl(terminal));
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
    Map<String, Object> r = post(terminal, 'LowProfile/Create', b);
    if (code(r) != 0 || String.isBlank((String) r.get('Url')))
      throw new CardcomException('LP_CREATE:' + code(r) + ' ' + r.get('Description'));
    return r; // LowProfileId, Url
  }

  /** The secondary terminal's webhook carries ?terminal=Secondary: a hint for GetLpResult, never trusted (CardcomLpResultJob). */
  @TestVisible
  static String webhookUrl(String terminal) {
    String u = settings().Webhook_Url__c;
    if (terminalKey(terminal) != SECONDARY || String.isBlank(u))
      return u;
    return u + (u.contains('?') ? '&' : '?') + 'terminal=' + SECONDARY;
  }

  // ---- B5.3 ----
  public static Map<String, Object> getLpResult(String lowProfileId) {
    return getLpResult(PRIMARY, lowProfileId);
  }
  public static Map<String, Object> getLpResult(String terminal, String lowProfileId) {
    Map<String, Object> b = withTerminal(terminal);
    b.put('LowProfileId', lowProfileId);
    return post(terminal, 'LowProfile/GetLpResult', b);
  }

  /** A GetLpResult that settles the question for its terminal: a token, or the donor still on the page (5117–5119). */
  public static Boolean isLpKnown(Map<String, Object> r) {
    Integer c = code(r);
    return (c == 0 && cardFrom(r) != null) || (c >= 5117 && c <= 5119);
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
    return chargeToken(PRIMARY, token, expMMYY, amount, attemptKey);
  }
  public static Map<String, Object> chargeToken(String terminal, String token, String expMMYY, Decimal amount, String attemptKey) {
    Map<String, Object> b = withTerminal(terminal);
    b.put('Amount', amount.setScale(2));
    b.put('Token', token);
    b.put('CardExpirationMMYY', expMMYY);
    b.put('ExternalUniqTranId', attemptKey);
    b.put('ExternalUniqUniqTranIdResponse', true);
    b.put('ISOCoinId', 1);
    b.put('NumOfPayments', 1);
    Map<String, Object> adv = new Map<String, Object>{ 'SendNote' => false };
    if (isRecurring(terminal))
      adv.put('IsAutoRecurringPayment', true);
    b.put('Advanced', adv);
    return post(terminal, 'Transactions/Transaction', b);
  }

  // ---- B5.5 ----
  /** @return TranzactionInfo map if a SUCCESSFUL transaction exists for the key, else null. */
  public static Map<String, Object> findSuccessByExternalId(String attemptKey) {
    return findSuccessByExternalId(PRIMARY, attemptKey);
  }
  public static Map<String, Object> findSuccessByExternalId(String terminal, String attemptKey) {
    Map<String, Object> b = withTerminal(terminal);
    b.put('ExternalUniqTranId', attemptKey);
    Map<String, Object> r = post(terminal, 'Transactions/GetTransactionByExternalUniqTran', b);
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
    return listTransactions(PRIMARY, d, page, pageSize);
  }
  public static List<TxnSummary> listTransactions(String terminal, Date d, Integer page, Integer pageSize) {
    String dd = Datetime.newInstance(d, Time.newInstance(12, 0, 0, 0)).format('ddMMyyyy');
    Map<String, Object> b = new Map<String, Object>{
      'ApiName' => AN,
      'ApiPassword' => AP,
      'FromDate' => dd,
      'ToDate' => dd,
      'TranStatus' => 'All',
      'Page' => page,
      'Page_size' => pageSize,
      'LimitForTerminal' => terminalNumber(terminal)
    };
    Map<String, Object> r = post(terminal, 'Transactions/ListTransactions', b);
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
  /** Documents are issued by the Cardcom account, which owns both terminals (D39), so one receipt covers charges on either. */
  public static Map<String, Object> createDocument(Map<String, Object> body) {
    body.put('ApiName', AN);
    body.put('ApiPassword', AP);
    return post(PRIMARY, 'Documents/CreateDocument', body);
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
