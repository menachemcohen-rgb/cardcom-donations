// Read-only diagnostic: calls Cardcom LowProfile/GetLpResult for the newest pending pledge and prints the outcome.
// Changes nothing in Salesforce and charges nothing (GetLpResult only reads). Never prints the token.
// The running user needs access to the Cardcom_EC principal (permission set Donations_Integration).
//   sf apex run --target-org <alias> --file scripts/apex/diag-lp-result.apex
List<Opportunity> ps = [SELECT Pledge_Number__c, LowProfileId__c FROM Opportunity
                        WHERE Type = 'Daily Donation Pledge' AND StageName = 'Pending_Verification'
                        ORDER BY CreatedDate DESC LIMIT 1];
if (ps.isEmpty()) {
    System.debug(LoggingLevel.ERROR, 'DIAG no pending pledge');
} else {
    String lp = ps[0].LowProfileId__c;
    System.debug(LoggingLevel.ERROR, String.format('DIAG pledge {0} lowProfileId {1}', new List<Object>{ ps[0].Pledge_Number__c, lp }));
    try {
        Map<String, Object> r = CardcomService.getLpResult(lp);
        CardcomService.CardData d = CardcomService.cardFrom(r);
        System.debug(LoggingLevel.ERROR, String.format('DIAG ResponseCode {0} Description {1} ReturnValue {2} tokenReturned {3}',
            new List<Object>{ CardcomService.code(r), r.get('Description'), r.get('ReturnValue'), d != null }));
    } catch (CardcomService.CardcomHttpException e) {
        System.debug(LoggingLevel.ERROR, String.format('DIAG HTTP {0}: {1}', new List<Object>{ e.status, e.getMessage() }));
    } catch (Exception e) {
        System.debug(LoggingLevel.ERROR, String.format('DIAG {0}: {1}', new List<Object>{ e.getTypeName(), e.getMessage() }));
    }
}
