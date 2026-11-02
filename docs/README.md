# Cardcom ↔ WordPress ↔ Salesforce micro-donations

The spec lives in [`CLAUDE.md`](../CLAUDE.md) (Part A background, Part B authoritative spec, Part C Opportunity override and errata;
precedence **C > B > A**). The client-facing spec is [`spec/cardcom-donations-client-spec.pdf`](../spec/cardcom-donations-client-spec.pdf).
The implementation prompts and their run order are in [`docs/prompts.md`](prompts.md).

## Architecture

A custom WordPress plugin (`org-donations`, shortcode `[org_donation_form]`) renders the donation form. On page load, PHP calls a
Salesforce Apex REST endpoint (External Client App, OAuth Client Credentials) that asks Cardcom (`LowProfile/Create`, `CreateTokenOnly`) for a
hosted card iframe. Terminal credentials exist only in Salesforce (External/Named Credential `Cardcom`). When the donor submits, the
iframe's return page posts a message to the parent, JS sends amount, frequency and donor details plus the `LowProfileId` to PHP, and PHP
posts them to Salesforce, which stores them on a **pledge Opportunity** (Record Type `Micro_Donation_Pledge`, stage
`Pending_Verification`). Cardcom's webhook to a Salesforce Site and a server-side `GetLpResult` call are the source of truth for the
card token. Once both the form data and the verified token exist, an integration-user job matches or creates the donor Contact and
activates the pledge (stage `Active`).

Scheduled Apex (Asia/Jerusalem) charges active pledges once or twice a day with the stored token (`Transactions/Transaction`), never on
Shabbat or holidays; on a Friday or holiday eve it charges the rest days ahead of time. Every attempt is a `Charge__c` (two-phase: plan
`Pending` rows, then Queueables call Cardcom). Retries, roll-ups, consecutive-failure alerts to staff (no auto-suspension, manual stop
only), a thank-you email with signed donor links (card change / amount change), a monthly donation receipt issued through Cardcom
`Documents/CreateDocument`, and a nightly reconciliation against Cardcom `ListTransactions` complete the system.

## Part C decisions (summary)

| # | Decision |
|---|---|
| D23 | The pledge is a standard **Opportunity** with Record Type `Micro_Donation_Pledge`; no `Recurring_Pledge__c` object. |
| D24 | Every trigger, flow, validation rule, query, list view and page is scoped to that Record Type. Other Opportunities are never touched. |
| D25 | Standard `Amount` mirrors `Total_Collected__c`; the per-charge amount is `Charge_Amount__c`. |
| D26 | NPSP is **not installed** in the target org. |
| C1 | Own Sales Process `Micro_Donation_Process` with 5 stages: `Pending_Verification`, `Active`, `Stopped`, `Cancelled`, `Verification_Failed`. |
| E14 | The 5 stages are **added** to the org's existing `OpportunityStage` StandardValueSet; a partial set is never deployed. |
| E15/E16 | Encrypted fields (`Token__c`, `Donor_Tax_Id__c`) are never used in SOQL filters, report/list-view filters or matching rules. ID matching uses `Contact.Tax_Id_Hash__c`. |
| E1–E13 | Canonical names for fields and methods that were inconsistent in Parts A/B (see `CLAUDE.md` C3). |

## Repository layout

| Path | Contents |
|---|---|
| `force-app/main/default/` | Salesforce source-format metadata (API 62.0). Platform Events live under `objects/` (`*__e`), as SFDX source format requires. |
| `wordpress/org-donations/` | WordPress plugin (Prompt 10). |
| `docs/` | This README, prompts, consistency check, org discovery, acceptance, runbook (later prompts). |
| `scripts/` | Read-only org discovery script; later the plugin build script. |
| `spec/` | Client spec PDF. |

## Ground rules

- Nothing is deployed to any org and no real Cardcom call is made without explicit approval.
- No secrets in the repo. Credentials are entered in Setup (see below); Named Credential merge-field placeholders are never replaced in Apex.
- Every Apex class has a test class (`TestDataFactory` + `CardcomMock`).

## Manual Setup steps

This list grows with every prompt. Steps are grouped by the B10 deployment order.

### Before the first deploy
1. Run the read-only discovery in [`docs/org-discovery.md`](org-discovery.md) and resolve its risk list (existing Opportunity automation,
   required fields, validation rules, duplicate rules). Sandbox: done 2026-11-02; production: still to do.
2. **Standard value sets (E14).** The repo's `OpportunityStage` and `ContactRole` sets were built from the Ato Dev sandbox's live values
   (2026-11-02) plus the new values. Before deploying to any org, retrieve that org's sets and compare; the only differences must be the
   5 new stages and the `Donor` role. See "Validating Prompt 1" below. Never deploy a partial set.
3. **Enable Opportunity field history** (Setup → Object Manager → Opportunity → Fields & Relationships → Set History Tracking →
   "Enable Opportunity Field History"). It is off in the sandbox, and the fields Part C tracks (`Charge_Amount__c`, `Frequency__c`,
   `Stop_Reason__c`, `Link_Version__c`, `Last4__c`) fail to deploy with `trackHistory=true` until it is on. Limit 20 tracked fields
   (sandbox: 0 tracked before this project).
4. Enable **Translation Workbench** and add Hebrew (`iw`) as an active language. The stage and contact-role translations
   (`standardValueSetTranslations/*-iw`) fail to deploy without it.
