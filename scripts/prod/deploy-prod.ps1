# PowerShell version of scripts/prod/deploy-prod.sh (docs/production-deployment.md).
# Validates / deploys the folder built by scripts/prod/build-prod.py. Real changes to the org except "validate".
#   powershell -ExecutionPolicy Bypass -File scripts\prod\deploy-prod.ps1 <alias> validate
#   powershell -ExecutionPolicy Bypass -File scripts\prod\deploy-prod.ps1 <alias> quick <job-id>
#   powershell -ExecutionPolicy Bypass -File scripts\prod\deploy-prod.ps1 <alias> deploy
param(
    [Parameter(Mandatory = $true)][string]$Alias,
    [Parameter(Mandatory = $true)][ValidateSet('validate', 'quick', 'deploy')][string]$Mode,
    [string]$JobId
)
$ErrorActionPreference = 'Stop'
$dir = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'build\prod'
if (-not (Test-Path (Join-Path $dir 'force-app'))) { throw 'Run scripts\prod\build-prod.py first' }
Push-Location $dir
try {
    $tests = @()
    foreach ($t in Get-Content 'tests.txt') { if ($t.Trim()) { $tests += '--tests'; $tests += $t.Trim() } }
    switch ($Mode) {
        'validate' { & sf project deploy validate --target-org $Alias --source-dir force-app --test-level RunSpecifiedTests @tests --wait 120 --verbose }
        'quick' {
            if (-not $JobId) { throw 'quick needs the job id printed by validate' }
            & sf project deploy quick --target-org $Alias --job-id $JobId --wait 60
        }
        'deploy' { & sf project deploy start --target-org $Alias --source-dir force-app --test-level RunSpecifiedTests @tests --wait 120 --verbose }
    }
    if ($LASTEXITCODE -ne 0) { throw "sf exited with $LASTEXITCODE" }
} finally { Pop-Location }
