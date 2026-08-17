$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
$minimumNodeVersion = [Version]"22.13.0"

function Write-Step {
    param([string]$Message)
    Write-Host "`n==> $Message" -ForegroundColor Cyan
}

function Refresh-ToolPath {
    $knownPaths = @(
        "$env:ProgramFiles\nodejs",
        "$env:ProgramFiles\Git\cmd",
        "$env:LOCALAPPDATA\Programs\Git\cmd"
    )

    foreach ($path in $knownPaths) {
        if ((Test-Path $path) -and (($env:Path -split ";") -notcontains $path)) {
            $env:Path = "$path;$env:Path"
        }
    }
}

function Invoke-WingetPackage {
    param(
        [string]$Id,
        [string]$DisplayName,
        [ValidateSet("install", "upgrade")]
        [string]$Action = "install"
    )

    $winget = Get-Command winget.exe -ErrorAction SilentlyContinue
    if (-not $winget) {
        throw "$DisplayName is missing and winget is unavailable. Install it manually, restart this window, and run the installer CMD again."
    }

    Write-Step "$Action $DisplayName"
    & $winget.Source $Action --id $Id --exact --source winget --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        throw "winget could not $Action $DisplayName (exit code $LASTEXITCODE)."
    }
    Refresh-ToolPath
}

if ($env:OS -ne "Windows_NT") {
    throw "This installer is intended for Windows."
}

Write-Step "Checking Git"
if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
    Invoke-WingetPackage -Id "Git.Git" -DisplayName "Git"
}
if (-not (Get-Command git.exe -ErrorAction SilentlyContinue)) {
    throw "Git is still unavailable. Restart Windows and run the installer again."
}
Write-Host "Git: $(& git.exe --version)"

Write-Step "Checking Node.js"
$nodeNeedsInstall = $true
$node = Get-Command node.exe -ErrorAction SilentlyContinue
if ($node) {
    $nodeVersionText = (& $node.Source --version).Trim().TrimStart("v")
    $nodeVersion = [Version]($nodeVersionText -split "-")[0]
    $nodeNeedsInstall = $nodeVersion -lt $minimumNodeVersion
    Write-Host "Node.js found: $nodeVersion"
}

if ($nodeNeedsInstall) {
    $nodeAction = if ($node) { "upgrade" } else { "install" }
    Invoke-WingetPackage -Id "OpenJS.NodeJS.LTS" -DisplayName "Node.js LTS $minimumNodeVersion or newer" -Action $nodeAction
}

$node = Get-Command node.exe -ErrorAction SilentlyContinue
$npm = Get-Command npm.cmd -ErrorAction SilentlyContinue
if (-not $node -or -not $npm) {
    throw "Node.js or npm is unavailable. Restart Windows and run the installer again."
}

$installedNodeVersionText = (& $node.Source --version).Trim().TrimStart("v")
$installedNodeVersion = [Version]($installedNodeVersionText -split "-")[0]
if ($installedNodeVersion -lt $minimumNodeVersion) {
    throw "Node.js $installedNodeVersion is too old. Version $minimumNodeVersion or newer is required."
}

Write-Step "Installing locked web dependencies"
Push-Location (Join-Path $projectRoot "web")
try {
    & $npm.Source ci
    if ($LASTEXITCODE -ne 0) {
        throw "npm ci failed with exit code $LASTEXITCODE."
    }
}
finally {
    Pop-Location
}

Write-Step "Running safe project verification"
& (Join-Path $PSScriptRoot "verify.ps1")
if (-not $?) {
    throw "Project verification failed."
}

Write-Host "`nSetup completed successfully." -ForegroundColor Green
Write-Host "Open this folder in Claude and ask it to read CLAUDE.md."
