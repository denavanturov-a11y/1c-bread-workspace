$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

. (Join-Path $PSScriptRoot "local-business-config.ps1")
try {
    $businessConfig = Get-LocalBusinessConfig
}
catch {
    [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Local configuration required", "OK", "Error")
    exit 1
}

$supplierLabel = [string]$businessConfig.supplierLabel
$counterpartyKey = [string]$businessConfig.counterpartyKey

function Invoke-ODataQuery {
    param(
        [string]$Uri,
        [hashtable]$Headers
    )

    return Invoke-RestMethod -UseBasicParsing -Uri $Uri -Headers $Headers -Method Get -TimeoutSec 60
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "1C Bread Connector - supplier history"
$form.Size = New-Object System.Drawing.Size(560, 330)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

$urlLabel = New-Object System.Windows.Forms.Label
$urlLabel.Text = "OData address"
$urlLabel.Location = New-Object System.Drawing.Point(24, 24)
$urlLabel.AutoSize = $true
$form.Controls.Add($urlLabel)

$urlBox = New-Object System.Windows.Forms.TextBox
$urlBox.Text = "http://localhost/khleb1c/odata/standard.odata"
$urlBox.Location = New-Object System.Drawing.Point(24, 46)
$urlBox.Size = New-Object System.Drawing.Size(500, 24)
$form.Controls.Add($urlBox)

$userLabel = New-Object System.Windows.Forms.Label
$userLabel.Text = "1C user"
$userLabel.Location = New-Object System.Drawing.Point(24, 84)
$userLabel.AutoSize = $true
$form.Controls.Add($userLabel)

$userBox = New-Object System.Windows.Forms.TextBox
$userBox.Location = New-Object System.Drawing.Point(24, 106)
$userBox.Size = New-Object System.Drawing.Size(240, 24)
$form.Controls.Add($userBox)

$passwordLabel = New-Object System.Windows.Forms.Label
$passwordLabel.Text = "1C password (not saved)"
$passwordLabel.Location = New-Object System.Drawing.Point(284, 84)
$passwordLabel.AutoSize = $true
$form.Controls.Add($passwordLabel)

$passwordBox = New-Object System.Windows.Forms.TextBox
$passwordBox.Location = New-Object System.Drawing.Point(284, 106)
$passwordBox.Size = New-Object System.Drawing.Size(240, 24)
$passwordBox.UseSystemPasswordChar = $true
$form.Controls.Add($passwordBox)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = "Read-only: reads recent incoming invoices from $supplierLabel."
$statusLabel.Location = New-Object System.Drawing.Point(24, 150)
$statusLabel.Size = New-Object System.Drawing.Size(500, 44)
$form.Controls.Add($statusLabel)

$exportButton = New-Object System.Windows.Forms.Button
$exportButton.Text = "Export supplier history (read-only)"
$exportButton.Location = New-Object System.Drawing.Point(24, 212)
$exportButton.Size = New-Object System.Drawing.Size(500, 38)
$form.Controls.Add($exportButton)

$exportButton.Add_Click({
    if ([string]::IsNullOrWhiteSpace($userBox.Text) -or [string]::IsNullOrWhiteSpace($passwordBox.Text)) {
        [System.Windows.Forms.MessageBox]::Show("Enter the dedicated 1C user and password.", "Missing data", "OK", "Warning")
        return
    }

    $exportButton.Enabled = $false
    $statusLabel.Text = "Reading recent invoices for $supplierLabel from local 1C..."
    $form.Refresh()

    try {
        $baseUrl = $urlBox.Text.Trim().TrimEnd('/')
        $credentialText = "{0}:{1}" -f $userBox.Text, $passwordBox.Text
        $credentialBytes = [System.Text.Encoding]::UTF8.GetBytes($credentialText)
        $authValue = [Convert]::ToBase64String($credentialBytes)
        $headers = @{ Authorization = "Basic $authValue" }

        $documentSelect = "Ref_Key,Number,Date,ВходящийНомерДокумента,Контрагент_Key,Товары"
        $documentFilter = "Контрагент_Key eq guid'$counterpartyKey'"
        $documentQuery = "`$select=$([Uri]::EscapeDataString($documentSelect))&`$filter=$([Uri]::EscapeDataString($documentFilter))&`$orderby=Date%20desc&`$top=30&`$format=json"
        $documentResponse = Invoke-ODataQuery -Uri "$baseUrl/Document_ПриходнаяНакладная`?$documentQuery" -Headers $headers
        $documents = @($documentResponse.value)

        if ($documents.Count -eq 0) {
            throw "No incoming invoices for $supplierLabel were found."
        }

        $itemCache = @{}
        $resultRows = New-Object System.Collections.ArrayList

        foreach ($document in $documents) {
            foreach ($line in @($document.'Товары')) {
                $itemKey = [string]$line.'Номенклатура_Key'
                if ([string]::IsNullOrWhiteSpace($itemKey) -or $itemKey -eq "00000000-0000-0000-0000-000000000000") {
                    continue
                }

                if (-not $itemCache.ContainsKey($itemKey)) {
                    $itemSelect = "Ref_Key,Code,Description,НаименованиеПолное"
                    $itemFilter = "Ref_Key eq guid'$itemKey'"
                    $itemQuery = "`$select=$([Uri]::EscapeDataString($itemSelect))&`$filter=$([Uri]::EscapeDataString($itemFilter))&`$top=1&`$format=json"
                    $itemResponse = Invoke-ODataQuery -Uri "$baseUrl/Catalog_Номенклатура`?$itemQuery" -Headers $headers
                    $itemCache[$itemKey] = @($itemResponse.value)[0]
                }

                $item = $itemCache[$itemKey]
                [void]$resultRows.Add([pscustomobject][ordered]@{
                    DocumentDate = $document.Date
                    DocumentNumber = $document.Number
                    IncomingNumber = $document.'ВходящийНомерДокумента'
                    ItemRef_Key = $itemKey
                    ItemCode = $item.Code
                    ItemName = $item.Description
                    ItemFullName = $item.'НаименованиеПолное'
                    Quantity = $line.'Количество'
                    PurchasePrice = $line.'ПриходнаяЦена'
                    PurchaseAmount = $line.'ПриходнаяСумма'
                })
            }
        }

        $outputDir = Join-Path $PSScriptRoot "miller-history"
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        @($resultRows) | Sort-Object DocumentDate -Descending | Export-Csv -Path (Join-Path $outputDir "miller-history-items.csv") -Delimiter ';' -NoTypeInformation -Encoding UTF8

        $summary = [ordered]@{
            exportedAt = (Get-Date).ToString("o")
            baseUrl = $baseUrl
            supplier = $supplierLabel
            supplierRef_Key = $counterpartyKey
            documentsRead = $documents.Count
            rowsSaved = $resultRows.Count
            containsPassword = $false
            readOnly = $true
        }
        [System.IO.File]::WriteAllText((Join-Path $outputDir "summary.json"), ($summary | ConvertTo-Json -Depth 3), (New-Object System.Text.UTF8Encoding($false)))

        $passwordBox.Text = ""
        $statusLabel.Text = "Success. The result was saved to the miller-history folder."
        [System.Windows.Forms.MessageBox]::Show("Read-only history export succeeded. No 1C data was changed. Send the miller-history folder to the developer.", "Success", "OK", "Information")
    }
    catch {
        $passwordBox.Text = ""
        $statusLabel.Text = "The export failed. No 1C data was changed."
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Read-only export failed", "OK", "Error")
    }
    finally {
        $exportButton.Enabled = $true
    }
})

[void]$form.ShowDialog()