5. Check the action of `Standard_Contact_Duplicate_Rule` in Setup: it must not **Block** (org-discovery R5).

### Integration user
6. Create `integration.donations@<org>`: Salesforce Integration license, profile `Minimum Access - API Only Integrations`,
   **TimeZoneSidKey = Asia/Jerusalem**, Locale `he_IL`. Assign PS `Donations_Integration` (Prompt 2).

### Credentials (values never in the repo)
7. External Credential `Cardcom_EC`, principal `CardcomTerminal`: enter `ApiName` and `ApiPassword` in Setup.
   Sandbox uses Cardcom's public test terminal from B5.0א (terminal `1001`); production uses the client's terminal.
8. `Donor_Link_Setting__mdt.Default` secret: generate a random value and enter it in Setup (Protected CMDT).

### External Client App, Site, email
9. External Client App `WP_Donations` (Part C D27, replaces B3.2's Connected App): OAuth scope `api`, Client Credentials Flow with
   Run As = the integration user, IP restrictions to the WP server. Consumer Key/Secret go into the WordPress `wp-config.php` only.
   Prompt 3 adds the app's metadata where it can be deployed and the exact Setup steps for the rest.
10. Salesforce Site `cardcom` + Guest user PS `Donations_Site_Guest`; only `CardcomWebhookResource` exposed — B3.3.
11. Verify an **Org-Wide Email Address** for staff alerts and donor emails and allow the integration user to use it. Email
    Deliverability = All email.

### After deploy
12. **Record type access.** `Micro_Donation_Pledge` is the org's first Opportunity record type. It is deployed without profile
    assignments (profiles are never deployed). Check that no profile's default Opportunity record type changed (org-discovery R3).
    Access to the record type comes from the `Donations_*` permission sets (Prompt 2).
13. **Page layout assignment.** Setup → Object Manager → Opportunity → Page Layouts → Page Layout Assignment: assign
    "Micro Donation Pledge Layout" to record type `Micro_Donation_Pledge` for every profile that will see pledges (at least System
    Administrator). Layout assignments live in profiles, which this repo doesn't deploy.
14. **Activate the record page.** Lightning App Builder → `Pledge_Record_Page` (label "עמוד הוראת תרומה יומית") → Activation →
    App, Record Type and Profile: assign it to record type `Micro_Donation_Pledge` only (C2 rule 6). Don't make it the org default.
15. **Field history on `StageName`** (optional). Part C lists it, but Opportunity already records every stage change in Stage History
    (`OpportunityHistory`) automatically. Turn on Field History for `StageName` in Setup only if you also want it in the field-history
    list; it counts toward the limit of 20.
16. **Contact layout section** (B2.8): add a "תורם מיקרו" section to the existing "Contact Layout" with `Donor_Source__c`,
    `Needs_Review__c`, `Review_Reason__c`, `Donor_Tax_Id__c`, and the related list "הוראות תרומה יומית" (`Donor_Pledges`). Done by hand
    because deploying the Contact layout would overwrite the org's existing one.
17. Run `ContactNormalizationBatch` on existing Contacts **before** activating Matching Rule `Donor_Contact_Match` / Duplicate Rule
    `Donor_Contact_Duplicate` (B10 step 12).
18. `DonationSetup.scheduleAll()` as the integration user.

### Org settings to record (do not change)
Recorded from the Ato Dev sandbox on 2026-11-02 (`docs/org-discovery.md`); re-check on production.
- OWD: Opportunity **Public Read Only**, Account **Public Read/Write**, Contact **Controlled by Parent** (C2 rule 5).
- No Shield Platform Encryption detected: encrypted fields use **Classic Encrypted Text** (max 175 chars, not filterable, masked).
  `MetadataSmokeTest.encryptedFieldsAreNotFilterable` records the scheme in its debug log and fails if a field is filterable.
- Every new Contact gets a "{First} {Last} Household" Account from the org's flow `Create_New_Account_When_Creating_A_Contact`.
- All users have language `en_US`, so they see the English stage labels ("Pending Verification", "Active"…). The Hebrew labels from
  C1 appear only for users whose language is Hebrew.

## Validating Prompt 1 (no deploy)

`sf project deploy validate` is a check-only deploy: it compiles and runs the tests in the target org, then rolls everything back.
Do this only against a sandbox, and only after manual steps 3 and 4 above.

1. Retrieve the org's standard value sets into a scratch folder and compare them with the repo (E14):

```bash
sf project retrieve start --target-org <alias> --manifest manifest/retrieve-standard-value-sets.xml --output-dir /tmp/svs-check
```

```bash
diff -r "$(find /tmp/svs-check -type d -name standardValueSets)" force-app/main/default/standardValueSets
```

   Apart from formatting, the diff must show only added values: 5 stages in `OpportunityStage`, `Donor` in `ContactRole`. Anything else (a value missing from
   the repo, a changed probability) means the org changed since 2026-11-02: update the repo file from the retrieved one first.

2. Validate the data model and run its tests:

```bash
sf project deploy validate --target-org <alias> --manifest manifest/prompt-1-core.xml --test-level RunSpecifiedTests --tests MetadataSmokeTest --tests PledgeValidationRulesTest
```

3. The layout and record page (`manifest/prompt-1-pages.xml`) reference `Charge__c` and `Pledge_Change_Log__c`, which Prompt 2 creates.
   Validate them together with Prompt 2 (B10 step 11):

```bash
sf project deploy validate --target-org <alias> --source-dir force-app --test-level RunLocalTests
```
