// Read-only check of the Cardcom terminals (D39, PR #57): both terminals are in one Cardcom account, one Named Credential.
//   Primary   = Named Credential Cardcom / External Credential Cardcom_EC / Terminal_Number__c
//   Secondary = Named Credential Cardcom / External Credential Cardcom_EC / Secondary_Terminal_Number__c (Diners)
// For each terminal: LowProfile/Create (CreateTokenOnly — a payment page, charges nothing), then GetLpResult on it
// (expected 5117-5119: page not filled yet). Builds the requests itself, so it works whatever CardcomService version is deployed.
// Writes nothing to Salesforce. Do NOT open and fill the printed URLs: a saved card would create a pledge with no donor.
// The running user needs principal access to Cardcom_EC (permission set Donations_Integration).
//   sf apex run --target-org <alias> --file scripts/apex/check-cardcom-terminal.apex
Cardcom_Setting__mdt s = Cardcom_Setting__mdt.getInstance('Default');
Object secondary = null;
try { secondary = s.get('Secondary_Terminal_Number__c'); } catch (Exception e) { System.debug(LoggingLevel.ERROR, 'CHECK no Secondary_Terminal_Number__c field (D39 not deployed)'); }
System.debug(LoggingLevel.ERROR, String.format('CHECK primary {0} secondary {1} webhook {2}',
    new List<Object>{ s.Terminal_Number__c, secondary, s.Webhook_Url__c }));

List<List<Object>> terminals = new List<List<Object>>{ new List<Object>{ 'Primary', 'Cardcom', s.Terminal_Number__c } };
if (secondary != null) terminals.add(new List<Object>{ 'Secondary', 'Cardcom', secondary });
else System.debug(LoggingLevel.ERROR, 'CHECK secondary terminal number is empty: only the primary is checked');

String returnBase = 'https://ato770.com/cardcom-return/';
for (List<Object> t : terminals) {
    String name = (String) t[0], nc = (String) t[1];
    Long terminal = ((Decimal) t[2]).longValue();
    String apiName = '{!$Credential.' + nc + '_EC.ApiName}';
    try {
        Map<String, Object> body = new Map<String, Object>{
            'TerminalNumber' => terminal, 'ApiName' => apiName, 'Operation' => 'CreateTokenOnly',
            'ReturnValue' => 'CHECK-' + UUID.randomUUID().toString(), 'Amount' => 1,
            'SuccessRedirectUrl' => returnBase + '?s=ok', 'FailedRedirectUrl' => returnBase + '?s=fail',
            'CancelRedirectUrl' => returnBase + '?s=fail', 'WebHookUrl' => s.Webhook_Url__c,
            'ProductName' => 'בדיקת מסוף', 'Language' => 'he', 'ISOCoinId' => 1,
            'AdvancedDefinition' => new Map<String, Object>{ 'JValidateType' => 2, 'ThreeDSecureState' => 'Auto' } };
        Map<String, Object> lp = post(nc, 'LowProfile/Create', body);
        Integer createCode = code(lp);
        String lpId = String.valueOf(lp.get('LowProfileId'));
        System.debug(LoggingLevel.ERROR, String.format('CHECK {0} ({1}, terminal {2}) Create ResponseCode {3} Description {4} lowProfileId {5}',
            new List<Object>{ name, nc, terminal, createCode, lp.get('Description'), lpId }));
        if (createCode != 0) {
            System.debug(LoggingLevel.ERROR, 'CHECK RESULT ' + name + ': CREATE FAILED');
            continue;
        }
        Map<String, Object> r = post(nc, 'LowProfile/GetLpResult',
            new Map<String, Object>{ 'TerminalNumber' => terminal, 'ApiName' => apiName, 'LowProfileId' => lpId });
        Integer c = code(r);
        System.debug(LoggingLevel.ERROR, String.format('CHECK {0} GetLpResult ResponseCode {1} Description {2}', new List<Object>{ name, c, r.get('Description') }));
        System.debug(LoggingLevel.ERROR, 'CHECK RESULT ' + name + ': ' + (c >= 5117 && c <= 5119 ? 'TERMINAL WORKS' : 'CREATE WORKS, GETLPRESULT UNEXPECTED'));
    } catch (Exception e) {
        System.debug(LoggingLevel.ERROR, String.format('CHECK RESULT {0} ({1}): {2}: {3}', new List<Object>{ name, nc, e.getTypeName(), e.getMessage() }));
    }
}

Map<String, Object> post(String nc, String path, Map<String, Object> body) {
    HttpRequest req = new HttpRequest();
    req.setEndpoint('callout:' + nc + '/api/v11/' + path);
    req.setMethod('POST');
    req.setHeader('Content-Type', 'application/json; charset=utf-8');
    req.setTimeout(30000);
    req.setBody(JSON.serialize(body, true));
    HttpResponse res = new Http().send(req);
    if (res.getStatusCode() != 200) throw new CalloutException('HTTP ' + res.getStatusCode() + ' (401 = wrong ApiName/terminal): ' + res.getBody().left(200));
    return (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
}
Integer code(Map<String, Object> r) {
    Object c = r == null ? null : r.get('ResponseCode');
    return c == null ? -1 : Integer.valueOf(String.valueOf(c));
}
