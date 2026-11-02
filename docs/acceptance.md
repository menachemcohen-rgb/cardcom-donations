# Acceptance tests (B11)

Mapping of the B11 sandbox scenarios to automated Apex tests or manual steps. Prompts 5, 8 and 10 extend this file; Prompt 12 completes
TC01–TC40. "Automated" tests use `CardcomMock` (no real Cardcom call). Manual steps run in the sandbox against Cardcom's public test
terminal (`CLAUDE.md` B5.0א) with the WordPress staging site (Prompt 10).

## Intake — TC01–TC10 (Prompt 3)

| ID | Scenario | Automated | Manual (sandbox + test terminal) |
|---|---|---|---|
| TC01 | New donor signs up | `CardcomLpResultJobTest.submitThenWebhookActivatesExactlyOnce`, `DonationPledgeResourceTest.createsPendingPledgeOpportunity`, `ContactMatcherTest.createsNewDonorWhenNothingMatches` | Fill the form with test card `4580280000000008`, 12/30, CVV 123, ₪3 twice a day. Within a minute: pledge Opportunity `Active`, new Contact with `Donor_Source__c = WP_Micro`, contact role Donor, `Token__c`/`CardExpirationMMYY__c` filled (`Last4__c` stays empty until the first charge, B5.3). Needs Prompt 10. |
| TC02 | Existing donor by email | `ContactMatcherTest.matchesByEmailAndFillsOtherPhone` | Create a Contact with the same email and another mobile, then sign up: no new Contact, `Match_Method__c = Email`, `OtherPhone` = new mobile. |
| TC03 | Existing donor by phone only | `ContactMatcherTest.matchesByPhoneAndFlagsDifferentEmail` | Contact with the same mobile, different email: `Match_Method__c = Phone`, email unchanged, `Needs_Review__c` with "אימייל שונה". |
| TC04 | Conflicting keys | `ContactMatcherTest.conflictingKeysPickEmailAndFlagReview` | Email of Contact A, mobile of Contact B: pledge linked to A, A flagged with both Ids. |
| TC05 | Invalid Israeli ID | `DonationPledgeResourceTest.validationListsBadFields` (server side) | `123456789` in the form: Hebrew field error and no call to Salesforce (WordPress, Prompt 10). |
| TC06 | Missing field after the card is saved | — | WordPress flow (Prompt 10): "נא להשלים..." and a finish button; after completing, success without re-entering the card. |
| TC07 | iframe expires | — | WordPress flow (Prompt 10): wait 21 minutes; the iframe refreshes and the form keeps its values. |
| TC08 | Duplicate webhook | `CardcomLpResultJobTest.repeatedWebhooksCallCardcomOnce`, `CardcomWebhookResourceTest.webhookLogsPublishesAndCreatesVerifiedPledge` | Replay the webhook POST 3 times (Postman): 3 `Cardcom_Webhook_Log__c` rows, one pledge, one GetLpResult call. |
| TC09 | Webhook blocked | `PendingVerificationSweeperTest.rechecksOldPendingPledges`, `PendingVerificationSweeperTest.activatesVerifiedSubmittedPledgesLeftPending` | Deactivate the Site, sign up: the sweeper activates the pledge within 15 minutes (10-minute grace + next run). |
| TC10 | Submit replay | `DonationPledgeResourceTest.replayIsRejected` | Re-send the submit with the same `lowProfileId`: Salesforce returns 400 `LP_ALREADY_USED`; WordPress shows "ההוראה כבר נקלטה" (409 mapping, Prompt 10). |

Also automated for Prompt 3 (no B11 number):
- Webhook before submit, then submit → Active once: `DonationPledgeResourceTest.webhookFirstThenSubmitActivatesOnce`.
- 6 failed checks → `Verification_Failed`: `CardcomLpResultJobTest.sixthFailedCheckMarksVerificationFailed`.
- Donor still on the payment page (5117) → no change: `CardcomLpResultJobTest.stillOnPaymentPageChangesNothing`.
- Non-pledge Opportunities never selected or modified: `CardcomLpResultJobTest.otherOpportunitiesAreNeverSelectedOrModified`,
  `PendingVerificationSweeperTest.ignoresFreshPledgesAndOtherOpportunities`, `PledgeActivationServiceTest.activatesOnlyWhenSubmittedAndVerified`.
- Named Credential merge fields sent unchanged: `CardcomServiceTest.createTokenLowProfileSendsB51BodyWithCredentialPlaceholders`.

## Thank-you email and donor page — TC25–TC30 (Prompts 8 and 10)

