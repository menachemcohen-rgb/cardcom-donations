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
7. **Cardcom credentials.** Setup → Named Credentials → External Credentials → `Cardcom_EC` → Principals → `CardcomTerminal` →
   Authentication Parameters: add `ApiName` and `ApiPassword` (exact names; the request body uses
   `{!$Credential.Cardcom_EC.ApiName}` / `{!$Credential.Cardcom_EC.ApiPassword}`). The named principal and the Named Credential
   `Cardcom` (`https://secure.cardcom.solutions`, formulas allowed in the body only) are deployed as metadata; the values never are.
   - Sandbox: Cardcom's public test terminal — terminal number, ApiName and ApiPassword are in `CLAUDE.md` B5.0א (terminal `1001`).
     They're public, but B5.0א says not to copy them anywhere else in the repo, so this README only points to them.
   - Production: the client's terminal.
   - Principal access is granted only through `Donations_Integration`.
8. **Donor-link secret.** Setup → Custom Metadata Types → Donor Link Setting → Manage Records → `Default`: set `Secret__c` to 64
   random hex characters (for example `openssl rand -hex 32`). Leave `Previous_Secret__c` empty until the first rotation.
   The type is Protected and the deployed record has an empty secret.
9. **`Cardcom_Setting__mdt.Default` values.** The deployed record has the B2.6 defaults. Fill in by hand per org:
   `Terminal_Number__c` (sandbox `1001`, production the client's), `Integration_User_Id__c` (18-char Id of the integration user),
   `Failure_Notify_Emails__c` (Q7), `Org_Wide_Email_Address__c`, `Terms_Url__c` (Q8), and replace the `ORG` placeholders in
   `Donor_Portal_Base_Url__c`, `Webhook_Url__c` and `Allowed_Return_Hosts__c`. `Default_Account_Id__c` stays empty (org-discovery D-3).

### External Client App, Site, email
10. **External Client App `WP_Donations`** (Part C D27, replaces B3.2's Connected App). Created in Setup, not deployed: its OAuth
    policies name the org's integration user, and its global OAuth settings hold the consumer key.
    1. Setup → External Client App Manager → New External Client App. Name `WP Donations`, API name `WP_Donations`, contact email,
       Distribution State **Local**.
    2. API (Enable OAuth): callback URL `https://login.salesforce.com/services/oauth2/success` (not used), OAuth scope
       "Manage user data via APIs (`api`)" only. Flow Enablement: **Enable Client Credentials Flow**. Create.
    3. Policies → Edit → OAuth Policies: Permitted Users = "Admin approved users are pre-authorized", select permission set
       `Donations_Integration`; IP Relaxation = **Enforce IP restrictions**; Client Credentials Flow → Run As = the integration user
       (step 6). Save.
    4. Network access for the WP server's outgoing IP (Q11): Setup → Network Access, or the integration user's profile Login IP Ranges.
    5. Settings → OAuth Settings → Consumer Key and Secret: copy them into the WordPress `wp-config.php` as `ORG_SF_CLIENT_ID` and
       `ORG_SF_CLIENT_SECRET` (B7.3), together with `ORG_SF_LOGIN_URL` = the org's My Domain URL. Never anywhere else.
    6. Check: `curl -s -X POST https://<mydomain>/services/oauth2/token -d grant_type=client_credentials -d client_id=... -d client_secret=...`
       returns an `access_token`. The token endpoint is the same as for a Connected App.
11. **Salesforce Site `cardcom`** (B3.3), created in Setup (its guest user is org-specific):
    1. Setup → Sites: register a Sites domain if there is none, then New: label `cardcom`, name `cardcom`, default web address `cardcom`,
       Active Site Home Page `InMaintenance`, Clickjack Protection "Allow framing by the same origin only". Activate.
    2. Public Access Settings: leave the guest profile with no object access. Assign permission set `Donations_Site_Guest` to the site's
       guest user (it grants only: create `Cardcom_Webhook_Log__c` rows, publish `Cardcom_Lp_Event__e`, run `CardcomWebhookResource`).
    3. Setup → Sharing Settings: keep "Secure guest user record access" on; no sharing rules for the guest.
    4. Put the webhook URL `https://<domain>.my.salesforce-sites.com/cardcom/services/apexrest/cardcom/webhook` into
       `Cardcom_Setting__mdt.Default.Webhook_Url__c` (step 9). Check: a POST with `{"LowProfileId":"test-0000000001"}` returns 200
       and creates a `Cardcom_Webhook_Log__c` row.
12. Verify an **Org-Wide Email Address** for staff alerts and donor emails and allow the integration user to use it. Email
    Deliverability = All email.

### After deploy
13. **Custom-setting defaults.** Custom-setting data isn't metadata, so the deploy can't create the Org Default records. Run once per org
    (it skips records that already exist):

```bash
sf apex run --target-org <alias> --file scripts/apex/init-settings.apex
```

14. **Permission sets** (B2.7): assign `Donations_Integration` to the integration user, `Donations_Admin` to the data/finance managers,
      `Donations_Staff` to fundraising staff, and `Donations_Site_Guest` to the guest user of Site `cardcom` (Prompt 3). Give the
    integration user the "Salesforce API Integration" permission set license first, then check it can be assigned `Donations_Integration`.
15. **Record type access.** `Micro_Donation_Pledge` is the org's first Opportunity record type. It is deployed without profile
    assignments (profiles are never deployed). Check that no profile's default Opportunity record type changed (org-discovery R3).
    Access to the record type comes from the `Donations_*` permission sets (Prompt 2).
16. **Page layout assignment.** Setup → Object Manager → Opportunity → Page Layouts → Page Layout Assignment: assign
    "Micro Donation Pledge Layout" to record type `Micro_Donation_Pledge` for every profile that will see pledges (at least System
    Administrator). Layout assignments live in profiles, which this repo doesn't deploy.
17. **Activate the record page.** Lightning App Builder → `Pledge_Record_Page` (label "עמוד הוראת תרומה יומית") → Activation →
    App, Record Type and Profile: assign it to record type `Micro_Donation_Pledge` only (C2 rule 6). Don't make it the org default.
    The page carries the dynamic actions הפסקת חיובים / חידוש חיובים / ביטול הוראה / ביטול קישורי תורם, shown by stage and only to
    users with `Stop_Pledge_Charges` (`Donations_Admin`).
18. **Field history on `StageName`** (optional). Part C lists it, but Opportunity already records every stage change in Stage History
    (`OpportunityHistory`) automatically. Turn on Field History for `StageName` in Setup only if you also want it in the field-history
    list; it counts toward the limit of 20.
19. **Contact layout section** (B2.8): add a "תורם מיקרו" section to the existing "Contact Layout" with `Donor_Source__c`,
    `Needs_Review__c`, `Review_Reason__c`, `Donor_Tax_Id__c`, and the related list "הוראות תרומה יומית" (`Donor_Pledges`). Done by hand
    because deploying the Contact layout would overwrite the org's existing one.
20. **Platform event subscriber** (B6.3). `CardcomLpEventTrigger` must run as the integration user, otherwise its job can't use the
    Cardcom credential. PlatformEventSubscriberConfig has no Setup page and names an org-specific user, so it is a template outside
    `force-app`. Deploy it once per org (a real deploy, after the trigger is deployed):

```bash
scripts/deploy-pe-subscriber.sh <alias> integration.donations@<org>
```

21. **Normalize existing Contacts, then activate the donor rules** (B10 step 12). Matching Rule `Donor_Contact_Match` and Duplicate
    Rule `Donor_Contact_Duplicate` are deployed **inactive**. First run the backfill as an admin and wait for it to finish:

```bash
sf apex run --target-org <alias> --file scripts/apex/normalize-contacts.apex
```

    Then Setup → Matching Rules → `Donor Contact Match` → Activate (wait for the activation email), then Setup → Duplicate Rules →
    `Donor Contact Duplicate` → Activate.
22. **LP sweeper** (B5.3), only if the full schedule (step 23) isn't set up yet: schedule it every 15 minutes. Scheduled jobs run as the user who schedules them, and the sweeper's job calls
    Cardcom, so schedule it as the integration user. That user is API-only, so authorize the CLI as it (for example with the JWT
    bearer flow) and run (see spec-consistency N42):

```bash
sf apex run --target-org <alias> --file scripts/apex/schedule-lp-sweeper.apex
```

23. **Charge schedule** (B9). Before the first run, allow deploys while jobs are scheduled: Setup → Deployment Settings → "Allow
    deployments of components when corresponding Apex jobs are pending or in progress". Otherwise every later deploy of a class used by
    a scheduled job fails. Then, as the integration user (same JWT session as step 22, TZ Asia/Jerusalem):

```bash
sf apex run --target-org <alias> --file scripts/apex/schedule-donations.apex
```

    It schedules the 4 charge runs (AM, PM, Eve AM, Eve PM on SUN-FRI; `ChargeCalendar.shouldRun` decides), the LP sweepers, and every
    later job whose class is already deployed; it prints the ones it skipped. Don't run step 22 as well — `scheduleAll()` includes the
    sweepers. After later prompts add the retry, receipt, reconciliation, alert and cleanup classes, run
    `DonationSetup.unscheduleAll(); DonationSetup.scheduleAll();` again.
24. **"Apply charge schedule" button** (B9.1). Times in `Charge_Settings__c` only take effect after re-scheduling. Add the screen flow
    `Apply_Charge_Schedule` ("החלת זמני חיוב") where admins work, for example: App Manager → the app → Utility Items → Add → Flow →
    `Apply_Charge_Schedule`. It runs only for users with `Manage_Charge_Schedule` (in `Donations_Admin`) and TZ Asia/Jerusalem.
    Note: jobs re-scheduled from the button run as that admin (see spec-consistency N42).

### Operations (charge engine)
- **Emergency stop:** set `Charge_Settings__c.Charging_Enabled__c = false`. No run plans charges and the dispatcher sends nothing,
  retries included; Pending charges wait. Setting it back to true resumes with the next scheduled run or retry sweep.
- **After a Cardcom configuration error** (wrong API user/password, B6.13 E21): fix the credential, then as the integration user
  `ChargeAdmin.requeueFailedConfig(Date.today());` — it creates one new attempt per Config-failed charge of that day and starts the chain.
- **Simulated run** (sandbox, B11): `ChargePlanner.plan(Date.newInstance(2026, 11, 4), 'AM');` plans and starts charging immediately.

### Org settings to record (do not change)
Recorded from the Ato Dev sandbox on 2026-11-02 (`docs/org-discovery.md`); re-check on production.
- OWD: Opportunity **Public Read Only**, Account **Public Read/Write**, Contact **Controlled by Parent** (C2 rule 5).
- No Shield Platform Encryption detected: encrypted fields use **Classic Encrypted Text** (max 175 chars, not filterable, masked).
  `MetadataSmokeTest.encryptedFieldsAreNotFilterable` records the scheme in its debug log and fails if a field is filterable.
- Every new Contact gets a "{First} {Last} Household" Account from the org's flow `Create_New_Account_When_Creating_A_Contact`.
- All users have language `en_US`, so they see the English stage labels ("Pending Verification", "Active"…). The Hebrew labels from
  C1 appear only for users whose language is Hebrew.

## Validating (no deploy)

`sf project deploy validate` is a check-only deploy: it compiles and runs the tests in the target org, then rolls everything back.
Do this only against a sandbox, and only after manual steps 3 and 4 above (field history, Translation Workbench).

1. Retrieve the org's standard value sets into a scratch folder and compare them with the repo (E14):

```bash
sf project retrieve start --target-org <alias> --manifest manifest/retrieve-standard-value-sets.xml --output-dir /tmp/svs-check
```

```bash
diff -r "$(find /tmp/svs-check -type d -name standardValueSets)" force-app/main/default/standardValueSets
```

   Apart from formatting, the diff must show only added values: 5 stages in `OpportunityStage`, `Donor` in `ContactRole`. Anything
   else (a value missing from the repo, a changed probability) means the org changed since 2026-11-02: update the repo file from the
   retrieved one first.

2. Validate the whole source tree and run all local tests (Prompts 1 and 2 together; the layout and record page need Prompt 2's
   `Charge__c` and `Pledge_Change_Log__c`):

```bash
sf project deploy validate --target-org <alias> --source-dir force-app --test-level RunLocalTests
```

Credentials, CMDT values and custom-setting records are post-deploy steps (7–9, 13); the validation doesn't need them.
