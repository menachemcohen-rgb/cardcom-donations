// E2E 13 — re-run the nightly reconciliation for one day (ReconciliationJob(Date) is private; use enqueue).
// No plus sign anywhere in this file: the anonymous-Apex path through the MCP turns it into a space.
Date day = Date.today(); // or Date.newInstance(2026, 11, 3)
Id jobId = ReconciliationJob.enqueue(day);
System.debug(String.join(new List<String>{ 'RECON enqueued', String.valueOf(jobId), 'for', String.valueOf(day) }, ' '));
// Then: Reconciliation_Issue__c with Business_Date__c = day; if Cardcom's list was unusable, staff get
// "התאמה לילית: רשימת העסקאות מ-Cardcom לא זמינה" and each charge is looked up by its key (N86).
