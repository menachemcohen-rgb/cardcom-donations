# Claude Code prompts — Cardcom ↔ WordPress ↔ Salesforce micro-donations

Version 2.2 (2026-11-02). Changes from the previous pack are marked **[v2.2]**.

## How to use

1. `CLAUDE.md` in the repo root already contains Part C (precedence C > B > A).
2. Start every prompt in a fresh Claude Code session (`/clear`), paste the Preamble first, then the prompt. Use plan mode for Prompts 3, 5 and 8.
3. One prompt = one branch + one PR. Don't start the next until acceptance passes.
4. Nothing is deployed and no real Cardcom call is made without an explicit "go".

### Run order **[v2.2]**

```
0 ─┬─ 1 → 2 ─┬─ 3 → 5 → 6 ─┬─ 7 ─┐
   │         └─ 4 ──┘      ├─ 8 ─┼─ 11 → 12
   │                       └─ 9 ─┘
   └─ 10 ──────────────────────────────→ 12
```

| Prompt | Depends on | Can run in parallel with |
|---|---|---|
| 0 | — | — |
| 1 | 0 | 10 |
| 2 | 1 | 10 |
| 3 | 2 | 4, 10 |
| 4 | 2 (`Charge_Settings__c`, `Charge_Holiday__mdt`); uses `TestDataFactory` from 3 if merged, otherwise its own test setup | 3, 10 |
| 5 | 3, 4 | 10 |
| 6 | 5 (replaces the `PledgeRollupService` stub; builds all E11 `StaffAlertService` methods) | 10 |
| 7, 8, 9 | 6 | each other |
| 10 | 0 only (B4 REST contract, no Apex) | everything up to 11 |
| 11 | best after 7–9, so reports cover every object | — |
| 12 | everything | — |

Prompts 0–6 are the core scope of the 40-hour quote. 7–9 and 11 are scope extensions (B12) and need client approval.

Merge in the order above. Nearly every prompt edits `docs/README.md` (manual steps) and several edit `docs/acceptance.md`
(3, 5, 8, 10), so parallel branches will have small, easy conflicts there.

## Preamble (paste at the start of EVERY session)

```
You are implementing the project described in CLAUDE.md in this repo.
Read CLAUDE.md fully before doing anything. Precedence: Part C > Part B > Part A.
Part C replaces Recurring_Pledge__c with the standard Opportunity (Record Type Micro_Donation_Pledge) and
lists errata with canonical names: follow Part C literally. If you find another inconsistency, do not guess:
list it under "Open issues" in your final report and choose the most conservative reading.
Also read docs/spec-consistency.md and apply the resolutions of its items that touch your task.

Ground rules:
- SFDX project, API version 62.0+, source-format metadata under force-app/main/default. WordPress plugin under wordpress/org-donations.
- Do NOT deploy to any org, run anything against Cardcom, or push to remote unless I say so. Local work, unit tests with mocks only.
  (If an org alias is available read-only, you may describe/retrieve metadata but never deploy.)
- Never put secrets in the repo. Credentials are placeholders/formula merge fields as in B3/B5.
- Encrypted fields (Token__c, Donor_Tax_Id__c) never appear in SOQL WHERE/ORDER BY/GROUP BY, report or list-view filters,
  or matching/duplicate rules (Part C rule 8, E15, E16). Select them, then check in Apex.
- Every Apex class gets a test class with the coverage target in B8. Use TestDataFactory + CardcomMock.
- Code in the spec is the baseline: copy it, adapt it per Part C (Opportunity), do not redesign it.
- Hebrew strings stay Hebrew exactly as written in the spec; identifiers stay English.
- Work in small commits with clear messages. At the end give: (1) what you built, (2) files, (3) tests run and results,
  (4) deviations from the spec and why, (5) Open issues, (6) what I must do manually in Setup.
```

## Prompt 0 — Repo bootstrap and read-only org discovery

