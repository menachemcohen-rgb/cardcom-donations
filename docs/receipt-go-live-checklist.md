# Monthly receipt — go-live checklist (B6.11)

Run these checks with Cardcom (test terminal first, then the client's production terminal) **before** the first real
`MonthlyReceiptScheduler` run. Nothing here is automated: the Apex tests only use `CardcomMock`.
Decisions (D28, 2026-11-02):
- **Document type** `DonationReceipt` (`Cardcom_Setting__mdt.Receipt_Document_Type__c`, the default).
- **Israeli ID optional**: sent as `TaxId` when the Contact or a pledge has one, omitted otherwise. The form field stays optional.
- **Payment block** `Cash` = the monthly total, `Receipt_Link_Deal_Numbers__c = false` — the only variant Cardcom accepted on the test
  terminal. Linking the card transactions (`DealNumbers`) stays available behind the flag; turn it on only if Cardcom confirms it for the
  production terminal and one supervised receipt passes.
- **Payment mode** (N94, D33): `Cardcom_Setting__mdt.Receipt_Payment_Mode__c` = `CreditCardLines` (the default: one credit card line
  per charge in `CustomFields`, so the receipt shows card payments) / `Cash` / `DealNumbers`. **Check 6 must pass before the first
  receipt run** (the 2nd of the month); until it does, a failed credit card receipt stays `Failed` and is not sent as cash.
- **Day of issue** (D33): the 2nd of every month (`Charge_Settings__c.Receipt_Day_Of_Month__c = 2`), or the next working day.
- **Section 46 setup** (module, approval number, whether a combined monthly receipt qualifies) is between the client and Cardcom; check 1
  only records that it was done.

| # | Check | How | Done |
|---|---|---|---|
| 1 | The documents module is active and the section 46 donation receipt is configured (the organisation's section 46 approval number in the document settings). | Cardcom admin → document settings. Ask Cardcom support if the module is missing. The client arranges this with Cardcom (D28); we only need confirmation that it is active. | ☐ |
| 2 | A receipt with one product line and top-level `Cash` = the total returns `ResponseCode = 0` (on terminal 1001 this passed on 2.11.2026). `DealNumbers` stays off (D28); test it only if Cardcom later confirms it for the production terminal (U4, U8). | Sandbox: create a Pending `Monthly_Receipt__c` for a test Contact, run `MonthlyReceiptQueueable.start(<period>)`; check `Status__c = Issued`, `Cardcom_Document_Number__c`, and the PDF at `Cardcom_Document_Url__c`. | ☐ |
| 3 | Sending again with the same `ExternalId` returns the same `DocumentNumber` (KB510; seen on 1001). | Use the Retry_Receipt action ("שליחה חוזרת") on the receipt from check 2; the document number must not change and no second receipt must reach the donor. | ☐ |
| 4 | The wording and design of Cardcom's receipt email (set in the terminal settings), and the day and time of issue. | Look at the email that reached the test inbox in check 2. Q16: confirm with the client; set `Charge_Settings__c.Receipt_Day_Of_Month__c` / `Receipt_Time__c` and press "החלת זמני חיוב". | ☐ |
| 5 | The charges themselves (Transaction without `Document`, `SendNote=false`) create **no** document, email or SMS. | After TC11 in the sandbox: Cardcom admin → documents list shows nothing for those transactions; the donor's test inbox/phone got nothing from Cardcom. TC40. | ☐ |
| 6 | `CreditCardLines` (N94): a receipt whose `CustomFields` lines are real sandbox charges returns `ResponseCode = 0` and the PDF lists credit card payments. On 2.11 it failed with 9996 using transactions that were not the document company's. | Pick a real sandbox charge (e.g. deal 268898721, 5 ₪) whose donor has a test address. Use a Contact/month with **no receipt yet** (a known ExternalId returns the old document) and press "הפקת קבלה חודשית" on that Contact. Check `Raw_Request__c` (`CustomFields`, no `Cash`), `Status__c`, the PDF. 9996/6311 → `Failed` with the code, nothing sent as cash; then fix with Cardcom (or set the mode to `Cash` as a stopgap) before the 2nd. | ☐ |

After go-live: watch the list view "קבלות שנכשלו" and the daily staff email "קבלות חודשיות שנכשלו" for the first two months.
Charges confirmed as successful after their month's receipt was issued are not added to it (N78): find them with a report on
`Charge__c` where `Status__c = Success`, `Monthly_Receipt__c` is blank and `Run_Date__c` is before this month.
