# Production deployment

The complete path from this repo to the client's production org. It builds on `docs/deployment-runbook.md` (order, phases,
rollback) and the manual steps in `docs/README.md` ("README n"). Hebrew checklist: `docs/production-checklist-he.md`.

Every command marked **(org change)** changes production. Run it only when you mean to, outside the charge times
(06:00, 08:00, 11:00, 20:00 and the hour before each).

## What the deploy carries, and what it doesn't

| Component | How it gets to production |
|---|---|
| Apex classes (incl. 32 test classes), triggers | deploy (`build/prod`) |
| Custom objects, fields, validation rules, list views, compact layout (Contact, Opportunity, 8 custom objects) | deploy |
| Platform events (3), custom settings (`Charge_Settings__c`, `Charge_Run_Lock__c`, `Alert_State__c`) | deploy; **Org Default data**: `scripts/apex/init-settings.apex` |
| Custom metadata types + records: 17 `Cardcom_Error_Code`, `Cardcom_Setting.Default` | deploy; `Cardcom_Setting.Default` filled from `config/prod-values.local.json` |
| `Donor_Link_Setting.Default` (donor-link secret) | deploy **first install only** (empty), then the secret in Setup (README 8). Never redeployed. |
| Standard value sets `OpportunityStage` (+5 stages), `ContactRole` (+Donor), `OpportunityType` (+Daily Donation Pledge) | deploy, **merged with production's own sets** by the build (E14) |
| Custom labels (org name, contact phone/email, signer, impact sentence in donor emails) | deploy, filled from the values file (`labels`) |
| Hebrew translations (11 objects, report-type sections, value sets) | deploy; Translation Workbench on with Hebrew active first (README 4) |
| Permission sets (5), custom permissions (`Stop_Pledge_Charges`, `Manage_Charge_Schedule`) | deploy; **assignment** by hand (README 14) |
| Screen flows (8, Active), quick actions (6) | deploy |
| Layouts `Micro Donation Pledge Layout`, `Monthly Receipt Layout`; record page `Pledge_Record_Page` | deploy; **assignment/activation** by hand (README 16, 17) |
| Email template folder `Donations` / `Donor_Charge_Thanks` | deploy |
| External Credential `Cardcom_EC`, Named Credential `Cardcom` | deploy (no secrets); ApiName/ApiPassword by hand (README 7) |
| Matching rule `Donor_Contact_Match`, duplicate rule `Donor_Contact_Duplicate` | deploy **inactive**; activate after normalizing Contacts (README 21) |
| Report types (4), report folder `Donations` (13 reports), dashboard | deploy; folder sharing by hand (README 25) |
| Platform event subscriber configs (3) | `scripts/deploy-pe-subscriber.sh` (needs the integration username) |
| Scheduled jobs (13) | `scripts/apex/schedule-donations.apex` (run as integration user via D30) |

**Not deployed, by design:**

- **Profiles.** The repo never deploys profiles (`.forceignore`): a profile file overwrites the org's settings for that profile.
  Access comes from the permission sets. The four profile-bound settings are set by hand:
  - layout assignment;
  - record page activation;
  - the integration user's default Opportunity record type (only if production has record types);
  - the app utility bar.
- **Record type `Micro_Donation_Pledge` and sales process `Micro_Donation_Process`.** They are legacy (D34); no code uses them. The
  build leaves them out, together with their translation. Use `--with-record-type` only if production has no usable Opportunity
  record type and you decide to add one; it then needs a sales process with **all** stages (README 15).
- **The Contact page layout** and the Lightning app (utility bar). Deploying them would overwrite the org's own versions.
  In the sandbox they were edited by hand (Contact Layout 3.11, LightningSales 3.11); repeat by hand in production (step 5 below).
- **External Client App `WP_Donations`, Site `cardcom`, Org-Wide Email Address, DKIM, integration user.** Created in Setup
  (org-specific users and keys).
- **Data.** No pledges, charges or settings data move from the sandbox.

## 0. Prerequisites in production (by hand, before any deploy)

1. **Discovery** (README 1): `scripts/org-discovery.sh <prod-alias>`. Read-only. Check:
   - Opportunity automation and required fields (R1, R2);
   - Opportunity record types (R3);
   - the standard Contact duplicate rule (R5, must not Block).