```
Task: prepare the repo and learn the target org's Opportunity landscape. Read-only; no deploys.

1. Create the SFDX project skeleton (sfdx-project.json, .forceignore, .gitignore, package.json with prettier-plugin-apex
   and eslint for the wordpress JS is optional), the folders under force-app/main/default and wordpress/org-donations.
2. Add docs/README.md with: architecture summary (2 paragraphs), the Part C decisions, and a "Manual Setup steps" list
   that you will extend in every later prompt (External Client App, Site, OWEA, Named/External Credential values, integration user TZ).
3. Consistency check of CLAUDE.md: write docs/spec-consistency.md listing every identifier referenced but not defined, or defined
   twice with different names/signatures. Part C already resolves E1–E16; list anything NEW only, with your proposed resolution.
4. Org discovery (only if an org alias/MCP is connected; otherwise write the exact commands for me to run). NPSP is NOT installed (D26).
   - Person Accounts enabled? AccountId required on Opportunity?
   - All existing Opportunity record types, sales processes/stages (and whether any of the 5 new stage values already exists, E14),
     required custom fields, validation rules, triggers, record-triggered flows, duplicate rules, Process Builders, workflow rules,
     managed packages hooking Opportunity; number of history-tracked Opportunity fields.
   - Contact: existing duplicate/matching rules, triggers, flows, required fields.
   - OWD for Opportunity and Contact, Email deliverability, OrgWideEmailAddress list, TZ of the likely integration user.
   Write docs/org-discovery.md with findings and a risk list: which existing automation could fire on integration inserts of
   Micro_Donation_Pledge Opportunities, and the plan to scope/bypass it (Part C rule 4).

Acceptance: skeleton committed; docs/spec-consistency.md and docs/org-discovery.md exist; zero code written beyond the skeleton.
```

## Prompt 1 — Data model: Contact + Opportunity (T01, T02, T05 part)

```
Implement the data model for the donor and the pledge. Spec: B2.1 (Contact), B2.2 through Part C (Opportunity), B2.8 (layouts/pages), C1–C2.

Build as metadata in force-app:
1. Contact custom fields + VR_Tax_Id_Format (B2.1).
2. Opportunity: Record Type Micro_Donation_Pledge + Sales Process Micro_Donation_Process with the 5 stages and
   probabilities/IsClosed/IsWon exactly per C1, plus the Hebrew translations file.
   [v2.2] Stages (E14): retrieve the existing OpportunityStage StandardValueSet from the org first (or, without an org, stop and give
   me the retrieve command) and ADD the 5 values to it; never commit or deploy a partial set. Check that none of the 5 values already
   exists (case-insensitive); if one does, stop and report it. Document the retrieve step in the README.
3. Opportunity custom fields: every field in the C2 table (Pledge_Number__c auto number, Donor_Contact__c lookup,
   Charge_Amount__c, all carried-over B2.2 fields with the same types/lengths/encryption/unique/ext-id/help text).
   Token__c and Donor_Tax_Id__c encrypted (use Classic encrypted text if Shield isn't available; note it in the README).
   Card_Expiry_Date__c formula as in B2.2.
4. The 6 Opportunity validation rules from C2, all record-type guarded. Field History on the listed fields.
5. Page layout for the record type + the Lightning Record Page Pledge_Record_Page (B2.8): highlights, tabs, related lists
   (Charge__c, Pledge_Change_Log__c), the red "consecutive failures" banner via component visibility.
   Actions can be placeholders until Prompt 6 creates the flows.
6. Custom Permission Stop_Pledge_Charges (and Manage_Charge_Schedule).
7. Do NOT create Recurring_Pledge__c anywhere.

Tests: add an Apex test class MetadataSmokeTest that, using describe calls, asserts every field above exists with the expected
type/length and that the record type and the 5 stage values exist. It will run after deploy.
[v2.2] It also asserts and reports isFilterable() for Opportunity.Token__c, Opportunity.Donor_Tax_Id__c and Contact.Donor_Tax_Id__c
(expected false with Classic encryption or Shield probabilistic), so the encryption choice is visible in the test results.

Acceptance: `sf project deploy validate --dry-run` instructions documented (do NOT deploy); describe-based smoke test written;
README lists manual steps (translations, Hebrew labels, StandardValueSet retrieve).
```