| ID | Scenario | Automated | Manual (sandbox + staging WordPress) |
|---|---|---|---|
| — | Thank-you email | `DonorChargeEmailServiceTest` (grouping, no email, limit guard, disabled, missing secret, event trigger) | After TC11/TC12: one email per pledge per run with the amount, the dates (Friday: "עבור 06/11 ו-07/11"), the card phrase, and two links. |
| TC25 | Change amount | `DonorPortalResourceTest.amountChangeAppliesFromTheNextChargeOnly` | Open the amount link → 5 ₪: "הסכום עודכן ל-5.00 ₪…"; `Charge_Amount__c` = 5, change log "Amount" (Donor_Portal); an existing Pending retry stays 3; the next run charges 5. |
| TC26 | Amount out of range | `DonorPortalResourceTest.amountOutOfRangeOrWrongLinkIsRefused` | 0.5 / 100: range message, nothing changes. |
| TC27 | Replace card | `DonorPortalResourceTest.cardReplacementStartsALowProfile`, `DonorPortalResourceTest.cardStatusWaitsThenPullsTheResult`, `CardChangeServiceTest.successfulReplacementKeepsHistory` | Card link → "החלפת כרטיס" → second test card: success message (with 4 digits when Cardcom returns them, else "בכרטיס החדש"); `Pledge_Card_History__c` holds the old token; the next charge uses the new token. |
| TC28 | Replacement fails | `CardChangeServiceTest.failedReplacementKeepsTheOldCard` | Cancel inside the iframe: "פרטי הכרטיס לא נקלטו והכרטיס הקודם נשאר בתוקף…"; CCR Failed (or Expired after 30 min); token unchanged. |
| TC29 | Revoke links | `DonorLinkTokenTest.wrongActionVersionSignatureAndStatusAreInvalid` | "ביטול קישורי תורם" on the pledge → the old link shows "הקישור אינו תקף…"; the link in the next thank-you email works. |
| TC30 | Months-old link | `DonorLinkTokenTest.issueAndVerifyWithoutExpiry` (no expiry claim), `DonorLinkTokenTest.previousSecretStillWorksAfterRotation` | Issue a token with the current version (Anonymous Apex `DonorLinkToken.issue(pledgeId, 'amount', 1)`) and open it: it works (D15). |

## WordPress — form and donor page (Prompt 10)

Staging site with the plugin installed (`docs/wp-install.md`), sandbox Salesforce, Cardcom test terminal. Automated: PHPUnit
(`ValidatorTest`, `RateLimiterTest`) and `node --test wordpress/org-donations/tests/js/donation-form.test.mjs`.

| ID | Scenario | Manual steps | Expected |
|---|---|---|---|
| TC01 | New donor, end to end | Open the form, fill every field, ₪3, twice a day, accept the terms, enter card `4580280000000008`, 12/30, CVV 123, any ID, click "שמור כרטיס". | The form submits by itself and shows "תודה! הוראת התרומה התקבלה…". In Salesforce the pledge becomes Active within a minute (Prompt 3). DevTools: no browser request to Salesforce. |
| TC05 | Invalid Israeli ID | Type `123456789` in the ID field and click "סיום". | "מספר תעודת הזהות אינו תקין" under the field; no `org_donation_submit` request (browser check) and the server check rejects it too (`ValidatorTest`). |
| TC06 | Missing field after the card is saved | Leave the email empty, enter and save the card. | "נא להשלים את פרטי הטופס וללחוץ 'סיום'" and a "סיום" button. Fill the email, click "סיום": success without entering the card again. |
| TC07 | iframe expiry | Open the form, fill some fields, wait 21 minutes. | About 30 seconds before `expiresAt` the iframe reloads with a new payment page; the typed values stay. |
| TC10 | Submit replay | After TC01, re-send the same `org_donation_submit` request (DevTools → Copy as fetch). | HTTP 409 with "ההוראה כבר נקלטה. תודה!". |
| — | Rate limit | Reload the form page 11 times within 10 minutes. | The 11th load shows "בוצעו ניסיונות רבים. נסו שוב בעוד מספר דקות." and no iframe. |
| — | Cache / CSP | Load the form page twice in two browsers. | Two different iframe URLs; `/cardcom-return/` shows inside the iframe (not blocked by CSP). |
| — | Donor page: invalid link | Open `/donor/?a=amount&t=abc`. | "הקישור אינו תקף. לפרטים פנו אלינו: …"; the token disappears from the address bar. |
| — | Donor page: amount, card | See TC25–TC28 above. | Messages per B7.12.4. |

## Charging — TC11–TC21 (Prompts 4–5)

Manual steps run in the sandbox against Cardcom's public test terminal (`CLAUDE.md` B5.0א) with a real token from TC01. The
"simulated date" is Anonymous Apex as the integration user: `ChargePlanner.plan(Date.newInstance(2026, 11, 4), 'AM');` — the planner
starts the chain itself. On the test terminal a charge **above 5,000 ₪** is declined (B5.0א).

