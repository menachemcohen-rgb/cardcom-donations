// E2E 12 — monthly receipt for chosen test donors only. Never runs for other Contacts, so no document reaches a real donor.
// No plus sign anywhere in this file: the anonymous-Apex path through the MCP turns it into a space.
// 1) Put the test Contact Ids here (or the pledges' Donor_Contact__c).
Set<Id> testContacts = new Set<Id>{ '003000000000000AAA' };
// 2) The month to issue (any day in it).
Date period = Date.today().toStartOfMonth().addMonths(-1);
// Plans receipts for these Contacts only; finish() sends only their receipts (MonthlyReceiptQueueable.start(period, contacts)).
Id batchId = Database.executeBatch(new MonthlyReceiptPlanner(period, testContacts), 200);
System.debug(String.join(new List<String>{ 'RECEIPTS batch', String.valueOf(batchId), 'contacts', String.valueOf(testContacts.size()) }, ' '));
// Retry only these later (after fixing a Failed receipt): MonthlyReceiptQueueable.start(period, testContacts);
