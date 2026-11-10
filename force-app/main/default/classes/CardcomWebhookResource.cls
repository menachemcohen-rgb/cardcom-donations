/**
 * Cardcom webhook on Site "cardcom" (guest user) — Part A 7.5, B5.2, B6.3. A trigger only: logs the call, publishes
 * Cardcom_Lp_Event__e with the LowProfileId and returns 200. Nothing else from the body is trusted; GetLpResult decides.
 */
@RestResource(urlMapping='/cardcom/webhook')
global without sharing class CardcomWebhookResource {
  @HttpPost
  global static void receive() {
    RestRequest req = RestContext.request;
    String body = req.requestBody == null ? '' : req.requestBody.toString();
    String lpId = extractLowProfileId(req, body);
    Cardcom_Webhook_Log__c log = new Cardcom_Webhook_Log__c(
      LowProfileId__c = lpId == null ? null : lpId.left(64),
      Raw_Body__c = body.left(32768),
      Received_At__c = Datetime.now(),
      Content_Type__c = req.headers == null || req.headers.get('Content-Type') == null ? null : req.headers.get('Content-Type').left(100),
      Source_Ip__c = req.remoteAddress == null ? null : req.remoteAddress.left(45)
    );
    insert log;
    // Only an ID is trusted from here; everything else comes from GetLpResult.
    if (String.isNotBlank(lpId) && Pattern.matches('[A-Za-z0-9-]{10,64}', lpId)) {
      // Guest context can't use the Named Credential → publish a Platform Event; its trigger runs as the integration user
      // D39: ?terminal=Secondary on the webhook URL says which terminal to ask first; GetLpResult still decides.
      String t = req.params == null ? null : req.params.get('terminal');
      EventBus.publish(
        new Cardcom_Lp_Event__e(LowProfileId__c = lpId, Terminal__c = t == CardcomService.SECONDARY ? CardcomService.SECONDARY : null)
      );
    }
    RestContext.response.statusCode = 200;
  }

  @TestVisible
  static String extractLowProfileId(RestRequest req, String body) {
    for (String k : new List<String>{ 'LowProfileId', 'lowprofileid', 'LowProfileCode', 'lowprofilecode' }) {
      if (req.params != null && req.params.containsKey(k))
        return req.params.get(k);
    }
    if (body.startsWith('{')) {
      try {
        Map<String, Object> m = (Map<String, Object>) JSON.deserializeUntyped(body);
        Object v = m.containsKey('LowProfileId') ? m.get('LowProfileId') : m.get('LowProfileCode');
        return v == null ? null : String.valueOf(v);
      } catch (Exception e) {
        return null; // malformed JSON: still logged, nothing published
      }
    }
    for (String pair : body.split('&')) {
      // form-encoded
      List<String> kv = pair.split('=', 2);
      if (kv.size() == 2 && (kv[0].equalsIgnoreCase('LowProfileId') || kv[0].equalsIgnoreCase('LowProfileCode'))) {
        return EncodingUtil.urlDecode(kv[1], 'UTF-8');
      }
    }
    return null;
  }
}
