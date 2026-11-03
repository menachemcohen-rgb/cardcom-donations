# Deployment runbook (B10, adjusted for Part C)

Order follows `CLAUDE.md` B10 with the Opportunity changes of Part C: the `OpportunityStage` set is merged first (E14), then the
record type and sales process, then the Opportunity fields, before any object whose `Pledge__c` lookup points to Opportunity.
Every command below is a **real change to the org** — run it only when you mean to. Details of each manual step are in
`docs/README.md` ("Manual Setup steps"); the step numbers are referenced as **README n**.

`<alias>` = the target org alias. `<int-user>` = the integration username (README 6).

## 0. Before the first deploy (each org: sandbox first, then production)

1. **Re-run discovery** (README 1, 4, 5) on the target org (`scripts/org-discovery.sh <alias>`; production too, risk R11) and re-read
   `docs/org-discovery.md`: R1 (household-Account Contact flow), R2 (`Log__c` flow creating Opportunities), R3 (first Opportunity
   record type), R5 (standard Contact duplicate rule must not Block).
2. **Integration user** with the Salesforce Integration license, TZ **Asia/Jerusalem**, locale he_IL (README 6).
3. **Deployment settings:** "Allow deployments of components when corresponding Apex jobs are pending or in progress" (README 23).
4. **Email:** Deliverability = All email; a verified Org-Wide Email Address (README 12, R7).
5. Field history slots on Opportunity (README 3): at most 20 tracked fields including the org's existing ones.

## 1. Standard value sets — retrieve and merge first (E14)

```bash
sf project retrieve start --target-org <alias> --manifest manifest/retrieve-standard-value-sets.xml --output-dir /tmp/svs-check
```

Compare `/tmp/svs-check/.../OpportunityStage` and `ContactRole` with `force-app/main/default/standardValueSets/`. The repo files must
contain **every** value the org has plus the 5 stages (`Pending_Verification`, `Active`, `Stopped`, `Cancelled`, `Verification_Failed`)
and the `Donor` role (E18). If the org has values the repo lacks, add them to the repo file first — **never deploy a partial set**.
None of the 5 stages may already exist (case-insensitive); if one does, stop. Then:

```bash
sf project deploy start --target-org <alias> --source-dir force-app/main/default/standardValueSets force-app/main/default/standardValueSetTranslations
```

## 2. Check-only validation of everything

```bash
sf project deploy validate --target-org <alias> --source-dir force-app --test-level RunLocalTests
```

Fix what it reports (most likely: report column names, dashboard component settings, CRT field names — never verified in an org).
If the single validation is too big to read, validate in the phases of step 3 with `--test-level NoTestRun` until the last one.

## 3. Deploy (one deploy, or these phases in order)

**Redeploying Apex while the jobs are scheduled.** A deploy that touches a scheduled class (`DonationChargeScheduler`,
`ChargeRetryScheduler`, `ReconciliationJob`, `MonthlyReceiptScheduler`, `PendingVerificationSweeper`, `StaffAlertService`,
`LogCleanupBatch` or anything they reference) fails with "This schedulable class has jobs pending or in progress" — via the Tooling
API even when Setup → Deployment Settings → "Allow deployments of components when corresponding Apex jobs are pending or in progress"
is on. Unschedule, deploy, schedule again (Anonymous Apex, as any admin; the integration user does the work, D30):

1. `DonationSetup.request('UNSCHEDULE_ALL');` — wait until Setup → Scheduled Jobs shows no `Donations …` job (about a minute) and
   no charge chain is running (Apex Jobs: no `ChargeQueueable` Queued/Processing).
2. Deploy.
3. `DonationSetup.request('SCHEDULE_ALL');` — expect 13 `Donations …` jobs again and the staff email "זמני חיוב עודכנו".

Do it outside the charge times (not at 06:00/08:00/11:00/20:00 or on the hour before them). A run missed while unscheduled is not
made up; if one was missed, run `ChargePlanner.plan(Date.today(), 'AM')` (or `'PM'`) by hand.

| Phase | B10 | Source | Notes |
|---|---|---|---|
| a | 1, 2, 3 | `customPermissions`, `labels`, `objects/Cardcom_Setting__mdt` … all `__mdt` types, `customMetadata`, `objects/Charge_Settings__c`, `objects/Charge_Run_Lock__c`, `objects/Alert_State__c` | `Donor_Link_Setting__mdt.Default.Secret__c` is empty in the repo; set it in README 8. |
| b | 4 | `objects/Contact`, `objects/Opportunity` (fields, record type `Micro_Donation_Pledge`, business process `Micro_Donation_Process`, compact layout, validation rules, list views) | Record type has **no profile assignment** (R3); access only through the permission sets. |
| c | 4, 5 | `objects/Monthly_Receipt__c`, `objects/Charge__c`, `Card_Change_Request__c`, `Pledge_Card_History__c`, `Pledge_Change_Log__c`, `Donor_Link_Use__c`, `Reconciliation_Issue__c`, `Cardcom_Webhook_Log__c`; platform events `Cardcom_Lp_Event__e`, `Charge_Success__e`, `Donation_Setup_Command__e` | `Pledge__c` lookups target Opportunity, so after phase b. |
| d | 7 | `externalCredentials`, `namedCredentials` | No secrets in the files; ApiName/ApiPassword in README 7. |
| e | 8 | `classes`, `triggers`, `email`, `staticresources` | `--test-level RunLocalTests`. |
| f | 10 | `permissionsets` (incl. the optional read-only `Donations_Internal_Read`) | Then assign (README 14). |
| g | 11 | `flows`, `quickActions`, `layouts`, `flexipages` | Activate the record page for the record type only (README 17). |
| h | 12 | `matchingRules`, `duplicateRules` | Deployed **inactive**; activate after step 5.3. |
| i | 15 | `reportTypes`, `reports`, `dashboards` | |

