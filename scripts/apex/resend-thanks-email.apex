// Re-sends the donor thank-you e-mail for the successful charges of the last 2 days (testing / a donor who lost the mail).
// Clears Donor_Email_Status__c on those charges and calls DonorChargeEmailService.send, which groups them per pledge.
// Real e-mail to the donor's address. Run as an admin:
//   sf apex run --target-org <alias> --file scripts/apex/resend-thanks-email.apex
List<Charge__c> cs = [SELECT Id, Name, Donor_Email_Status__c FROM Charge__c
                      WHERE Status__c = 'Success' AND Executed_At__c = LAST_N_DAYS:2 ORDER BY Executed_At__c];
if (cs.isEmpty()) {
    System.debug(LoggingLevel.ERROR, 'RESEND no successful charge in the last 2 days');
} else {
    for (Charge__c c : cs) c.Donor_Email_Status__c = null;
    update cs;
    DonorChargeEmailService.send(new List<Id>(new Map<Id, Charge__c>(cs).keySet()));
    for (Charge__c c : [SELECT Name, Donor_Email_Status__c, Donor_Email_Sent_At__c FROM Charge__c WHERE Id IN :cs])
        System.debug(LoggingLevel.ERROR, String.format('RESEND {0} {1} {2}', new List<Object>{ c.Name, c.Donor_Email_Status__c, c.Donor_Email_Sent_At__c }));
}