2. **Integration user** (README 6):
   - Salesforce Integration license plus the "Salesforce API Integration" permission set license;
   - TZ **Asia/Jerusalem**, locale he_IL;
   - put its 18-character Id in the values file.
3. **Record types on Opportunity.** If production has Opportunity record types, the integration user's default one must allow:
   - the 5 pledge stages in its sales process;
   - `Type = Daily Donation Pledge`;
   - the values of `Frequency__c`, `Stop_Reason__c` and `Match_Method__c`.

   Otherwise inserting a pledge fails ("bad value for restricted picklist"). Add the values on the record type after the deploy
   (step 5). With no record types (Master), nothing is needed.
4. **Translation Workbench** on, Hebrew active (README 4). Without it, build with `--no-translations`.
5. **Field history** on Opportunity (README 3) and at most 20 tracked fields in total, or build with `--no-history`.
6. **Deployment settings:** "Allow deployments of components when corresponding Apex jobs are pending or in progress" (README 23).
7. **Email:**
   - Deliverability = All email;
   - verify the Org-Wide Email Address;
   - DKIM key active for the sending domain (runbook "Production only").
8. **Cardcom:** the client's terminal has the Tokens and Documents modules, and no CVV is required for token charges (README 7).
9. **Values file:** `cp config/prod-values.example.json config/prod-values.local.json` and fill in every `<…>`. Never commit it
   (`.gitignore`); it holds no passwords. The build refuses to run while a required value is empty or still a placeholder.

## 1. Build the production folder (local, no org change)

```bash
sf project retrieve start --target-org <prod-alias> --manifest manifest/retrieve-standard-value-sets.xml --output-dir build/prod-svs
```

```bash
python3 scripts/prod/build-prod.py --org-svs build/prod-svs --values config/prod-values.local.json --first-install
```

The build output shows the production stages it kept, the values it added and anything it left out.

- **Stop condition:** it stops if one of the 5 stages already exists in production (E14). Decide with the client before going on.
- **Optional flags:** `--no-translations`, `--no-history`, `--with-record-type`.
- **Output:** `build/prod/force-app`, `build/prod/manifest/package.xml` and `build/prod/tests.txt`.

**Later releases:** run the build without `--first-install`, so the donor-link secret is never sent. Use `--skip-svs` when the value
sets didn't change. Run it without `--values` to keep the Cardcom settings and labels that admins changed in Setup.

## 2. Validate (check-only, no org change)

```bash
scripts/prod/deploy-prod.sh <prod-alias> validate
```

Runs the project's 32 test classes (`RunSpecifiedTests`) and prints a job id.

- **Typical first-run failures:**
  - org-specific report or dashboard settings;
  - a required field or validation rule on Opportunity/Contact that the test data doesn't fill (discovery R1/R2);
  - an active Contact duplicate rule that Blocks (R5).

  Fix the cause in the org or in the repo, then build and validate again.
- **Coverage:** production needs 75% per deploy; the project tests cover its own classes.

## 3. Deploy (org change)

```bash
scripts/prod/deploy-prod.sh <prod-alias> quick <job-id>
```

The quick deploy has to run within 10 days of the validation, with no deploy in between.

**Redeploys** (jobs already scheduled): `DonationSetup.request('UNSCHEDULE_ALL');` first, then `'SCHEDULE_ALL'` after the deploy
(runbook step 3).

## 4. Right after the first deploy (by hand)

1. **Donor-link secret** (README 8). Setup → Custom Metadata Types → Donor Link Setting → `Default`:
   - `Secret__c` = 64 random hex characters (`openssl rand -hex 32`);
   - never reuse the sandbox secret.
2. **Cardcom credentials** (README 7). External Credential `Cardcom_EC` → principal `CardcomTerminal`: the client's ApiName and
   ApiPassword.
3. **Custom-setting defaults** (org change): `sf apex run --target-org <prod-alias> --file scripts/apex/init-settings.apex`. Then
   check Charge Settings → Org Default:
   - `Receipt Day Of Month` = 2;
   - `Charging_Enabled__c` = **false** until go-live (step 8).
4. **External Client App `WP_Donations`** (README 10):
   - enable the JWT Bearer flow (D31) with the production certificate;
   - pre-authorize the integration user;
   - IP restrictions for the WP server.
5. **Site `cardcom`** (README 11):
   - assign the guest permission set;
   - put the Site's domain in `Webhook_Url__c`.
