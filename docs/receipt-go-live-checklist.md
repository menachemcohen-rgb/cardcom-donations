# Monthly receipt — go-live checklist (B6.11)

Run these checks with Cardcom (test terminal first, then the client's production terminal) **before** the first real
`MonthlyReceiptScheduler` run. Nothing here is automated: the Apex tests only use `CardcomMock`.
Blocked on answers to Q14 (accountant) and Q15 (Cardcom).

| # | Check | How | Done |
|---|---|---|---|
| 1 | The documents module is active and the section 46 donation receipt is configured (the organisation's section 46 approval number in the document settings). | Cardcom admin → document settings. Ask Cardcom support if the module is missing. Confirm with the accountant (Q14) whether `DonationReceipt` or `Receipt` is the right type → `Cardcom_Setting__mdt.Receipt_Document_Type__c`, and whether the Israeli ID is mandatory. | ☐ |
| 2 | A receipt with one product line and top-level `Cash` = the total returns `ResponseCode = 0` (on terminal 1001 this passed on 2.11.2026). `DealNumbers` only on the production terminal and only if `Receipt_Link_Deal_Numbers__c` will be turned on (U4, U8). | Sandbox: create a Pending `Monthly_Receipt__c` for a test Contact, run `MonthlyReceiptQueueable.start(<period>)`; check `Status__c = Issued`, `Cardcom_Document_Number__c`, and the PDF at `Cardcom_Document_Url__c`. | ☐ |
| 3 | Sending again with the same `ExternalId` returns the same `DocumentNumber` (KB510; seen on 1001). | Use the Retry_Receipt action ("שליחה חוזרת") on the receipt from check 2; the document number must not change and no second receipt must reach the donor. | ☐ |
| 4 | The wording and design of Cardcom's receipt email (set in the terminal settings), and the day and time of issue. | Look at the email that reached the test inbox in check 2. Q16: confirm with the client; set `Charge_Settings__c.Receipt_Day_Of_Month__c` / `Receipt_Time__c` and press "החלת זמני חיוב". | ☐ |
| 5 | The charges themselves (Transaction without `Document`, `SendNote=false`) create **no** document, email or SMS. | After TC11 in the sandbox: Cardcom admin → documents list shows nothing for those transactions; the donor's test inbox/phone got nothing from Cardcom. TC40. | ☐ |

After go-live: watch the list view "קבלות שנכשלו" and the daily staff email "קבלות חודשיות שנכשלו" for the first two months.
Charges confirmed as successful after their month's receipt was issued are not added to it (N78): find them with a report on
`Charge__c` where `Status__c = Success`, `Monthly_Receipt__c` is blank and `Run_Date__c` is before this month.