| ID | Scenario | Automated | Manual (sandbox + test terminal) |
|---|---|---|---|
| TC11 | Regular day | `ChargePlannerTest.regularMorningPlansOneAttemptPerPledge`, `ChargeQueueableTest.successfulChargeUpdatesChargeAndPledgeLast4` | `plan(<Wednesday>, 'AM')`: one Success per Active pledge, `Cardcom_Tranzaction_Id__c` filled, `Last4__c` on the pledge. Thank-you email: Prompt 8. |
| TC12 | Friday | `ChargePlannerTest.fridayChargesFridayAndShabbat`, `ChargeCalendarTest.multiplicityTableFromB66` | `plan(<Friday>, 'AM')`: 2 charges per pledge (Fri + Sat) with different `ExternalUniqTranId__c`. Grouped email: Prompt 8. |
| TC13 | Erev Rosh Hashana 5787 | `ChargePlannerTest.erevRoshHashanaChargesThreeDays` | `plan(2026-09-11, 'AM')`: 3 charges (11, 12, 13). |
| TC14 | Shabbat / holiday | `DonationChargeSchedulerTest.runsOnlyOnItsDays`, `ChargePlannerTest.restDayPlansNothingAndRerunIsIdempotent` | Run the scheduler on 2026-09-12: no charges. |
| TC15 | Temporary failure | `ChargeOutcomeHandlerTest.retryableGoesA1A2A3ThenFinal` | Pledge with `Charge_Amount__c` 5001 (bypass the range rule temporarily, or charge by hand from Anonymous Apex with `CardcomService.chargeToken(token, exp, 5001, key)`): A1 Failed → A2 one hour later → A3 four hours later → final. `Consecutive_Failures__c = 1` comes with Prompt 6. |
| TC16 | Blocked card | `ChargeOutcomeHandlerTest.cardDeadIsFinalForThisLogicalChargeOnly`, `ChargeQueueableTest.expiredCardFailsFinalAndTheNextChargeIsStillPlanned` | No public blocked test card (B5.0א): covered by the mock only. |
| TC17 | Expired card | `ChargeQueueableTest.expiredCardFailsFinalAndTheNextChargeIsStillPlanned` | Set `CardExpirationMMYY__c = 0124` on a test pledge: the charge is sent, fails final (Card_Dead), and the next day's run still plans it (D11). |
| TC18 | 3 consecutive failures | `PledgeRollupServiceTest.threeFailuresAlertOnceAndTheFourthDoesNot` | TC15 three times on one pledge: one staff email (Failure_Notify_Emails__c), pledge stays Active; a fourth failure sends nothing. |
| TC19 | Success after a streak | `PledgeRollupServiceTest.successResetsTheStreakAndReArmsTheAlert` | Replace the card (Prompt 8) or lower the amount, charge successfully: `Consecutive_Failures__c = 0`, `Failure_Alert_Sent_At__c` empty. |
| TC20 | Retry after an unknown success | `ChargeQueueableTest.verifiedPreviousSuccessIsNotChargedAgain`, `ChargeQueueableTest.verifiedPreviousFailureIsChargedNormally` | Charge A1 by hand, then create an A2 with `Verify_Attempt_Key__c` = A1's key and run the chain: A2 becomes Success / `ALREADY_CHARGED`, and Cardcom shows one transaction. |
| TC21 | Timeout | `ChargeOutcomeHandlerTest.unknownOutcomeVerifiesTheKeyNextTime`, `ChargeQueueableTest.timeoutLeadsToAVerifiedRetry` | Mock only (no way to force a Cardcom timeout). |

Also automated: Stopped pledge → Skipped STOPPED with no Cardcom call (`ChargeQueueableTest.stoppedPledgeIsSkipped`); Config error → no
retry, one alert a day, manual re-run (`ChargeQueueableTest.configErrorCreatesNoRetryAndAlertsOncePerDay`); retry falling after the
Friday cutoff → Sunday 08:00 (`ChargeOutcomeHandlerTest.retryThatWouldFallAfterTheFridayCutoffMovesToSunday`); 200 pledges × 2 dates
in one transaction and the batch path for large volumes (`ChargePlannerTest`); callout time budget (`ChargeQueueableTest.calloutBudgetLeavesTheRestPending`).
Calendar: Rosh Hashana 5785–5790 and the 2026/2027 sets (`HebrewHolidaysTest`), overrides, retry window (`ChargeCalendarTest`), settings
and scheduling (`ChargeSettingsTest`, `DonationSetupTest`).