6. **Permission sets** (README 14):
   - `Donations_Integration` → integration user;
   - `Donations_Admin` → finance/data managers;
   - `Donations_Staff` → fundraising staff;
   - `Donations_Site_Guest` → the Site guest user;
   - `Donations_Internal_Read` → read-only users (optional).
7. **Platform event subscribers** (org change): `scripts/deploy-pe-subscriber.sh <prod-alias> <integration-username>`. Then check
   that `Charge_Success__e` is "Publish After Commit" (runbook 5.2).

## 5. Layouts, pages, actions and buttons (by hand)

1. **Opportunity layout** (README 16). Page Layout Assignment:
   - either assign `Micro Donation Pledge Layout` to the record type that pledges use,
   - or add the pledge section and the 4 actions to the org's existing layout.

   Mind other profiles' regular Opportunities.
2. **Record page** (README 17). Lightning App Builder → `Pledge_Record_Page` → Activation:
   - assign it as org default or app default for the Opportunity record type that pledges use;
   - the pledge components and actions show only when `Type = Daily Donation Pledge`.
3. **Opportunity actions** (if the org's layout is kept), in "Mobile & Lightning Actions":
   - `Stop_Charges`, `Resume_Charges`, `Cancel_Pledge`, `Revoke_Donor_Links`;
   - they are gated by `Stop_Pledge_Charges`.
4. **Contact layout** (README 19):
   - a "תורם מיקרו" section;
   - the related list "הוראות תרומה יומית";
   - the action `Plan_Monthly_Receipt` ("הפקת קבלה חודשית") in Mobile & Lightning Actions.
5. **Monthly Receipt layout:**
   - assign `Monthly Receipt Layout` (single layout, no record types);
   - the action `Retry_Receipt` is on it.
6. **Admins' Lightning app utility bar** (README 24): add the flows `Apply_Charge_Schedule` and `Plan_Monthly_Receipts_All`.
7. **Opportunity record type values** (if record types exist, step 0.3), on the record type the integration user uses:
   - the 5 stages in its sales process;
   - `Daily Donation Pledge` in `Type`.
8. **List views** are deployed (Opportunity, Charge, Receipt, Contact). Share them with the `Donations_*` groups if they should not
   be visible to everyone.

## 6. Data and jobs (org change)

1. **Normalize existing Contacts**, wait for the batch, then activate `Donor_Contact_Match` and `Donor_Contact_Duplicate` (README 21):
   `scripts/apex/normalize-contacts.apex`.
2. **Reports** (README 25):
   - share the `Donations` folder with the staff;
   - the dashboard is "logged-in user": viewers need the "View Dashboards"-type access their profile gives;
   - build the duplicates report by hand.
3. **Schedule the jobs:** `scripts/apex/schedule-donations.apex`. Check Setup → Scheduled Jobs:
   - 13 `Donations …` jobs, submitted by the integration user;
   - the staff email "זמני חיוב עודכנו".

## 7. WordPress (production site)

`docs/wp-install.md`.

- **`wp-config.php`:** production `ORG_SF_LOGIN_URL = https://login.salesforce.com`, the ECA Client ID, the integration username and
  the production key path.
- **Cache exclusions:** `docs/wp-cache-exclusions.md`.
- **Pages:** `[org_donation_form]` and `[org_donor_portal]`.
- **Salesforce side:** `Allowed_Return_Hosts__c` / `Donor_Portal_Base_Url__c` must match the site.

## 8. Go-live

1. Close the open items in `docs/open-questions.md` marked "blocks go-live".
2. Pass `docs/receipt-go-live-checklist.md` against the client's terminal.
3. **Controlled first pledge.** One real pledge by a staff member with a small amount, while `Charging_Enabled__c` is still false:
   - the pledge becomes Active;
   - Contact matching is correct;
   - there is no email from Cardcom.
4. **Turn charging on.** Set `Charging_Enabled__c = true` before a regular (not eve) morning run. Watch the first run:
   - the Charge records;
   - the thank-you email;
   - the reconciliation next night (runbook "Production only").

## Not to carry over from the sandbox

- Remote Site `Tmp_Self_Metadata_Deploy` (temporary).
- The 18 test pledges and their test-terminal tokens.
- Contacts such as avi@fried.com.
- The sandbox values of `Cardcom_Setting.Default` (Site URL, return hosts, `example.org` addresses): production values come only from the values file.