## Prompt 2 — Data model: remaining objects, config, permissions (T03, T04, T05, T06)

```
Implement B2.3–B2.7 and the platform events, adapted by Part C.

1. Charge__c, Monthly_Receipt__c, Card_Change_Request__c, Pledge_Card_History__c, Pledge_Change_Log__c, Donor_Link_Use__c,
   Reconciliation_Issue__c (use SF_Amount__c per E2), Cardcom_Webhook_Log__c. Every Pledge__c lookup points to Opportunity
   (Part C), keep the API name Pledge__c, child relationship name Charges on Charge__c. Lookups with Restrict delete (no Master-Detail).
2. Platform Events Cardcom_Lp_Event__e and Charge_Success__e (B6.3/B6.5.1), Publish Immediately.
3. Custom Metadata types + records: Cardcom_Setting__mdt (add Terms_Url__c, Failure_Notify_Emails__c per E1/E3),
   Donor_Link_Setting__mdt (Protected; secret left EMPTY, documented as manual), Charge_Holiday__mdt, Cardcom_Error_Code__mdt
   with the 17 rows listed at the end of B5.8 (Source__c filled).
4. Custom Settings: Charge_Settings__c (hierarchy, org-default record with the defaults in B2.6), Charge_Run_Lock__c,
   and a small Alert_State__c (E11).
5. Permission Sets: Donations_Integration, Donations_Admin, Donations_Staff, Donations_Site_Guest per B2.7 + Part C rule 7
   (Opportunity CRUD, Record Type assignment, FLS for new fields; Token/Tax-Id access exactly as in B2.7).
   If docs/org-discovery.md calls for it, add Custom Permission Donations_Bypass_Automation to Donations_Integration only.
6. Validation rule on Charge__c (VR_Charge_Immutable_After_Final).
7. List Views per B2.8 (Opportunity ones filtered by record type; never filter on an encrypted field).
8. Named Credential Cardcom + External Credential Cardcom_EC metadata WITHOUT secret values (B3.1). Document the manual
   Principal parameter entry and the sandbox test terminal values from B5.0א in the README (public test creds only).

Already done in Prompt 1 [v2.2]: Cardcom_Setting__mdt exists with Min_Amount__c, Max_Amount__c, Integration_User_Id__c and the Default
record — add the remaining B2.6 fields and extend the Default record, don't recreate it. Relationship names used by Prompt 1's layout and
record page: Charge__c.Pledge__c → Charges, Pledge_Change_Log__c.Pledge__c → Pledge_Change_Logs (spec-consistency N19). Discovery found
no automation that needs Donations_Bypass_Automation, so don't create it.

Acceptance: extend MetadataSmokeTest to cover the new objects/fields (including isFilterable() of Pledge_Card_History__c.Token__c);
README manual-steps updated; no secrets in the repo.
```

## Prompt 3 — Cardcom client, LowProfile, intake, contact matching, activation (T10–T16) (plan mode)

