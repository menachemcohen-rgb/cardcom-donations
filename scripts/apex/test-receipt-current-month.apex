// TEST: issues a REAL monthly receipt through Cardcom (Documents/CreateDocument) for ONE contact for the CURRENT month,
// with one payment line per successful charge so far (CreditCardLines). Used to check receipt go-live check 6 before the 2nd.
// The receipt is a real document of the organization (real number, e-mailed to the donor) and can't be deleted.
// Charges of this month made AFTER this receipt are not picked up by the regular run on the 2nd for this contact
// (it already has this month's receipt); issue them by hand afterwards if needed.
// The running user needs the Cardcom credential (permission set Donations_Integration, temporarily).
// Set the contact's e-mail below, then:  sf apex run --target-org <alias> --file scripts/apex/test-receipt-current-month.apex
String email = 'PUT_THE_CONTACT_EMAIL_HERE';
List<Contact> cs = [SELECT Id, Name FROM Contact WHERE Email = :email LIMIT 2];
if (cs.size() != 1) {
    System.debug(LoggingLevel.ERROR, String.format('RECEIPT expected 1 contact with {0}, found {1}', new List<Object>{ email, cs.size() }));
} else {
    Date period = Date.today().toStartOfMonth();
    Integer n = [SELECT COUNT() FROM Charge__c WHERE Contact__c = :cs[0].Id AND Status__c = 'Success' AND Monthly_Receipt__c = null
                 AND Needs_Reconciliation__c = false AND Cardcom_Deal_Number__c != null AND Run_Date__c >= :period];
    System.debug(LoggingLevel.ERROR, String.format('RECEIPT contact {0}, charges to include {1}', new List<Object>{ cs[0].Name, n }));
    if (n > 0) {
        Id job = Database.executeBatch(new MonthlyReceiptPlanner(period, new Set<Id>{ cs[0].Id }), 200);
        System.debug(LoggingLevel.ERROR, String.format('RECEIPT planner batch {0}: the receipt is sent to Cardcom right after it', new List<Object>{ job }));
    }
}
