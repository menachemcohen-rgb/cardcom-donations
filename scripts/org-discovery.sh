#!/usr/bin/env bash
# Read-only discovery of the target org's Opportunity/Contact landscape (Prompt 0).
# Runs only SOQL queries, describes and a metadata *retrieve* into discovery/ (git-ignored).
# It never deploys, never writes data and never touches the project source folders.
#
# Usage: scripts/org-discovery.sh <org-alias>
set -euo pipefail

ORG="${1:?usage: scripts/org-discovery.sh <org-alias>}"
OUT="discovery/$(date +%Y%m%d-%H%M%S)-${ORG}"
mkdir -p "$OUT"

q() { # q <file> <soql>
  echo "-> $1"
  sf data query --target-org "$ORG" --query "$2" --result-format csv > "$OUT/$1.csv" 2> "$OUT/$1.err" || echo "   (failed, see $OUT/$1.err)"
}
qt() { # tooling API
  echo "-> $1 (tooling)"
  sf data query --use-tooling-api --target-org "$ORG" --query "$2" --result-format csv > "$OUT/$1.csv" 2> "$OUT/$1.err" || echo "   (failed, see $OUT/$1.err)"
}
describe() {
  echo "-> describe $1"
  sf sobject describe --target-org "$ORG" --sobject "$1" --json > "$OUT/describe-$1.json"
}

sf org display --target-org "$ORG" --json > "$OUT/org-display.json"

# 1. Org basics, packages, Person Accounts, currency, TZ
q org            "SELECT Name, OrganizationType, IsSandbox, TimeZoneSidKey, DefaultLocaleSidKey, LanguageLocaleKey, DefaultCurrencyIsoCode FROM Organization"
q packages       "SELECT NamespacePrefix, Status, AllowedLicenses, UsedLicenses, ExpirationDate FROM PackageLicense ORDER BY NamespacePrefix"
q sharing        "SELECT QualifiedApiName, InternalSharingModel, ExternalSharingModel FROM EntityDefinition WHERE QualifiedApiName IN ('Account','Contact','Opportunity')"
for o in Account Contact Opportunity OpportunityContactRole; do describe "$o"; done

# 2. Opportunity configuration
q opp-recordtypes     "SELECT DeveloperName, Name, IsActive, BusinessProcessId, NamespacePrefix FROM RecordType WHERE SobjectType = 'Opportunity'"
q opp-salesprocesses  "SELECT Id, Name, IsActive, Description FROM BusinessProcess WHERE TableEnumOrId = 'Opportunity'"
q opp-stages          "SELECT ApiName, MasterLabel, IsActive, IsClosed, IsWon, DefaultProbability, ForecastCategoryName, SortOrder FROM OpportunityStage ORDER BY SortOrder"
qt opp-history-fields "SELECT QualifiedApiName FROM FieldDefinition WHERE EntityDefinition.QualifiedApiName = 'Opportunity' AND IsFieldHistoryTracked = true"

# 3. Automation on Opportunity, Contact and OpportunityContactRole
for o in Opportunity Contact OpportunityContactRole; do
  qt "vr-$o"       "SELECT ValidationName, Active, ErrorDisplayField, ErrorMessage, NamespacePrefix FROM ValidationRule WHERE EntityDefinition.QualifiedApiName = '$o'"
  qt "triggers-$o" "SELECT Name, Status, NamespacePrefix, UsageBeforeInsert, UsageAfterInsert, UsageBeforeUpdate, UsageAfterUpdate FROM ApexTrigger WHERE TableEnumOrId = '$o'"
  qt "workflow-$o" "SELECT Name, NamespacePrefix FROM WorkflowRule WHERE TableEnumOrId = '$o'"
done
# Record-triggered flows and Process Builders (labels may be localized; filter by API name of the object in the CSV)
q flows-active "SELECT ApiName, Label, ProcessType, TriggerType, RecordTriggerType, TriggerObjectOrEventId, TriggerObjectOrEventLabel, NamespacePrefix FROM FlowDefinitionView WHERE IsActive = true AND (TriggerType != null OR ProcessType = 'Workflow')"
q duplicate-rules "SELECT DeveloperName, MasterLabel, SobjectType, IsActive, NamespacePrefix FROM DuplicateRule WHERE SobjectType IN ('Contact','Opportunity','Account','Lead')"

# 4. Email and users
q owea      "SELECT Address, DisplayName, IsAllowAllProfiles FROM OrgWideEmailAddress"
q int-users "SELECT Username, IsActive, TimeZoneSidKey, LocaleSidKey, LanguageLocaleKey, Profile.Name, Profile.UserLicense.Name FROM User WHERE Profile.UserLicense.Name LIKE '%Integration%' OR Username LIKE 'integration%'"

# 5. Metadata snapshots (retrieve only; writes under $OUT, not force-app)
echo "-> retrieve StandardValueSet:OpportunityStage, MatchingRules, Settings"
sf project retrieve start --target-org "$ORG" --output-dir "$OUT/retrieve" \
  --metadata "StandardValueSet:OpportunityStage" "MatchingRules:Contact" "MatchingRules:Opportunity" \
             "DuplicateRule" "Settings:Opportunity" "Settings:Account" "Settings:Language" > "$OUT/retrieve.log" 2>&1 \
  || echo "   (retrieve failed, see $OUT/retrieve.log)"

# 6. Quick summaries derived from the describes
node -e '
const fs=require("fs"),p=process.argv[1];
for (const o of ["Opportunity","Contact"]) {
  const d=JSON.parse(fs.readFileSync(`${p}/describe-${o}.json`)).result;
  const req=d.fields.filter(f=>f.createable&&!f.nillable&&!f.defaultedOnCreate).map(f=>f.name);
  console.log(`${o}: required-on-create = ${req.join(", ")}`);
  if (o==="Opportunity") {
    const acc=d.fields.find(f=>f.name==="AccountId");
    console.log(`Opportunity.AccountId nillable = ${acc&&acc.nillable}`);
    console.log(`Opportunity.CurrencyIsoCode present (multi-currency) = ${d.fields.some(f=>f.name==="CurrencyIsoCode")}`);
  }
}
const a=JSON.parse(fs.readFileSync(`${p}/describe-Account.json`)).result;
console.log(`Person Accounts enabled = ${a.fields.some(f=>f.name==="IsPersonAccount")}`);
' "$OUT" | tee "$OUT/summary.txt"

echo
echo "Done. Results in $OUT. Fill docs/org-discovery.md from them; do not commit the raw folder."