```
Implement the intake pipeline: the form's backend through donor matching and pledge activation.
Spec: B3, B4, B5.1–B5.3, B5.8–B5.9, B6.1–B6.4, B6.13 (E1–E7), Part A 7.3/7.4/7.4א/7.5/7.7ב/7.7ג as referenced by B, plus Part C.

Classes (each with tests):
- CardcomService (B5.9 verbatim) + CardcomMock (HttpCalloutMock with per-path scripted/queued responses) + TestDataFactory
  (pledge() creates an Opportunity of the Micro_Donation_Pledge record type; contact(); charge(); settings()).
- DonationLowProfileResource (/donations/lowprofile) and DonationPledgeResource (/donations/pledge): the pledge is an Opportunity;
  set Name/CloseDate/StageName per C1; use ContactMatcher.validIsraeliId (E4); keep FOR UPDATE idempotency and LP_ALREADY_USED.
- CardcomWebhookResource, Cardcom_Lp_Event__e trigger + PlatformEventSubscriberConfig, CardcomLpResultJob, PendingVerificationSweeper
  (queries scoped to the record type; Lp_Check_Count__c ≥ 6 → StageName Verification_Failed).
- ContactMatcher (+ ContactNormalizationTrigger, ContactNormalizationBatch) exactly per 7.4א, with the B6.4 Review_Reason append.
  [v2.2] ID matching uses Contact.Tax_Id_Hash__c only; Donor_Tax_Id__c is selected, never filtered (E16).
- PledgeActivationService/PledgeActivationJob: on activation set Donor_Contact__c, Match_Method__c, StageName='Active',
  Activated_At__c, Start_Date__c, CloseDate=activation date, AND insert an OpportunityContactRole (Donor, primary) if none exists.
- Matching Rule + Duplicate Rule metadata (B6.4) — deployed AFTER the normalization batch; document that ordering in the README.
- [v2.3] External Client App WP_Donations (Part C D27, replaces B3.2's Connected App: Client Credentials Flow, Run As the integration
  user, scope api, IP restrictions) / Site / Guest profile: metadata where possible (ExternalClientApplication + its OAuth settings and
  policies, never the consumer secret), otherwise precise manual steps in the README (B3.2, B3.3).

Already in place from Prompt 2 [v2.3]: Cardcom_Lp_Event__e has only LowProfileId__c (publish without Log_Id__c, N1); the guest
PS can create the event (N28); Donations_Integration has the Cardcom_EC principal. Add classAccesses for every class you create to
Donations_Integration (and CardcomWebhookResource to Donations_Site_Guest).

Constraints: callouts before DML in every Queueable; the webhook trusts only the LowProfileId; Named Credential merge-field
placeholders are never replaced in Apex; no real HTTP.

Tests required (minimum): matcher by email/phone/taxId (hash), conflict → Needs_Review, no-overwrite, multiple candidates; submit→webhook order
and webhook→submit order both end Active exactly once; webhook ×3 is a no-op after the first; Verification_Failed after 6 checks;
replay → LP_ALREADY_USED; non-micro Opportunities are never selected or modified.

Acceptance: all tests pass locally (scratch org only if I authorize), ≥90% coverage on these classes, B11 TC01–TC10 mapped to tests or to manual steps in docs/acceptance.md.
```

## Prompt 4 — Calendar, holidays, scheduling and settings (T30, T31)

```
Implement B6.6, B9, B9.1, B9.2 + errata E5–E7.

- HebrewHolidays (B6.6 algorithm) with HebrewHolidaysTest containing the 2026/2027 date sets and RH 5785–5790 from B6.6/B8 (100% coverage).
- ChargeCalendar: holidays() (auto-detect + Charge_Holiday__mdt override), dow, isRestDay, isEve, logicalDatesFor,
  fridayCutoffHour, isRetryWindowOpen, shouldRun(kind,date), nextWorkingMorning(datetime) — signatures/semantics per E5.
  ChargeCalendarTest must contain the whole multiplicity table from B6.6 plus shouldRun cases from B8 and Remove_Rest_Day override.
- ChargeSettings (validate, hm, cron, defaults) and DonationSetup (scheduleAll, reschedule, unscheduleAll, applyScheduleInvocable),
  DonationChargeScheduler(String kind) honoring Charging_Enabled__c and Runs_Per_Day__c (=1 → no PM/EvePM; TwiceDaily pledges
  are then charged once). Use SUN-FRI crons; shouldRun decides.
- Flow Apply_Charge_Schedule (screen flow) metadata + Custom Permission gate.
- ChargeSettingsTest and DonationChargeSchedulerTest per B8.

Acceptance: the calendar tests are the contract — they must pass before anything else uses the calendar.
Report any date in B6.6 that your implementation disagrees with (do not "fix" the spec table silently).
```

## Prompt 5 — Charge engine (T32–T36) (plan mode)

