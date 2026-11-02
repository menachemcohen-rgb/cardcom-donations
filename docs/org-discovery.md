# Org discovery (Prompt 0)

**Status: run read-only on 2026-11-02 against the Ato Dev sandbox** through the Salesforce connector (REST and Tooling SOQL only;
nothing was deployed or written).

| | |
|---|---|
| Org | Association of Yeshiva Students – Torah and Social Activities for Students |
| Instance | `associationofyeshivastudentstoraha--atosandbox.sandbox.my.salesforce.com` (ISR2S), **sandbox** |
| Edition | Enterprise Edition |

This is a sandbox. Re-run the same checks against production before the production deploy (B10); use
[`scripts/org-discovery.sh`](../scripts/org-discovery.sh) with an `sf` alias, which also retrieves the metadata snapshots that the
connector could not.

## Findings

| # | Check | Finding |
|---|---|---|
| 1 | NPSP (`npsp__`) | **Not installed** (D26; `PackageLicense` lists only `OIQ`, `omnistudio`, `sf_com_apps`). |
| 2 | Managed packages hooking Opportunity/Contact | **None.** No managed triggers, VRs or record-triggered flows on these objects. Platform flows from `PgmMgmt`, `industries_*`, `revcloud_*` etc. are present but none is record-triggered on Opportunity/Contact. |
| 3 | Person Accounts | **Disabled** (`Account.IsPersonAccount` does not exist). |
| 4 | `Opportunity.AccountId` required | Not required by any VR (there are none). The UI layout may still require it; API inserts are fine. |
| 5 | Currency | **Single currency** (`CurrencyType` not available). The org currency value itself isn't exposed by the API; confirm it is ILS in Setup → Company Information. |
| 6 | Opportunity record types | **None.** Every existing Opportunity uses the master record type. `Micro_Donation_Pledge` will be the first one. |
| 7 | Sales processes | **None.** `Micro_Donation_Process` will be the first. |
| 8 | Existing stages | 10 standard stages: Prospecting, Qualification, Needs Analysis, Value Proposition, Id. Decision Makers, Perception Analysis, Proposal/Price Quote, Negotiation/Review, Closed Won, Closed Lost. |
| 9 | Stage collision (E14) | **None.** None of `Pending_Verification`, `Active`, `Stopped`, `Cancelled`, `Verification_Failed` exists. The 5 values can be added to the existing set. |
| 10 | Opportunity field history | **0 fields tracked.** Part C's 6 fit within the limit of 20. |
| 11 | Validation rules (Opportunity, Contact, Account, OpportunityContactRole) | **None.** |
| 12 | Apex triggers (same objects) | **None.** |
| 13 | Workflow rules (same objects) | **None.** |
| 14 | Record-triggered flows and Process Builders | **Two relevant flows**, both unmanaged (see R1 and R2): `Create_New_Account_When_Creating_A_Contact` (Contact, after-save, create) and `Create_Opp_And_Tlush_After_Log_Created` (`Log__c`, after-save, creates Opportunities). No Process Builders. |
| 15 | Duplicate rules | Active standard rules: `Standard_Contact_Duplicate_Rule`, `Standard_Account_Duplicate_Rule`, `Standard_Lead_Duplicate_Rule`. None on Opportunity. Their action (Allow/Block) can't be read through the API; check in Setup (R5). |
| 16 | Org-wide defaults (record only; don't change) | Opportunity **Public Read Only**; Account **Public Read/Write**; Contact **Controlled by Parent**. |
| 17 | Org-Wide Email Addresses | One: `menachag@gmail.com` ("Ato Olami"), allowed for all profiles. |
| 18 | Email Deliverability | Not available through the API. Check Setup → Deliverability (sandboxes default to "System email only"). |
| 19 | Encryption | `TenantSecret` is not available, so **Shield Platform Encryption is most likely not enabled**. Plan on Classic Encrypted Text and confirm in Setup → Encryption Settings. E15/E16 already cover the filtering limits. |
| 20 | Integration user | **Doesn't exist yet.** Active users are 5 System Administrators plus the standard Sales Insights integration user. All are on Asia/Jerusalem. |
| 21 | Translation Workbench | Not checked through the API. Org language is `en_US` and locale `iw_IL`; enable Hebrew in Translation Workbench for the stage and record-type labels. |
| 22 | Org TZ / locale | Asia/Jerusalem, `iw_IL`, language `en_US`. |
| 23 | Existing custom fields | Contact has **`Israeli_Id__c` Text(9), unencrypted** (4 of 5 Contacts filled in). Opportunity has a custom **`Contact__c`** Lookup(Contact). See D-1 and D-2. |
| 24 | OpportunityContactRole `Role` values | Standard 9 values; **`Donor` does not exist** (confirms consistency finding N9). |
| 25 | Data volume (sandbox) | 5 Contacts (all with an Account), 6 Opportunities (5 Closed Won, 1 Prospecting). |

## Risk list and plan

Part C rule 4: existing automation must not break the integration user's inserts or act on pledge Opportunities. The org has very
little Opportunity automation, so **no bypass Custom Permission is needed**. Don't create `Donations_Bypass_Automation` in Prompt 2
unless production discovery finds more.

| # | Risk | Detail | Plan |
|---|---|---|---|
| R1 | **Contact flow creates a Household Account for every new Contact** | `Create_New_Account_When_Creating_A_Contact` has no entry condition: on every Contact insert it creates an Account named "{First} {Last} Household" and **overwrites `Contact.AccountId`**. It will run when `ContactMatcher` creates a donor. | Accept it. It also means donor Contacts are never private (Contact OWD is Controlled by Parent, Account is Public Read/Write). Any `AccountId` set by `ContactMatcher` will be overwritten. Decision D-3 covers what the pledge's `AccountId` should be. Tests must expect one extra Account per new donor. |
| R2 | **`Log__c` flow creates Closed Won Opportunities** | `Create_Opp_And_Tlush_After_Log_Created` (an existing payments/payslip process) finds the Contact by `Israeli_Id__c`, queries **all** Opportunities on that Contact's Account with no record-type filter, and creates a Closed Won Opportunity plus a `Tlush__c` when no `Tlush__c` is linked. | Pledges on the same Account will show up in its "Try To Find Opps" query. They have no linked `Tlush__c`, so the outcome is unchanged. Low impact, but our reports must filter on record type, and their Opportunity reports should exclude `Micro_Donation_Pledge`. Tell the org owner. |
| R3 | First Opportunity record type in the org | When the first record type is added in Setup, Salesforce can make it a profile's default. Regular Opportunities created by staff or by the R2 flow would then become micro-pledges. | Deploy the record type through metadata **without** profile assignments (`.forceignore` already excludes profiles). Grant it only through the `Donations_*` permission sets. After deploy, check that no profile's default Opportunity record type changed. |
| R4 | StandardValueSet (E14) | No collisions. | Retrieve the 10 existing stages, add the 5, deploy the full set. |
| R5 | Standard Contact duplicate rule | It is active. If its action on create is **Block**, `ContactMatcher`'s `allowSave = true` won't help and donor creation fails. | Check in Setup. The standard default is Allow + Alert, which is fine. If it is Block, switch it to Allow or exclude the integration user. |
| R6 | Opportunity OWD is Public Read Only | Every internal user can read every pledge, so FLS is the only protection for `Token__c` and `Donor_Tax_Id__c` (C2 rule 5). | Permission sets per B2.7. Make sure no profile grants FLS to these fields (they're new, so by default none does). |
| R7 | Email deliverability / OWEA | The sandbox likely sends system email only. The only OWEA is a personal Gmail address. | Set Deliverability to "All email" for the sandbox tests. Use a verified organisational address for production (Q8). |
| R8 | Shield likely absent | Classic Encrypted Text: max 175 characters, not filterable, masked by default. | Already handled by E15/E16; `MetadataSmokeTest` records `isFilterable()`. |
| R9 | OpportunityContactRole `Donor` role missing | Activation inserts an OCR with Role `Donor`, which would fail on a restricted picklist or create an unlisted value. | Add `Donor` to the OpportunityContactRole `Role` standard value set in Prompt 1, the E14 way: retrieve the whole set, add the value, never deploy a partial set. |
| R10 | Integration user doesn't exist | Needed for the Connected App Run As, scheduled jobs and the platform-event subscriber. | Manual step 5 in the README (Salesforce Integration license, Asia/Jerusalem). Check that the license's permission set license grants Opportunity access before Prompt 2. |
| R11 | Sandbox vs production | All findings are from the sandbox. | Re-run discovery on production before the production deploy. |

## Decisions needed (not in the spec)

These come from the org, not from `CLAUDE.md`, so they're open until Yosef decides. Until then, Prompts 1–3 follow the conservative
default shown.

| # | Question | Conservative default |
|---|---|---|
| D-1 | Contact already has an **unencrypted `Israeli_Id__c`**, which the `Log__c` flow uses to find Contacts. The spec adds a new encrypted `Donor_Tax_Id__c`. Reuse the existing field, or keep both? | Keep the spec: add `Donor_Tax_Id__c` (encrypted) and `Tax_Id_Hash__c`. Also: (a) `ContactNormalizationTrigger` computes `Tax_Id_Hash__c` from `Donor_Tax_Id__c`, **falling back to `Israeli_Id__c`** when the former is blank, so existing Contacts match by ID; (b) `ContactMatcher` never writes `Israeli_Id__c`. Raise with the client as part of Q13 (ID retention). |
| D-2 | Opportunity already has a custom `Contact__c` lookup (used by the `Log__c` flow). Part C uses `Donor_Contact__c`. Also fill `Contact__c` on pledges? | Don't fill it: `Donor_Contact__c` only, as Part C says. |
| D-3 | Pledge `AccountId`: the spec uses `Cardcom_Setting__mdt.Default_Account_Id__c` (else blank). In this org every Contact gets its own Household Account (R1). | Keep the spec: `Default_Account_Id__c`, empty by default, so `AccountId` stays blank. Alternative to propose: set `AccountId = Donor_Contact__r.AccountId` on activation, so pledges appear under the donor's household like the org's other Opportunities. |
