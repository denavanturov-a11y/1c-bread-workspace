$ErrorActionPreference = "Stop"

function Assert-ProjectGuid {
    param(
        [object]$Value,
        [string]$FieldName
    )

    $parsedGuid = [Guid]::Empty
    if (-not [Guid]::TryParse([string]$Value, [ref]$parsedGuid) -or $parsedGuid -eq [Guid]::Empty) {
        throw "Local configuration field '$FieldName' must contain a non-zero GUID from 1C."
    }
}

function Get-LocalBusinessConfig {
    param([switch]$RequireTestInvoice)

    $configPath = Join-Path $PSScriptRoot "business-data.local.json"
    $examplePath = Join-Path $PSScriptRoot "business-data.example.json"

    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        throw "Local business configuration was not found. Copy '$examplePath' to '$configPath' and fill it from the read-only connector exports. The local file is ignored by Git."
    }

    try {
        $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        throw "Could not read local business configuration '$configPath': $($_.Exception.Message)"
    }

    if ([string]::IsNullOrWhiteSpace([string]$config.supplierLabel)) {
        throw "Local configuration field 'supplierLabel' is required."
    }
    Assert-ProjectGuid -Value $config.counterpartyKey -FieldName "counterpartyKey"

    if (-not [string]::IsNullOrWhiteSpace([string]$config.sourceDocumentDate) -and ([string]$config.sourceDocumentDate) -notmatch '^\d{4}-\d{2}-\d{2}$') {
        throw "Optional field 'sourceDocumentDate' must use YYYY-MM-DD format."
    }

    if (-not $RequireTestInvoice) {
        return $config
    }

    if ($null -eq $config.testInvoice) {
        throw "Local configuration section 'testInvoice' is required for a test write."
    }

    if (([string]$config.testInvoice.marker) -notmatch '^KHLEB-TEST-[A-Z0-9_-]+$' -or ([string]$config.testInvoice.marker) -eq "KHLEB-TEST-CHANGE-ME") {
        throw "Set a unique testInvoice.marker beginning with 'KHLEB-TEST-'."
    }

    foreach ($fieldName in @(
        "currencyKey",
        "contractKey",
        "warehouseKey",
        "priceTypeKey",
        "tradeObjectKey",
        "companyKey",
        "vatRateKey"
    )) {
        Assert-ProjectGuid -Value $config.testInvoice.$fieldName -FieldName "testInvoice.$fieldName"
    }

    $configuredItems = @($config.testInvoice.items)
    if ($configuredItems.Count -eq 0) {
        throw "Local configuration must contain at least one testInvoice.items entry."
    }

    for ($index = 0; $index -lt $configuredItems.Count; $index++) {
        $item = $configuredItems[$index]
        Assert-ProjectGuid -Value $item.unitKey -FieldName "testInvoice.items[$index].unitKey"
        Assert-ProjectGuid -Value $item.itemKey -FieldName "testInvoice.items[$index].itemKey"

        foreach ($numericField in @("quantity", "purchasePrice", "retailPrice")) {
            $number = 0.0
            if (-not [double]::TryParse([string]$item.$numericField, [ref]$number) -or $number -le 0) {
                throw "Local configuration field 'testInvoice.items[$index].$numericField' must be greater than zero."
            }
        }

        $markup = 0.0
        if (-not [double]::TryParse([string]$item.markupPercent, [ref]$markup) -or $markup -lt 0) {
            throw "Local configuration field 'testInvoice.items[$index].markupPercent' must be zero or greater."
        }
    }

    return $config
}