### Planning volume (2,500 pledges)
- Synchronous planning handles up to `ChargePlanner.SYNC_MAX` = 1,000 pledges: at most 4 dates each = 4,000 rows in one insert, a
  constant number of queries (`bulkFridayStaysInsideLimits` measures ≤ 6 queries, ≤ 3 DML statements for 200 pledges).
- Above 1,000 pledges `ChargePlannerBatch` plans 200 pledges per chunk (≤ 800 rows each), so 2,500 pledges × 4 dates (Rosh Hashana on
  Thu–Fri + Shabbat) = 10,000 rows never land in one transaction (the per-transaction limit is 10,000).
- Charging: 30 charges per link (`Batch_Size__c`), at most 2 callouts each; each link stops calling out after 90 s of the 120 s
  callout budget. 5,000 Friday charges ≈ 167 links (B6.5 rule 6).

## Manual stop / resume / cancel / revoke (Prompt 6)

| Scenario | Automated | Manual (sandbox) |
|---|---|---|
| Stop | `PledgeTriggerHandlerTest.stopSkipsPendingChargesAndLogs` | As a `Donations_Admin` user, on an Active pledge click "הפסקת חיובים", pick a reason: stage Stopped, Pending charges Skipped (STOPPED), change log "Stop". The button doesn't show without `Stop_Pledge_Charges`. |
| Resume | `PledgeTriggerHandlerTest.resumeAndCancelAreLoggedAndCancelIsFinal` | "חידוש חיובים" on a Stopped pledge: Active from the next run, skipped days not made up, log "Resume". |
| Cancel | same | "ביטול הוראה": Cancelled, End Date today, log "Cancel"; Edit → Active is refused. |
| Revoke links | `PledgeTriggerHandlerTest.revokingLinksIsLogged` | "ביטול קישורי תורם": `Link_Version__c` + 1, log "Link_Revoke". Old links stop working with Prompt 8. |
| Permission | `PledgeTriggerHandlerTest.userWithoutPermissionIsBlocked`, `PledgeValidationRulesTest.stoppingWithoutPermissionIsBlocked` | A `Donations_Staff` user sees no action buttons; a direct edit of the stage is refused with "אין לך הרשאה לעצור/לחדש חיובים." |

## Nightly reconciliation — TC36 (Prompt 7)

| ID | Scenario | Automated | Manual (sandbox + test terminal) |
|---|---|---|---|
| TC36 | Reconciliation issue, re-run without duplicates | `ReconciliationJobTest.eachIssueTypeIsReported`, `ReconciliationJobTest.reRunUpdatesIssuesInPlaceAndKeepsStaffResolution` | After a charging day (TC11), as the integration user set one Success charge's `Cardcom_Tranzaction_Id__c` to `999999999`, then run `System.enqueueJob(new ReconciliationJob(Date.today()));`. Expect one `Missing_In_Cardcom` issue (and a `Missing_In_Salesforce` for the real transaction); run it again: still the same issues. B11's "change the amount of a Success charge" is blocked by `VR_Charge_Immutable_After_Final` (B2.3), so `Amount_Mismatch` is covered by the automated test only (N76). |
| — | Every issue type | `ReconciliationJobTest.eachIssueTypeIsReported` (Missing_In_Cardcom, Amount_Mismatch, Status_Mismatch, Missing_In_Salesforce), `twoRealChargesForOneLogicalChargeIsADuplicate` | Report "פערי התאמה פתוחים" (folder Donations) and list view of the same name show them; staff set Status to Resolved/Ignored. |
| — | Unknown outcome fixed automatically | `ReconciliationJobTest.unknownOutcomeConfirmedByCardcomIsFixedAutomatically`, `notFoundInCardcomClearsTheFlag`, `sameTranzactionIdOnTheRetryIsNotADuplicate` | TC20/TC21 leave a `Failed (Unknown)` attempt with `Needs_Reconciliation__c`; the next night it becomes Success `RECONCILED` (if Cardcom charged it) or the flag is cleared. |
| — | Paging | `pagingContinuesWhileAPageIsFull`, `exactlyFullLastPageTriggersOneEmptyRequest` | — |
| — | Unknown Cardcom transactions ignored | `unknownCardcomTransactionsCanBeIgnored` (`Recon_Report_Unknown__c = false`) | — |
| — | Staff alert | `eachIssueTypeIsReported` (Alert_State__c), `cardcomErrorsAbortWithoutChanges` (config alert) | One "פערי התאמה פתוחים" email a day while issues are Open. |
| — | Log clean-up | `LogCleanupBatchTest` | — |

## Running the tests (sandbox, check-only)

```bash
sf project deploy validate --target-org <alias> --source-dir force-app --test-level RunLocalTests
```
