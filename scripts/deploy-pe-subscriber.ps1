# PowerShell version of scripts/deploy-pe-subscriber.sh.
# Deploys the PlatformEventSubscriberConfigs (CardcomLpSubscriber, ChargeSuccessSubscriber, DonationSetupSubscriber) with the
# integration username. This is a real deploy: run it only when you mean to.
#   powershell -ExecutionPolicy Bypass -File scripts\deploy-pe-subscriber.ps1 <org-alias> <integration-username>
param(
    [Parameter(Mandatory = $true)][string]$Alias,
    [Parameter(Mandatory = $true)][string]$Username
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('pe-sub-' + [Guid]::NewGuid().ToString('N'))
$target = Join-Path $tmp 'force-app\main\default\platformEventSubscriberConfigs'
New-Item -ItemType Directory -Path $target -Force | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)
foreach ($f in Get-ChildItem (Join-Path $root 'deploy-templates\platformEventSubscriberConfigs') -Filter '*.platformEventSubscriberConfig-meta.xml') {
    $xml = [IO.File]::ReadAllText($f.FullName).Replace('INTEGRATION_USERNAME', $Username)
    [IO.File]::WriteAllText((Join-Path $target $f.Name), $xml, $utf8)
}
[IO.File]::WriteAllText((Join-Path $tmp 'sfdx-project.json'),
    '{"packageDirectories":[{"path":"force-app","default":true}],"sourceApiVersion":"62.0"}', $utf8)
Push-Location $tmp
try {
    & sf project deploy start --target-org $Alias --source-dir force-app
    if ($LASTEXITCODE -ne 0) { throw "sf exited with $LASTEXITCODE" }
} finally {
    Pop-Location
    Remove-Item -Recurse -Force $tmp
}