```
Implement B6.5, B6.5.1–B6.5.3, B6.7 (retry part), Part A 7.7א for lock/retry scheduler, adapted by Part C.

- ChargePlanner.plan(Date, String slot): [v2.2] SOQL selects ONLY Opportunities of record type Micro_Donation_Pledge with
  StageName='Active' and (End_Date__c = null OR End_Date__c >= :runDate) — NO Token__c condition in the SOQL (E15). Select Token__c
  and skip rows with String.isBlank(Token__c) in Apex (log them; VR_Active_Requires_Token should make this impossible).
  Charge_Amount__c snapshot into Charge__c.Amount__c; Database.insert(allOrNone=false); duplicate Attempt_Key ignored.
- ChargeDispatcher, ChargeQueueable, ChargeRetryPolicy, ChargeRunLock, ChargeRetryScheduler (minute from Charge_Settings__c).
- ChargeOutcomeHandler and ChargeErrorClassifier (B6.5.2/B6.5.3 verbatim), including ALREADY_CHARGED/Verify_Attempt_Key__c flow and
  the Charge_Success__e publish. Last4 update goes to the Opportunity field Last4__c.
- ChargeTrigger on Charge__c (calls PledgeRollupService in Prompt 6 — create the class stub with a TODO and a failing-safe no-op now).
- StaffAlertService.configErrorOncePerDay (E11) minimal version.

Hard constraints: no DML before callouts within a Queueable; ExternalUniqTranId sent to Cardcom = Attempt_Key__c with
ExternalUniqUniqTranIdResponse=true; no Document block in the charge body; Config errors don't create retries nor count in streaks;
Card_Dead is a final failure for that logical charge only and later scheduled charges still run (D11/D12).

Tests (B8 "ChargeOutcomeHandlerTest" and B11 TC11–TC21 as unit tests with CardcomMock): success; Card_Dead final; Config no retry;
Retryable A1→A2 (+60m)→A3 (+240m)→final; retry that would fall on Shabbat/Friday-after-cutoff lands on the next working morning;
timeout → Unknown + Needs_Reconciliation + next attempt carries Verify_Attempt_Key__c; verify finds success → ALREADY_CHARGED and no
Transaction call; Stopped pledge → Skipped STOPPED; [v2.2] an Active pledge with a blank token is skipped by the planner without failing
the batch; 2,500 pledges × 2 dates planning stays inside limits (use Test with bulk 200+ and reason about the rest).

Acceptance: all tests green, coverage ≥95% on ChargeQueueable/OutcomeHandler/Planner, docs/acceptance.md updated with TC11–TC21 manual steps for the Cardcom test terminal.
```

## Prompt 6 — Roll-ups, alerts, manual stop/resume/cancel (T45–T47)

```
Implement B6.7 (roll-ups and streak), B6.8, B6.9.4, B2.8 actions, Part A 7.8/7.8א adapted by Part C.

- PledgeRollupService.recalc(Set<Id>) on Opportunity: Total_Collected__c (+ mirror to standard Amount, D25), Successful_Charge_Count__c,
  Last_Successful_Charge_Date__c, Consecutive_Failures__c (logical charges, Skipped neutral, pending logical charges not counted),
  Failure_Alert_Sent_At__c once per streak; NEVER changes StageName (D9).
- PledgeFailureAlert/StaffAlertService (all methods from E11 incl. Daily schedulable) with the HTML templates in B6.9.4; EmailUtil.
- OpportunityTrigger + OpportunityTriggerHandler (record-type guarded): on StageName Active→Stopped/Cancelled mark Pending Charges
  Skipped (STOPPED) and write Pledge_Change_Log__c for every stage transition.
- Flows: Stop_Pledge_Charges, Resume_Pledge_Charges, Cancel_Pledge, Revoke_Donor_Links (Link_Version__c +1 + log) as screen flows on
  Opportunity; Quick Actions + Dynamic Actions on Pledge_Record_Page gated by $Permission.Stop_Pledge_Charges.

Tests: B8 PledgeRollupServiceTest and PledgeTriggerHandlerTest scenarios (3 failures → one alert; 4th → none; success resets; Skipped does not
break streak; user without permission blocked by VR; Cancelled cannot be reopened; non-micro Opportunities unaffected).

Acceptance: green tests; this completes the core scope of the 40-hour quote. STOP here and give me a status report with hours-equivalent estimate before Prompt 7.
```

