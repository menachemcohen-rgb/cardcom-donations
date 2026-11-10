// Records in Salesforce a receipt that was issued directly in Cardcom (outside the system), so the regular monthly run
// doesn't issue a second receipt for the same charges. Creates a Monthly_Receipt__c (Issued) for the charges' contact and
// month and links the charges to it. Changes nothing in Cardcom. Fill in the three values, then:
//   sf apex run --target-org <alias> --file scripts/apex/record-external-receipt.apex
String documentNumber = '22509';
List<String> approvalNumbers = new List<String>{ '0260059', '0856849' };   // "אסמכתא" of each line on the receipt
Date periodMonth = Date.newInstance(2026, 11, 1);

List<Charge__c> chs = [SELECT Id, Name, Contact__c, Amount__c, Monthly_Receipt__c FROM Charge__c
                       WHERE Status__c = 'Success' AND Cardcom_Approval_Number__c IN :approvalNumbers];
Set<Id> contacts = new Set<Id>();
for (Charge__c c : chs) contacts.add(c.Contact__c);
if (chs.size() != approvalNumbers.size() || contacts.size() != 1) {
    System.debug(LoggingLevel.ERROR, String.format('RECORD stopped: found {0} charges for {1} approval numbers, {2} contacts',
        new List<Object>{ chs.size(), approvalNumbers.size(), contacts.size() }));
} else {
    Id cid = chs[0].Contact__c;
    String key = String.valueOf(cid) + '-' + Datetime.newInstance(periodMonth, Time.newInstance(12, 0, 0, 0)).format('yyyyMM');
    if ([SELECT COUNT() FROM Monthly_Receipt__c WHERE Receipt_Key__c = :key] > 0) {
        System.debug(LoggingLevel.ERROR, 'RECORD stopped: this contact already has a receipt record for that month: ' + key);
    } else {
        Decimal total = 0;
        for (Charge__c c : chs) total += c.Amount__c;
        Monthly_Receipt__c r = new Monthly_Receipt__c(Contact__c = cid, Period_Month__c = periodMonth, Receipt_Key__c = key,
            Status__c = 'Issued', Total_Amount__c = total, Charge_Count__c = chs.size(), Issued_At__c = Datetime.now(),
            Cardcom_Document_Number__c = documentNumber, Cardcom_Document_Type__c = 'DonationReceipt',
            Error_Message__c = 'Issued directly in Cardcom, outside Salesforce; recorded by hand');
        insert r;
        for (Charge__c c : chs) c.Monthly_Receipt__c = r.Id;
        update chs;
        System.debug(LoggingLevel.ERROR, String.format('RECORD receipt {0} recorded, {1} charges linked, total {2}',
            new List<Object>{ documentNumber, chs.size(), total }));
    }
}
