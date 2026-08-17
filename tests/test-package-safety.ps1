$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$projectRoot = Split-Path -Parent $PSScriptRoot
$failures = New-Object System.Collections.Generic.List[string]

$requiredPaths = @(
    "CLAUDE.md",
    "README.md",
    "connector\connector-check.ps1",
    "connector\business-data.example.json",
    "connector\local-business-config.ps1",
    "connector\test-create-unposted.ps1",
    "web\package.json",
    "web\package-lock.json"
)

foreach ($relativePath in $requiredPaths) {
    if (-not (Test-Path (Join-Path $projectRoot $relativePath))) {
        $failures.Add("Missing required path: $relativePath")
    }
}

$powerShellFiles = Get-ChildItem -Path $projectRoot -Recurse -File -Filter "*.ps1" |
    Where-Object { $_.FullName -notmatch "[\\/]node_modules[\\/]" }

foreach ($file in $powerShellFiles) {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        $file.FullName,
        [ref]$tokens,
        [ref]$parseErrors
    )
    foreach ($parseError in $parseErrors) {
        $failures.Add("PowerShell syntax error in $($file.FullName): $($parseError.Message)")
    }
}

$writeScripts = @()
foreach ($file in $powerShellFiles) {
    $content = Get-Content -LiteralPath $file.FullName -Raw
    if ($content -match "(?i)-Method\s+(Post|Patch|Delete)\b") {
        $writeScripts += $file
    }
}

if ($writeScripts.Count -ne 1 -or $writeScripts[0].Name -ne "test-create-unposted.ps1") {
    $names = ($writeScripts | ForEach-Object { $_.FullName }) -join ", "
    $failures.Add("Unexpected set of 1C write scripts: $names")
}

$testWritePath = Join-Path $projectRoot "connector\test-create-unposted.ps1"
if (Test-Path $testWritePath) {
    $testWriteContent = Get-Content -LiteralPath $testWritePath -Raw
    foreach ($guard in @(
        "http://localhost/khleb1c_test/odata/standard.odata",
        "C:\Baze_Test_Hleb",
        '"Posted" = $false'
    )) {
        if (-not $testWriteContent.Contains($guard)) {
            $failures.Add("The test write script is missing safety guard: $guard")
        }
    }
}

$trackedFiles = @()
$git = Get-Command git.exe -ErrorAction SilentlyContinue
if ($git -and (Test-Path (Join-Path $projectRoot ".git"))) {
    $trackedFiles = & $git.Source -c core.quotepath=false -C $projectRoot ls-files
    if ($LASTEXITCODE -ne 0) {
        $failures.Add("git ls-files failed.")
    }
}
else {
    $trackedFiles = Get-ChildItem -Path $projectRoot -Recurse -File |
        Where-Object {
            $_.FullName -notmatch "[\\/](node_modules|\.next|\.vinext|dist|\.wrangler)[\\/]"
        } |
        ForEach-Object { $_.FullName.Substring($projectRoot.Length + 1).Replace("\", "/") }
}

$forbiddenTrackedPatterns = @(
    "(^|/)\.env($|\.)",
    "(^|/)\.codex-local/",
    "(^|/)node_modules/",
    "(^|/)(\.next|\.vinext|dist|\.wrangler)/",
    "^connector/(diagnostics|catalog-match|miller-history|test-write-preflight|test-create-result)/",
    "^connector/business-data\.local\.json$",
    "^backups/(?!README\.md$)"
)

foreach ($trackedFile in $trackedFiles) {
    foreach ($pattern in $forbiddenTrackedPatterns) {
        if ($trackedFile -match $pattern) {
            $failures.Add("Forbidden tracked or packaged file: $trackedFile")
        }
    }
}

$nonZeroGuidPattern = "(?i)\b(?!00000000-0000-0000-0000-000000000000\b)[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b"
foreach ($trackedFile in @($trackedFiles | Where-Object { $_ -like "connector/*" })) {
    $fullPath = Join-Path $projectRoot $trackedFile
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        continue
    }
    try {
        $content = Get-Content -LiteralPath $fullPath -Raw -ErrorAction Stop
        if ($content -match $nonZeroGuidPattern) {
            $failures.Add("Real-looking non-zero GUID in tracked connector file: $trackedFile")
        }
    }
    catch {
        # This check applies only to readable text files.
    }
}

$secretPattern = "(?i)(gho_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----)"
foreach ($trackedFile in $trackedFiles) {
    $fullPath = Join-Path $projectRoot $trackedFile
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        continue
    }
    try {
        $content = Get-Content -LiteralPath $fullPath -Raw -ErrorAction Stop
        if ($content -match $secretPattern) {
            $failures.Add("Possible secret in: $trackedFile")
        }
    }
    catch {
        # Binary files are allowed; high-confidence secret scanning applies to readable text.
    }
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) {
        Write-Error $failure -ErrorAction Continue
    }
    exit 1
}

Write-Host "Package structure, PowerShell syntax, write guards, business identifiers, and secret patterns passed." -ForegroundColor Green
