@RestResource(urlMapping='/donations/lowprofile')
global without sharing class DonationLowProfileResource {
  /**
   * Contract: B4. Body {purpose:'signup', returnUrlBase, terminal?}. Response {lowProfileId, url, expiresAt, terminal}.
   * D39: terminal 'Secondary' opens the card page of the Diners terminal; anything else → the primary terminal.
   */
  @HttpPost
  global static void create() {
    RestResponse res = RestContext.response;
    res.addHeader('Content-Type', 'application/json; charset=utf-8');
    Map<String, Object> out;
    try {
      Map<String, Object> b = (Map<String, Object>) JSON.deserializeUntyped(RestContext.request.requestBody.toString());
      String returnUrlBase = (String) b.get('returnUrlBase');
      assertAllowedReturnUrl(returnUrlBase);
      String terminal = CardcomService.terminalKey((String) b.get('terminal'));
      String rv = 'SIGNUP-' + UUID.randomUUID().toString();
      Map<String, Object> r = CardcomService.createTokenLowProfile(terminal, rv, returnUrlBase, 'הוראת תרומה יומית'); // B5.1
      out = new Map<String, Object>{
        'lowProfileId' => r.get('LowProfileId'),
        'url' => r.get('Url'),
        'terminal' => terminal,
        // LP page lifetime is not documented → WP refreshes the iframe after 20 minutes (safe default)
        'expiresAt' => Datetime.now().addMinutes(20).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'')
      };
      res.statusCode = 200;
    } catch (IllegalArgumentException e) {
      res.statusCode = 400;
      out = new Map<String, Object>{ 'error' => 'BAD_RETURN_URL' };
    } catch (CardcomService.TerminalConfigException e) {
      res.statusCode = 400;
      out = new Map<String, Object>{ 'error' => 'TERMINAL_NOT_CONFIGURED' };
    } catch (Exception e) {
      System.debug(LoggingLevel.ERROR, 'LP create ' + e.getMessage());
      res.statusCode = 400;
      out = new Map<String, Object>{ 'error' => 'CARDCOM_ERROR' };
    }
    res.responseBody = Blob.valueOf(JSON.serialize(out));
  }

  /** https + host in Cardcom_Setting__mdt.Allowed_Return_Hosts__c (comma separated). Used also by DonorPortalResource. */
  public static void assertAllowedReturnUrl(String u) {
    if (String.isBlank(u) || !u.startsWith('https://'))
      throw new IllegalArgumentException('return url');
    String host = new Url(u).getHost().toLowerCase();
    Set<String> ok = new Set<String>();
    for (String h : CardcomService.settings().Allowed_Return_Hosts__c.split(','))
      ok.add(h.trim().toLowerCase());
    if (!ok.contains(host))
      throw new IllegalArgumentException('return url');
  }
}
