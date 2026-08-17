$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
$minimumNodeVersion = [Version]"22.13.0"

function Invoke-Checked {
    param(
        [string]$Name,
        [scriptblock]$Action
    )

    Write-Host "`n==> $Name" -ForegroundColor Cyan
    & $Action
    if ($LASTEXITCODE -ne 0) {
        throw "$Name failed with exit code $LASTEXITCODE."
    }
}

Write-Host "Safe verification only: no connector is executed and no request is sent to 1C." -ForegroundColor Yellow

& (Join-Path $projectRoot "tests\test-package-safety.ps1")
if (-not $?) {
    throw "Package safety checks failed."
}

$node = Get-Command node.exe -ErrorAction SilentlyContinue
$npm = Get-Command npm.cmd -ErrorAction SilentlyContinue
if (-not $node -or -not $npm) {
    throw "Node.js and npm are required. Run the installer CMD first."
}

$nodeVersionText = (& $node.Source --version).Trim().TrimStart("v")
$nodeVersion = [Version]($nodeVersionText -split "-")[0]
if ($nodeVersion -lt $minimumNodeVersion) {
    throw "Node.js $nodeVersion is too old. Version $minimumNodeVersion or newer is required."
}

Push-Location (Join-Path $projectRoot "web")
try {
    if (-not (Test-Path "node_modules")) {
        Invoke-Checked "Installing locked dependencies" { & $npm.Source ci }
    }
    Invoke-Checked "Web lint" { & $npm.Source run lint }
    Invoke-Checked "Web build and tests" { & $npm.Source test }
    Invoke-Checked "Production dependency audit" { & $npm.Source audit --omit=dev --audit-level=low }
}
finally {
    Pop-Location
}

Write-Host "`nAll safe checks passed." -ForegroundColor Green