Single deploy: `sf project deploy start --target-org <alias> --source-dir force-app --test-level RunLocalTests`.

## 4. Manual Setup in the org

README 3–19: field history, Cardcom credentials (test terminal 1001 in the sandbox, the client's terminal in production), donor-link
secret, `Cardcom_Setting__mdt.Default` values (URLs, emails, `Integration_User_Id__c`), External Client App `WP_Donations` (D27),
Site `cardcom` + guest permission set, permission-set assignments, record type access, layouts, record page, Contact layout section.

## 5. Data and jobs (in this order)

1. **Custom-setting defaults:** `sf apex run --target-org <alias> --file scripts/apex/init-settings.apex` (README 13).
2. **Platform event subscribers** (all three run as the integration user — README 20):

   ```bash
   scripts/deploy-pe-subscriber.sh <alias> <int-user>
   ```

   **Check the publish behavior** in the target org: Setup → Platform Events → Charge Success → "Publish Behavior" must be
   **Publish After Commit** (repo: `objects/Charge_Success__e` `publishBehavior=PublishAfterCommit`, commit 4f31290). With
   "Publish Immediately" the thank-you trigger can read the charge before it is saved as Success and send nothing. An event's publish
   behavior can't always be changed by a deploy once the event exists; if it still shows "Publish Immediately", change it by hand.
3. **Normalize existing Contacts**, wait for the batch, then activate `Donor_Contact_Match` and `Donor_Contact_Duplicate` (README 21):
   `sf apex run --target-org <alias> --file scripts/apex/normalize-contacts.apex`.
4. **Schedule all jobs** (as any admin; the integration user does the scheduling, D30 — README 22–23):
   `sf apex run --target-org <alias> --file scripts/apex/schedule-donations.apex`. Check Setup → Scheduled Jobs: 13 `Donations …` jobs
   submitted by the integration user, and the staff email "זמני חיוב עודכנו".
5. **"Apply charge schedule" button** in the admins' app (README 24).
6. **Reports:** folder access, dashboard running user, the duplicates report by hand (README 25).

## Production only

- **Sender address.** `Cardcom_Setting__mdt.Default.Org_Wide_Email_Address__c` must be an address in the organization's own domain
  (not Gmail or another free mailbox), verified as an Org-Wide Email Address, with DKIM set up in Salesforce: Setup → DKIM Keys →
  create a key for that domain, publish the two CNAME records in the domain's DNS, then activate the key. Without it thank-you emails
  and staff alerts tend to land in spam. Also set Deliverability to "All email".
- **First night on the client's terminal.** The sandbox uses Cardcom's shared test terminal 1001, whose transaction list doesn't
  represent our charges, so there the reconciliation always falls back to per-charge lookups (N86). After the first night in production:
  - Setup → Apex Jobs: `ReconciliationJob.Job` completed, with no `ReconciliationJob.FallbackJob` after it.
  - No email "התאמה לילית: רשימת העסקאות מ-Cardcom לא זמינה", and `Alert_State__c.Reconciliation_Unavailable_Sent_On__c` is empty.
  - Report "פערי התאמה פתוחים": no `Missing_In_Cardcom` for charges that exist in Cardcom.
  If the alert fires, the list isn't usable on the client's terminal either: check `Cardcom_Setting__mdt.Default.Terminal_Number__c`
  (sent as `LimitForTerminal`) and that the API user may list that terminal's transactions.

## 6. WordPress

`docs/wp-install.md` (plugin, `wp-config.php` constants from the External Client App, cache exclusions in `docs/wp-cache-exclusions.md`).
Then `Cardcom_Setting__mdt.Default.Allowed_Return_Hosts__c` = the site host.

## 7. Acceptance

`docs/acceptance.md` TC01–TC40 in the sandbox with the Cardcom test terminal. Before the first real receipt:
`docs/receipt-go-live-checklist.md`. Production go-live only after the open questions marked "blocks go-live" in
`docs/open-questions.md` are answered.

## Rollback

Nothing below deletes data; pledges, charges and receipts stay for audit.

1. **Stop charging at once:** `Charge_Settings__c.Charging_Enabled__c = false` (no run plans or sends anything).
2. **Remove the jobs:** `DonationSetup.request('UNSCHEDULE_ALL');` (Anonymous Apex, any admin; or `DonationSetup.unscheduleAll();` as the
   integration user). Check Setup → Scheduled Jobs shows no `Donations …` job.
3. **Close the form:** remove the `[org_donation_form]` and `[org_donor_portal]` shortcodes from their pages (or deactivate the
   `org-donations` plugin). Donor links then show WordPress's page without the portal.
4. **Stop new intake in Salesforce:** deactivate the External Client App `WP_Donations` policies (or revoke its consumer secret), and set
   the Site `cardcom` inactive (webhooks get 404; Cardcom retries for 24 h, the sweeper is unscheduled).
5. **Hide the pledges:** deactivate the record type `Micro_Donation_Pledge` (existing records keep it); remove the `Donations_*`
   permission-set assignments if needed. Deactivate the matching/duplicate rules if they bother other processes.
6. **Code rollback** of a single release: redeploy the previous Git tag (`git checkout <tag>` → step 3). Metadata removed in the new
   release needs a destructive-changes deploy; never delete fields that hold data without exporting it first.
