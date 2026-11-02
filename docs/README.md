# Cardcom ↔ WordPress ↔ Salesforce micro-donations

The spec lives in [`CLAUDE.md`](../CLAUDE.md) (Part A background, Part B authoritative spec, Part C Opportunity override and errata;
precedence **C > B > A**). The client-facing spec is [`spec/cardcom-donations-client-spec.pdf`](../spec/cardcom-donations-client-spec.pdf).
The implementation prompts and their run order are in [`docs/prompts.md`](prompts.md).

## Architecture

A custom WordPress plugin (`org-donations`, shortcode `[org_donation_form]`) renders the donation form. On page load, PHP calls a
Salesforce Apex REST endpoint (Connected App, OAuth Client Credentials) that asks Cardcom (`LowProfile/Create`, `CreateTokenOnly`) for a
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
   required fields, validation rules, duplicate rules).
2. **Retrieve the existing `OpportunityStage` StandardValueSet** into `force-app/main/default/standardValueSets/` before adding the 5
   new stages (E14). Confirm none of the 5 values already exists.
3. Count the Opportunity fields that already have Field History tracking (limit 20; Part C adds 6).
   - Sandbox: 0 tracked, no stage collisions (discovery 2026-11-02).
   - Check the action of `Standard_Contact_Duplicate_Rule` in Setup: it must not **Block** (org-discovery R5).
   - Add the `Donor` value to the OpportunityContactRole `Role` standard value set the same way as the stages (retrieve the whole set,
     add, never deploy a partial set) — org-discovery R9.
4. Enable **Translation Workbench** and add Hebrew (`iw`) for the Hebrew stage and record-type labels.

### Integration user
5. Create `integration.donations@<org>`: Salesforce Integration license, profile `Minimum Access - API Only Integrations`,
   **TimeZoneSidKey = Asia/Jerusalem**, Locale `he_IL`. Assign PS `Donations_Integration` (Prompt 2).

### Credentials (values never in the repo)
6. External Credential `Cardcom_EC`, principal `CardcomTerminal`: enter `ApiName` and `ApiPassword` in Setup.
   Sandbox uses Cardcom's public test terminal from B5.0א (terminal `1001`); production uses the client's terminal.
7. `Donor_Link_Setting__mdt.Default` secret: generate a random value and enter it in Setup (Protected CMDT).

### Connected App, Site, email
8. Connected App `WP_Donations` (Client Credentials, Run As the integration user, IP restrictions to the WP server) — B3.2.
   Consumer Key/Secret go into the WordPress `wp-config.php` only.
9. Salesforce Site `cardcom` + Guest user PS `Donations_Site_Guest`; only `CardcomWebhookResource` exposed — B3.3.
10. Verify an **Org-Wide Email Address** for staff alerts and donor emails and allow the integration user to use it. Email
    Deliverability = All email.

### After deploy
11. Run `ContactNormalizationBatch` on existing Contacts **before** activating Matching Rule `Donor_Contact_Match` / Duplicate Rule
    `Donor_Contact_Duplicate` (B10 step 12).
12. `DonationSetup.scheduleAll()` as the integration user.
13. Check that no profile's default Opportunity record type became `Micro_Donation_Pledge` (it is the org's first Opportunity record
    type; org-discovery R3).

### Org settings to record (do not change)
Recorded from the Ato Dev sandbox on 2026-11-02 (`docs/org-discovery.md`); re-check on production.
- OWD: Opportunity **Public Read Only**, Account **Public Read/Write**, Contact **Controlled by Parent** (C2 rule 5).
- No Shield Platform Encryption detected: encrypted fields use **Classic Encrypted Text** (max 175 chars, not filterable, masked).
- Every new Contact gets a "{First} {Last} Household" Account from the org's flow `Create_New_Account_When_Creating_A_Contact`.