## Prompt 7 — Nightly reconciliation (T48) (scope extension — only after approval)

```
Implement B6.12 ReconciliationJob with the fixes in Part C (SF_Amount__c, Charge_Settings__c.Reconcile_Time__c), Recon_* CMDT fields,
LogCleanupBatch (Cardcom_Webhook_Log__c and Raw_* fields > 90 days), Report/List View for Reconciliation_Issue__c, and
[v2.2] wire up and test the existing StaffAlertService.reconciliationOpen() from Prompt 6 (don't re-create it).
Tests: each Issue_Type, the auto-fix Failed(Unknown)→Success via GetTransactionByExternalUniqTran, Duplicate_In_Cardcom, idempotent re-run (Issue_Key__c),
paging with pageSize boundary (rows.size() == pageSize), Recon_Report_Unknown__c=false.
Acceptance: green tests, coverage ≥90%.
```

## Prompt 8 — Thank-you email, signed donor links, donor-portal API, card change (T55, T56) (plan mode)

```
Implement B6.9 (all subsections), B6.10, B6.10.1, B4 /donor/* contract, adapted by Part C.

- DonorChargeEmailService + Charge_Success__e trigger/subscriber: batching per pledge per run, OrgLimits SingleEmail guard (B6.9.5),
  Custom Labels for org name/contact/signer, Donor_Charge_Thanks HTML (B6.9.3). Read donor data from the Opportunity
  (Donor_Contact__r, Donor_First_Name__c, Last4__c, Link_Version__c).
- DonorLinkToken (HMAC, no expiry, Link_Version__c revocation, Previous_Secret__c rotation), DonorLinkLog (buffered flush).
- DonorPortalResource (/donor/*), CardChangeService, Card_Change_Request__c sweeper expiry. Charge_Amount__c changes via /donor/amount
  (applies to charges created after the change, D16; existing Pending Charges keep their snapshot).
- Optional verify-on-open (B6.9.6) behind Optional_Verify_On_Open__c=false.

Tests: DonorLinkTokenTest (no exp claim, wrong version, wrong action, previous secret, status Stopped → invalid), DonorPortalResourceTest,
CardChangeServiceTest, DonorChargeEmailServiceTest (grouping, no email address, limit guard, Disabled setting), TC25–TC30.
Security check: grep the codebase and confirm no PAN/CVV fields exist, no secret/token is logged (System.debug) anywhere, and
[v2.2] no SOQL filters on Token__c or Donor_Tax_Id__c.
```

## Prompt 9 — Monthly receipt (T60) (scope extension; blocked on accountant + Cardcom answers Q14/Q15)

```
Implement B6.11 and B6.11.1 exactly: MonthlyReceiptScheduler, MonthlyReceiptPlanner (Batch), MonthlyReceiptQueueable, MonthlyReceiptService,
Monthly_Receipt__c flows (Retry_Receipt action + MonthlyReceiptRetryAction invocable), List View "failed receipts",
[v2.2] and wire up and test the existing StaffAlertService.receiptFailures() from Prompt 6 (don't re-create it).
Defaults are fixed by B5.10: Receipt_Link_Deal_Numbers__c=false → body uses top-level Cash = total; DealNumbers only when the flag is on;
Document.Languge='he'; Document.ExternalId = Receipt_Key__c; one Products line equal to the total.
Donor lookups come through the Opportunity (Donor_Contact__c, Donor_Tax_Id__c fallback) as in buildRequest.
[v2.2] The Donor_Tax_Id__c fallback must not filter on the encrypted field (E16): query the donor's pledges (record-type guarded,
Donor_Contact__c = :id, ORDER BY Activated_At__c DESC) selecting Donor_Tax_Id__c, and pick the first non-blank value in Apex.

Tests per B8 MonthlyReceiptTest including: two pledges (two Opportunities) of one Contact → one receipt; no charges → no record;
idempotent rerun; day-1-on-Shabbat → next working day; validation error → Failed final; timeout → retryable; Max attempts reached → no send;
[v2.2] tax-id fallback picks the pledge value when the Contact's is blank.
Do not call Cardcom for real. Add docs/receipt-go-live-checklist.md from the five checks at the end of B6.11.
```

