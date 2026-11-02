# Org discovery (Prompt 0)

**Status: not run yet.** No target org is connected to this repo, so nothing has been queried. The checks below are ready to run
read-only with [`scripts/org-discovery.sh`](../scripts/org-discovery.sh). Fill the "Finding" column from its output, then work through
the risk list before Prompt 1 deploys anything.

Known so far:
- **NPSP is not installed** (confirmed 2026-11-02, Part C D26). No NPSP/TDTM bypass is needed.

## How to run

```bash
sf org login web --alias donations-target --instance-url https://<org>.my.salesforce.com
```

```bash
scripts/org-discovery.sh donations-target
```

The script only queries, describes and retrieves into `discovery/` (git-ignored). It never deploys or writes data.
Two items are not available through the API and are checked by hand in Setup: Email Deliverability level and the encryption option
(Shield Platform Encryption vs Classic Encrypted Text).

## Checklist

| # | Check | Source in script output | Finding |
|---|---|---|---|
| 1 | NPSP (`npsp__`) installed | `packages.csv` | **No** (D26) |
| 2 | Other managed packages that hook Opportunity/Contact | `packages.csv`, `triggers-*.csv` / `flows-active.csv` with `NamespacePrefix` | |
| 3 | Person Accounts enabled | `summary.txt` | |
| 4 | `Opportunity.AccountId` required at API level / by a VR | `summary.txt`, `vr-Opportunity.csv` | |
| 5 | Org default currency is ILS; multi-currency on/off | `org.csv`, `summary.txt` | |
| 6 | Existing Opportunity record types | `opp-recordtypes.csv` | |
| 7 | Existing Sales Processes and stages | `opp-salesprocesses.csv`, `opp-stages.csv`, `retrieve/…/OpportunityStage.standardValueSet-meta.xml` | |
| 8 | Any of `Pending_Verification`, `Active`, `Stopped`, `Cancelled`, `Verification_Failed` already a stage (E14) | `opp-stages.csv` (compare case-insensitively) | |
| 9 | Opportunity fields already history-tracked (limit 20; Part C adds 6) | `opp-history-fields.csv` | |
| 10 | Required-on-create fields (Opportunity, Contact) | `summary.txt` | |
| 11 | Validation rules (Opportunity, Contact, OpportunityContactRole) | `vr-*.csv` | |
| 12 | Apex triggers (Opportunity, Contact, OpportunityContactRole) | `triggers-*.csv` | |
| 13 | Record-triggered flows and Process Builders | `flows-active.csv` | |
| 14 | Workflow rules | `workflow-*.csv` | |
| 15 | Duplicate / matching rules on Contact and Opportunity (any **Block** action?) | `duplicate-rules.csv`, `retrieve/…/matchingRules` | |
| 16 | OWD for Account, Contact, Opportunity (record only; do not change — C2 rule 5) | `sharing.csv` | |
| 17 | Org-Wide Email Addresses | `owea.csv` | |
| 18 | Email Deliverability level | Setup → Deliverability (manual) | |
| 19 | Encryption: Shield available, or Classic Encrypted Text | Setup → Encryption Settings (manual) | |
| 20 | Integration user exists; TimeZone = Asia/Jerusalem; license grants Opportunity CRUD | `int-users.csv` | |
| 21 | Translation Workbench enabled, Hebrew (`iw`) active | `retrieve/…/Language.settings-meta.xml` | |
| 22 | Org TZ, locale, language | `org.csv` | |

Assignment and escalation rules apply to Leads and Cases, not Opportunities, so they are out of scope.

## Risk list and plan

Part C rule 4: existing automation must not break the integration user's inserts, and must not act on pledge Opportunities. The default
plan is to **scope by record type first** and fall back to a bypass Custom Permission only where scoping isn't possible.

The bypass, if needed, is a Custom Permission `Donations_Bypass_Automation`, granted only through the `Donations_Integration` permission
set, and checked as `$Permission.Donations_Bypass_Automation` in flow entry conditions and validation rules (`Not` it into the condition).
It is created in Prompt 2 only if discovery finds something that needs it.

| # | Risk | Why it matters here | Plan |
|---|---|---|---|
| R1 | **"Closed Won" automation** (flows, Process Builders, workflow rules, triggers) | `Active` and `Stopped` are `IsWon = true`. Every pledge activation would look like a won deal: welcome emails, invoices, tasks, Slack/Chatter posts, quota credit. | Add `RecordType.DeveloperName != 'Micro_Donation_Pledge'` to each entry condition. For managed automation that can't be edited, test in sandbox and document. |
| R2 | Record-triggered flows / triggers on Opportunity insert/update | Fire on every webhook, activation and roll-up update (roll-ups update the Opportunity after every charge, up to ~5,000 updates/day at 2,500 donors). CPU and SOQL limits inside charge Queueables. | Same record-type guard. Flag any automation that does callouts or sends email. |
| R3 | Validation rules on Opportunity / Contact | Can reject integration inserts (e.g. required `Type`, `LeadSource`, `NextStep`, AccountId). | Record-type exclusion on Opportunity VRs; bypass permission on Contact VRs if needed. |
| R4 | Required-on-create fields | Inserts fail. | Set values in Apex only if they have an obvious default; otherwise list under Open issues and ask. |
| R5 | AccountId required by a VR or process | Pledge insert fails when `Default_Account_Id__c` is blank. | Set `Cardcom_Setting__mdt.Default_Account_Id__c`, or exclude the record type. |
| R6 | Stage value collision (E14) | Re-using an existing `Active`/`Cancelled` value would change its meaning in other sales processes. Deploying a partial StandardValueSet would remove existing stages org-wide. | Retrieve the full set, add the 5 values, review the diff before any deploy. If a value exists, stop and decide with Yosef. |
| R7 | Field History limit | Deploy fails if tracked fields exceed 20. | Count first; drop the lowest-value Part C tracked field if needed and record it. |
| R8 | Duplicate rules with **Block** on Contact | `ContactMatcher` uses `allowSave = true`, which does not override Block. Donor creation would fail. | Add a condition excluding the integration user, or switch to Alert. |
| R9 | Contacts without Account are private | With Contact OWD "Controlled by Parent", a Contact with no Account is visible only to its owner (the integration user) and admins. Staff wouldn't see donors. | Set `Default_Account_Id__c` to a shared "Micro donors" Account, or confirm admins-only visibility is acceptable. Ask the client (Q1). |
| R10 | Forecasting / quotas | Won pledges with `Amount` = total collected (D25), owned by the integration user, enter forecasts. | Confirm with the client; exclude the record type from forecast types if forecasting is on. |
| R11 | Currency | `Charge_Amount__c` and `Amount` assume ILS. | If the org default isn't ILS or multi-currency is on, set `CurrencyIsoCode = 'ILS'` on insert and record it. |
| R12 | Integration license scope | The Salesforce Integration license must grant Opportunity access. | Verify the license/permission set license before Prompt 2's permission sets. |
| R13 | Encryption option | Classic encrypted fields are not filterable and max 175 chars; Shield probabilistic is also not filterable. | Already handled by E15/E16; `MetadataSmokeTest` records `isFilterable()`. |
| R14 | OpportunityContactRole automation / "primary contact role required" | Activation inserts an OCR (Role `Donor`, primary). | Check OCR triggers/flows/VRs (`*-OpportunityContactRole.csv`). |
