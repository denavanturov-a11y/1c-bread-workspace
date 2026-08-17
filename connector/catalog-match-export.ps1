$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

function Get-ODataRows {
    param(
        [string]$BaseUrl,
        [string]$EntitySet,
        [string]$Select,
        [hashtable]$Headers
    )

    $rows = New-Object System.Collections.ArrayList
    $pageSize = 250
    $skip = 0

    do {
        $query = "`$select=$([Uri]::EscapeDataString($Select))&`$filter=$([Uri]::EscapeDataString('IsFolder eq false and DeletionMark eq false'))&`$orderby=Description&`$top=$pageSize&`$skip=$skip&`$format=json"
        $response = Invoke-RestMethod -UseBasicParsing -Uri "$BaseUrl/$EntitySet`?$query" -Headers $Headers -Method Get -TimeoutSec 60
        $page = @($response.value)
        foreach ($row in $page) {
            [void]$rows.Add($row)
        }
        $skip += $page.Count
    } while ($page.Count -eq $pageSize)

    return @($rows)
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "1C Bread Connector - sample matching"
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
$statusLabel.Text = "Read-only: finds bread products and the two suppliers from the sample photos."
$statusLabel.Location = New-Object System.Drawing.Point(24, 150)
$statusLabel.Size = New-Object System.Drawing.Size(500, 44)
$form.Controls.Add($statusLabel)

$exportButton = New-Object System.Windows.Forms.Button
$exportButton.Text = "Export matching candidates (read-only)"
$exportButton.Location = New-Object System.Drawing.Point(24, 212)
$exportButton.Size = New-Object System.Drawing.Size(500, 38)
$form.Controls.Add($exportButton)

$exportButton.Add_Click({
    if ([string]::IsNullOrWhiteSpace($userBox.Text) -or [string]::IsNullOrWhiteSpace($passwordBox.Text)) {
        [System.Windows.Forms.MessageBox]::Show("Enter the dedicated 1C user and password.", "Missing data", "OK", "Warning")
        return
    }

    $exportButton.Enabled = $false
    $statusLabel.Text = "Reading minimal catalog fields from local 1C..."
    $form.Refresh()

    try {
        $baseUrl = $urlBox.Text.Trim().TrimEnd('/')
        $credentialText = "{0}:{1}" -f $userBox.Text, $passwordBox.Text
        $credentialBytes = [System.Text.Encoding]::UTF8.GetBytes($credentialText)
        $authValue = [Convert]::ToBase64String($credentialBytes)
        $headers = @{ Authorization = "Basic $authValue" }

        $items = Get-ODataRows -BaseUrl $baseUrl -EntitySet "Catalog_Номенклатура" -Select "Ref_Key,Code,Description,НаименованиеПолное,БазоваяЕдиница_Key,МинимальныйПроцентНаценки,ПроцентНаценки,IsFolder,DeletionMark" -Headers $headers
        $counterparties = Get-ODataRows -BaseUrl $baseUrl -EntitySet "Catalog_Контрагенты" -Select "Ref_Key,Code,Description,НаименованиеПолное,ИНН,IsFolder,DeletionMark" -Headers $headers

        $itemPattern = '(?i)(хлеб|матнакаш|бородин|пшенич|ржан|налив)'
        $supplierPattern = '(?i)(мельник|витязь)'

        $itemCandidates = @($items | Where-Object {
            (([string]$_.Description) -match $itemPattern) -or (([string]$_.'НаименованиеПолное') -match $itemPattern)
        } | ForEach-Object {
            [pscustomobject][ordered]@{
                Ref_Key = $_.Ref_Key
                Code = $_.Code
                Description = $_.Description
                FullName = $_.'НаименованиеПолное'
                BaseUnit_Key = $_.'БазоваяЕдиница_Key'
                MinimumMarkupPercent = $_.'МинимальныйПроцентНаценки'
                MarkupPercent = $_.'ПроцентНаценки'
            }
        })

        $supplierCandidates = @($counterparties | Where-Object {
            (([string]$_.Description) -match $supplierPattern) -or (([string]$_.'НаименованиеПолное') -match $supplierPattern)
        } | ForEach-Object {
            [pscustomobject][ordered]@{
                Ref_Key = $_.Ref_Key
                Code = $_.Code
                Description = $_.Description
                FullName = $_.'НаименованиеПолное'
                TaxId = $_.'ИНН'
            }
        })

        $outputDir = Join-Path $PSScriptRoot "catalog-match"
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

        $itemCandidates | Export-Csv -Path (Join-Path $outputDir "nomenclature-candidates.csv") -Delimiter ';' -NoTypeInformation -Encoding UTF8
        $supplierCandidates | Export-Csv -Path (Join-Path $outputDir "supplier-candidates.csv") -Delimiter ';' -NoTypeInformation -Encoding UTF8

        $summary = [ordered]@{
            exportedAt = (Get-Date).ToString("o")
            baseUrl = $baseUrl
            nomenclatureRowsScanned = $items.Count
            nomenclatureCandidatesSaved = $itemCandidates.Count
            counterpartyRowsScanned = $counterparties.Count
            supplierCandidatesSaved = $supplierCandidates.Count
            containsPassword = $false
            readOnly = $true
        }
        [System.IO.File]::WriteAllText((Join-Path $outputDir "summary.json"), ($summary | ConvertTo-Json -Depth 3), (New-Object System.Text.UTF8Encoding($false)))

        $passwordBox.Text = ""
        $statusLabel.Text = "Success. Matching candidates were saved to the catalog-match folder."
        [System.Windows.Forms.MessageBox]::Show("Read-only export succeeded. No 1C data was changed. Send the catalog-match folder to the developer.", "Success", "OK", "Information")
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
