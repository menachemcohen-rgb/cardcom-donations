// Read-only check of every configured Cardcom terminal (D39: primary + secondary/Diners) with the Cardcom_EC credentials.
// For each terminal: 1) LowProfile/Create (CreateTokenOnly) — a payment page only, charges nothing;
//                    2) LowProfile/GetLpResult on that page — expected 5117-5119 (page not filled yet).
// Writes nothing to Salesforce. Do NOT open and fill the printed URLs: a saved card would create a pledge with no donor.
// The running user needs access to the Cardcom_EC principal (permission set Donations_Integration).
//   sf apex run --target-org <alias> --file scripts/apex/check-cardcom-terminal.apex
Cardcom_Setting__mdt s = CardcomService.settings();
System.debug(LoggingLevel.ERROR, String.format('CHECK primary {0} secondary {1} webhook {2}',
    new List<Object>{ s.Terminal_Number__c, s.Secondary_Terminal_Number__c, s.Webhook_Url__c }));
if (s.Secondary_Terminal_Number__c == null) {
    System.debug(LoggingLevel.ERROR, 'CHECK secondary terminal number is empty: only the primary is checked');
}
String returnBase = 'https://ato770.com/cardcom-return/';
for (String t : CardcomService.terminals()) {
    try {
        Map<String, Object> lp = CardcomService.createTokenLowProfile(t, 'CHECK-' + UUID.randomUUID().toString(), returnBase, 'בדיקת מסוף');
        String lpId = String.valueOf(lp.get('LowProfileId'));
        System.debug(LoggingLevel.ERROR, String.format('CHECK {0} Create OK lowProfileId {1} url {2}', new List<Object>{ t, lpId, lp.get('Url') }));
        Map<String, Object> r = CardcomService.getLpResult(t, lpId);
        Integer code = CardcomService.code(r);
        Boolean ok = code >= 5117 && code <= 5119;
        System.debug(LoggingLevel.ERROR, String.format('CHECK {0} GetLpResult ResponseCode {1} Description {2}',
            new List<Object>{ t, code, r.get('Description') }));
        System.debug(LoggingLevel.ERROR, String.format('CHECK RESULT {0}: {1}', new List<Object>{ t,
            ok ? 'TERMINAL WORKS' : 'CREATE WORKS, GETLPRESULT UNEXPECTED' }));
    } catch (CardcomService.CardcomHttpException e) {
        System.debug(LoggingLevel.ERROR, String.format('CHECK RESULT {0}: HTTP {1} (401 = wrong ApiName/terminal): {2}', new List<Object>{ t, e.status, e.getMessage() }));
    } catch (Exception e) {
        System.debug(LoggingLevel.ERROR, String.format('CHECK RESULT {0}: {1}: {2}', new List<Object>{ t, e.getTypeName(), e.getMessage() }));
    }
}
