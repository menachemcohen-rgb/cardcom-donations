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

## Running the tests (sandbox, check-only)

```bash
sf project deploy validate --target-org <alias> --source-dir force-app --test-level RunLocalTests
```
