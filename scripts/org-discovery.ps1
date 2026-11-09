# PowerShell version of scripts/org-discovery.sh: read-only discovery of the target org (Prompt 0).
# Runs only SOQL queries, describes and a metadata *retrieve* into discovery\ (git-ignored).
# It never deploys, never writes data and never touches the project source folders.
#   powershell -ExecutionPolicy Bypass -File scripts\org-discovery.ps1 <org-alias>
param([Parameter(Mandatory = $true)][string]$Alias)
$ErrorActionPreference = 'Continue'
$out = Join-Path 'discovery' ((Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + $Alias)
New-Item -ItemType Directory -Path $out -Force | Out-Null

function Q([string]$name, [string]$soql, [switch]$Tooling) {
    Write-Host "-> $name$(if ($Tooling) { ' (tooling)' })"
    $args2 = @('data', 'query', '--target-org', $Alias, '--query', $soql, '--result-format', 'csv')
    if ($Tooling) { $args2 += '--use-tooling-api' }
    & sf @args2 2> (Join-Path $out "$name.err") | Out-File -Encoding utf8 (Join-Path $out "$name.csv")
    if ($LASTEXITCODE -ne 0) { Write-Host "   (failed, see $out\$name.err)" }
}
function Describe([string]$obj) {
    Write-Host "-> describe $obj"
    & sf sobject describe --target-org $Alias --sobject $obj --json | Out-File -Encoding utf8 (Join-Path $out "describe-$obj.json")
}

& sf org display --target-org $Alias --json | Out-File -Encoding utf8 (Join-Path $out 'org-display.json')

# 1. Org basics, packages, Person Accounts, currency, TZ
Q 'org'      "SELECT Name, OrganizationType, IsSandbox, TimeZoneSidKey, DefaultLocaleSidKey, LanguageLocaleKey, DefaultCurrencyIsoCode FROM Organization"
Q 'packages' "SELECT NamespacePrefix, Status, AllowedLicenses, UsedLicenses, ExpirationDate FROM PackageLicense ORDER BY NamespacePrefix"
Q 'sharing'  "SELECT QualifiedApiName, InternalSharingModel, ExternalSharingModel FROM EntityDefinition WHERE QualifiedApiName IN ('Account','Contact','Opportunity')"
foreach ($o in 'Account', 'Contact', 'Opportunity', 'OpportunityContactRole') { Describe $o }

# 2. Opportunity configuration
Q 'opp-recordtypes'    "SELECT DeveloperName, Name, IsActive, BusinessProcessId, NamespacePrefix FROM RecordType WHERE SobjectType = 'Opportunity'"
Q 'opp-salesprocesses' "SELECT Id, Name, IsActive, Description FROM BusinessProcess WHERE TableEnumOrId = 'Opportunity'"
Q 'opp-stages'         "SELECT ApiName, MasterLabel, IsActive, IsClosed, IsWon, DefaultProbability, ForecastCategoryName, SortOrder FROM OpportunityStage ORDER BY SortOrder"
Q 'opp-history-fields' "SELECT QualifiedApiName FROM FieldDefinition WHERE EntityDefinition.QualifiedApiName = 'Opportunity' AND IsFieldHistoryTracked = true" -Tooling

# 3. Automation on Opportunity, Contact and OpportunityContactRole
foreach ($o in 'Opportunity', 'Contact', 'OpportunityContactRole') {
    Q "vr-$o"       "SELECT ValidationName, Active, ErrorDisplayField, ErrorMessage, NamespacePrefix FROM ValidationRule WHERE EntityDefinition.QualifiedApiName = '$o'" -Tooling
    Q "triggers-$o" "SELECT Name, Status, NamespacePrefix, UsageBeforeInsert, UsageAfterInsert, UsageBeforeUpdate, UsageAfterUpdate FROM ApexTrigger WHERE TableEnumOrId = '$o'" -Tooling
    Q "workflow-$o" "SELECT Name, NamespacePrefix FROM WorkflowRule WHERE TableEnumOrId = '$o'" -Tooling
}
# FlowDefinitionView rejects OR ("Disjunctions not supported"): two queries
Q 'flows-active'    "SELECT ApiName, Label, ProcessType, TriggerType, RecordTriggerType, TriggerObjectOrEventId, TriggerObjectOrEventLabel, NamespacePrefix FROM FlowDefinitionView WHERE IsActive = true AND TriggerType != null"
Q 'flows-process-builder' "SELECT ApiName, Label, ProcessType, TriggerType, RecordTriggerType, TriggerObjectOrEventId, TriggerObjectOrEventLabel, NamespacePrefix FROM FlowDefinitionView WHERE IsActive = true AND ProcessType = 'Workflow'"
Q 'duplicate-rules' "SELECT DeveloperName, MasterLabel, SobjectType, IsActive, NamespacePrefix FROM DuplicateRule WHERE SobjectType IN ('Contact','Opportunity','Account','Lead')"

# 4. Email and users
Q 'owea'      "SELECT Address, DisplayName, IsAllowAllProfiles FROM OrgWideEmailAddress"
Q 'int-users' "SELECT Username, IsActive, TimeZoneSidKey, LocaleSidKey, LanguageLocaleKey, Profile.Name, Profile.UserLicense.Name FROM User WHERE Profile.UserLicense.Name LIKE '%Integration%' OR Username LIKE 'integration%'"

# 5. Metadata snapshots (retrieve only; writes under $out, not force-app)
Write-Host '-> retrieve StandardValueSet:OpportunityStage, MatchingRules, Settings'
& sf project retrieve start --target-org $Alias --output-dir (Join-Path $out 'retrieve') `
    --metadata 'StandardValueSet:OpportunityStage' 'MatchingRules:Contact' 'MatchingRules:Opportunity' `
    'DuplicateRule' 'Settings:Opportunity' 'Settings:Account' 'Settings:Language' *> (Join-Path $out 'retrieve.log')
if ($LASTEXITCODE -ne 0) { Write-Host "   (retrieve failed, see $out\retrieve.log)" }

# 6. Quick summaries derived from the describes
$summary = @()
foreach ($o in 'Opportunity', 'Contact') {
    $d = (Get-Content -Raw -Encoding utf8 (Join-Path $out "describe-$o.json") | ConvertFrom-Json).result
    $req = $d.fields | Where-Object { $_.createable -and -not $_.nillable -and -not $_.defaultedOnCreate } | ForEach-Object { $_.name }
    $summary += "${o}: required-on-create = $($req -join ', ')"
    if ($o -eq 'Opportunity') {
        $acc = $d.fields | Where-Object { $_.name -eq 'AccountId' }
        $summary += "Opportunity.AccountId nillable = $($acc.nillable)"
        $summary += "Opportunity.CurrencyIsoCode present (multi-currency) = $([bool]($d.fields | Where-Object { $_.name -eq 'CurrencyIsoCode' }))"
    }
}
$a = (Get-Content -Raw -Encoding utf8 (Join-Path $out 'describe-Account.json') | ConvertFrom-Json).result
$summary += "Person Accounts enabled = $([bool]($a.fields | Where-Object { $_.name -eq 'IsPersonAccount' }))"
$summary | Tee-Object -FilePath (Join-Path $out 'summary.txt')

Write-Host ''
Write-Host "Done. Results in $out. Fill docs/org-discovery.md from them; do not commit the raw folder."
