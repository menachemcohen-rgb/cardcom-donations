// Read-only check that the configured Cardcom terminal and the Cardcom_EC credentials work.
// 1) LowProfile/Create (CreateTokenOnly) — creates a payment page only, charges nothing.
// 2) LowProfile/GetLpResult on that page — expected 5117-5119 (page not filled yet).
// Writes nothing to Salesforce. Do NOT open and fill the printed URL: a saved card would create a pledge with no donor.
// The running user needs access to the Cardcom_EC principal (permission set Donations_Integration).
//   sf apex run --target-org <alias> --file scripts/apex/check-cardcom-terminal.apex
Cardcom_Setting__mdt s = CardcomService.settings();
System.debug(LoggingLevel.ERROR, String.format('CHECK terminal {0} webhook {1}',
    new List<Object>{ s.Terminal_Number__c, s.Webhook_Url__c }));
String returnBase = 'https://ato770.com/cardcom-return/';
try {
    Map<String, Object> lp = CardcomService.createTokenLowProfile('CHECK-' + UUID.randomUUID().toString(), returnBase, 'בדיקת מסוף');
    String lpId = String.valueOf(lp.get('LowProfileId'));
    System.debug(LoggingLevel.ERROR, String.format('CHECK Create OK lowProfileId {0} url {1}', new List<Object>{ lpId, lp.get('Url') }));
    Map<String, Object> r = CardcomService.getLpResult(lpId);
    Integer code = CardcomService.code(r);
    Boolean ok = code >= 5117 && code <= 5119;
    System.debug(LoggingLevel.ERROR, String.format('CHECK GetLpResult ResponseCode {0} Description {1} -> {2}',
        new List<Object>{ code, r.get('Description'), ok ? 'OK (page waiting for card)' : 'UNEXPECTED' }));
    System.debug(LoggingLevel.ERROR, ok ? 'CHECK RESULT: TERMINAL WORKS' : 'CHECK RESULT: CREATE WORKS, GETLPRESULT UNEXPECTED');
} catch (CardcomService.CardcomHttpException e) {
    System.debug(LoggingLevel.ERROR, String.format('CHECK RESULT: HTTP {0} (401 = wrong ApiName/terminal): {1}', new List<Object>{ e.status, e.getMessage() }));
} catch (Exception e) {
    System.debug(LoggingLevel.ERROR, String.format('CHECK RESULT: {0}: {1}', new List<Object>{ e.getTypeName(), e.getMessage() }));
}
