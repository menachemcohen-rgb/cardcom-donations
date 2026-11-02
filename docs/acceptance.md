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

## Running the tests (sandbox, check-only)

```bash
sf project deploy validate --target-org <alias> --source-dir force-app --test-level RunLocalTests
```