## Prompt 10 — WordPress plugin org-donations (T20–T29)

```
Implement B7 in wordpress/org-donations exactly as written: bootstrap, Org_SF_Client, Validator, Rate_Limiter, Org_Form + template,
donation-form.js/css, Return endpoint (/cardcom-return/), Org_Portal + portal template + donor-portal.js, uninstall.php, install guide (B7.15).

Rules:
- PHP ≥ 8.0, WP ≥ 6.2, RTL, WCAG-friendly labels/roles as in the templates; no client secret or Salesforce token in any front-end output.
- The Salesforce payload names are unchanged by Part C (the Opportunity is internal to Salesforce).
- Add PHPUnit tests for Org_Validator (phone, Israeli ID, amount rules) and for the rate limiter; add a JS test (or documented manual checks)
  for estimate() and validId().
- Add an admin Settings page ONLY if trivial; otherwise keep constants in wp-config.php (B7.3).
- Produce docs/wp-cache-exclusions.md covering WP Rocket / LiteSpeed / Cloudflare (B7.14) and the sandbox attribute risk note in B7.9.
- Deliver a zip build script (scripts/build-plugin.sh).

Acceptance: php -l clean, PHPUnit green, manual test script in docs/acceptance.md (TC01, TC05–TC07 and the portal flows).
```

## Prompt 11 — Reports, dashboard, list views (T64) (scope extension)

```
Build the Reports and the "תרומות מיקרו" Dashboard from the spec chapter 8 (client doc) and B2.8/B11, in folder Donations:
custom report types (Opportunity with Charges; Contact with Opportunities and Receipts), reports: contacts needing review, failed charges,
repeated failures, stopped pledges, donor changes, monthly receipts, collected this month (from Charge__c Success by Run_Date__c),
daily charges by status, open reconciliation issues, duplicates, new donors; Dashboard with the 7 tiles.
All Opportunity-based reports filter on Record Type = Micro_Donation_Pledge; no report filters on encrypted fields.
Report "Success charges without a monthly receipt" (E17-style) included.
Metadata only; document any component that needs manual creation.
```

## Prompt 12 — Hardening, acceptance run book, deployment pack (final)

```
Final pass over the whole repo.
1. Run every Apex test locally/in a scratch org ONLY if I authorize; otherwise produce the exact command list.
2. Static review: (a) no SOQL/DML in loops, (b) every query on Opportunity has the record-type guard, (c) callouts-before-DML everywhere,
   (d) no secrets/PAN, (e) all strings Hebrew where the spec says Hebrew, (f) all names match Part C canonical names,
   (g) [v2.2] no filter/match on encrypted fields anywhere (SOQL, reports, list views, matching rules).
3. Re-read docs/spec-consistency.md and close every item; update CLAUDE.md Part C with any new decision you had to make.
4. Produce docs/deployment-runbook.md following B10 with Opportunity adjustments (StandardValueSet retrieve-and-merge first per E14,
   then Record Type/Sales Process, Opportunity fields before Charge__c lookups), including rollback (DonationSetup.unscheduleAll(),
   disabling the shortcode, deactivating the record type).
5. Produce docs/acceptance.md: B11 TC01–TC40 as a table with Automated(test name) / Manual(steps) / Blocked(which open question).
6. Produce docs/open-questions.md from B14 + Part C4 with owner (client / Cardcom / Yosef) and what each blocks.
7. Estimate actual effort per work package vs the 40-hour quote (B1/B13) for the client change-request conversation.
```
