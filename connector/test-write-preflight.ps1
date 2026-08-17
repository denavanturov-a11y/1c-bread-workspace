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

$testBaseUrl = "http://localhost/khleb1c_test/odata/standard.odata"
$expectedDatabasePath = "C:\Baze_Test_Hleb"
$supplierLabel = [string]$businessConfig.supplierLabel
$counterpartyKey = [string]$businessConfig.counterpartyKey
$sourceDocumentNumber = [string]$businessConfig.sourceDocumentNumber
$sourceDocumentDate = [string]$businessConfig.sourceDocumentDate

function Get-NormalizedDigits {
    param([object]$Value)

    $digits = ([string]$Value) -replace '[^0-9]', ''
    return $digits.TrimStart('0')
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "1C Bread Connector - test write preflight"
$form.Size = New-Object System.Drawing.Size(580, 350)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

$targetLabel = New-Object System.Windows.Forms.Label
$targetLabel.Text = "Fixed target: TEST COPY ONLY"
$targetLabel.Location = New-Object System.Drawing.Point(24, 22)
$targetLabel.AutoSize = $true
$targetLabel.Font = New-Object System.Drawing.Font($targetLabel.Font, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($targetLabel)

$urlBox = New-Object System.Windows.Forms.TextBox
$urlBox.Text = $testBaseUrl
$urlBox.Location = New-Object System.Drawing.Point(24, 46)
$urlBox.Size = New-Object System.Drawing.Size(520, 24)
$urlBox.ReadOnly = $true
$form.Controls.Add($urlBox)

$userLabel = New-Object System.Windows.Forms.Label
$userLabel.Text = "1C user"
$userLabel.Location = New-Object System.Drawing.Point(24, 88)
$userLabel.AutoSize = $true
$form.Controls.Add($userLabel)

$userBox = New-Object System.Windows.Forms.TextBox
$userBox.Location = New-Object System.Drawing.Point(24, 110)
$userBox.Size = New-Object System.Drawing.Size(250, 24)
$form.Controls.Add($userBox)

$passwordLabel = New-Object System.Windows.Forms.Label
$passwordLabel.Text = "1C password (not saved)"
$passwordLabel.Location = New-Object System.Drawing.Point(294, 88)
$passwordLabel.AutoSize = $true
$form.Controls.Add($passwordLabel)

$passwordBox = New-Object System.Windows.Forms.TextBox
$passwordBox.Location = New-Object System.Drawing.Point(294, 110)
$passwordBox.Size = New-Object System.Drawing.Size(250, 24)
$passwordBox.UseSystemPasswordChar = $true
$form.Controls.Add($passwordBox)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = "Read-only. Finds a recent invoice for $supplierLabel and saves its full structure."
$statusLabel.Location = New-Object System.Drawing.Point(24, 156)
$statusLabel.Size = New-Object System.Drawing.Size(520, 54)
$form.Controls.Add($statusLabel)

$runButton = New-Object System.Windows.Forms.Button
$runButton.Text = "Run preflight (read-only)"
$runButton.Location = New-Object System.Drawing.Point(24, 232)
$runButton.Size = New-Object System.Drawing.Size(520, 40)
$form.Controls.Add($runButton)

$runButton.Add_Click({
    if ([string]::IsNullOrWhiteSpace($userBox.Text) -or [string]::IsNullOrWhiteSpace($passwordBox.Text)) {
        [System.Windows.Forms.MessageBox]::Show("Enter the dedicated 1C user and password.", "Missing data", "OK", "Warning")
        return
    }

    $runButton.Enabled = $false
    $statusLabel.Text = "Reading metadata and recent invoices for $supplierLabel from the test copy..."
    $form.Refresh()

    try {
        if ($testBaseUrl -notmatch '/khleb1c_test/') {
            throw "Safety check failed: the target is not khleb1c_test."
        }

        $credentialText = "{0}:{1}" -f $userBox.Text, $passwordBox.Text
        $credentialBytes = [System.Text.Encoding]::UTF8.GetBytes($credentialText)
        $authValue = [Convert]::ToBase64String($credentialBytes)
        $headers = @{ Authorization = "Basic $authValue" }

        $metadataResponse = Invoke-WebRequest -UseBasicParsing -Uri "$testBaseUrl/`$metadata" -Headers $headers -Method Get -TimeoutSec 60
        if ($metadataResponse.StatusCode -ne 200) {
            throw "Test metadata request returned HTTP $($metadataResponse.StatusCode)."
        }

        $filter = "Контрагент_Key eq guid'$counterpartyKey'"
        $query = "`$filter=$([Uri]::EscapeDataString($filter))&`$orderby=Date%20desc&`$top=100&`$format=json"
        $response = Invoke-RestMethod -UseBasicParsing -Uri "$testBaseUrl/Document_ПриходнаяНакладная`?$query" -Headers $headers -Method Get -TimeoutSec 90
        $documents = @($response.value)

        if ($documents.Count -eq 0) {
            throw "No incoming invoices for $supplierLabel were found in the test copy."
        }

        $normalizedSourceNumber = Get-NormalizedDigits $sourceDocumentNumber
        if ([string]::IsNullOrWhiteSpace($normalizedSourceNumber)) {
            $matches = @()
        }
        else {
            $matches = @($documents | Where-Object {
                ((Get-NormalizedDigits $_.Number) -eq $normalizedSourceNumber) -or
                ((Get-NormalizedDigits $_.'ВходящийНомерДокумента') -eq $normalizedSourceNumber)
            })
        }

        if ([string]::IsNullOrWhiteSpace($sourceDocumentDate)) {
            $datedMatches = @()
        }
        else {
            $datedMatches = @($documents | Where-Object {
                (([string]$_.Date) -like "$sourceDocumentDate*") -and (@($_.'Товары').Count -gt 0)
            })
        }
        $documentsWithLines = @($documents | Where-Object { @($_.'Товары').Count -gt 0 })

        if ($matches.Count -gt 0) {
            $sourceDocument = @($matches | Sort-Object Date -Descending)[0]
            $selectionReason = "configured document number"
        }
        elseif ($datedMatches.Count -gt 0) {
            $sourceDocument = @($datedMatches | Sort-Object Date -Descending)[0]
            $selectionReason = "configured document date"
        }
        elseif ($documentsWithLines.Count -gt 0) {
            $sourceDocument = @($documentsWithLines | Sort-Object Date -Descending)[0]
            $selectionReason = "latest supplier document with item lines"
        }
        else {
            $sourceDocument = @($documents | Sort-Object Date -Descending)[0]
            $selectionReason = "latest supplier document"
        }

        $outputDir = Join-Path $PSScriptRoot "test-write-preflight"
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

        [System.IO.File]::WriteAllText(
            (Join-Path $outputDir "metadata.xml"),
            $metadataResponse.Content,
            (New-Object System.Text.UTF8Encoding($false))
        )
        [System.IO.File]::WriteAllText(
            (Join-Path $outputDir "source-document.json"),
            ($sourceDocument | ConvertTo-Json -Depth 30),
            (New-Object System.Text.UTF8Encoding($false))
        )

        $documentIndex = @($documents | ForEach-Object {
            [pscustomobject][ordered]@{
                Date = $_.Date
                Number = $_.Number
                IncomingNumber = $_.'ВходящийНомерДокумента'
                Ref_Key = $_.Ref_Key
                ItemLineCount = @($_.'Товары').Count
            }
        })
        $documentIndex | Export-Csv -Path (Join-Path $outputDir "document-index.csv") -Delimiter ';' -NoTypeInformation -Encoding UTF8

        $summary = [ordered]@{
            exportedAt = (Get-Date).ToString("o")
            baseUrl = $testBaseUrl
            expectedDatabasePath = $expectedDatabasePath
            sourceDocumentNumber = $sourceDocument.Number
            sourceIncomingNumber = $sourceDocument.'ВходящийНомерДокумента'
            sourceDate = $sourceDocument.Date
            sourceRefKey = $sourceDocument.Ref_Key
            selectionReason = $selectionReason
            documentsScanned = $documents.Count
            matchingDocuments = $matches.Count
            containsBusinessValues = $true
            containsPassword = $false
            readOnly = $true
            writeAttempted = $false
        }
        [System.IO.File]::WriteAllText(
            (Join-Path $outputDir "summary.json"),
            ($summary | ConvertTo-Json -Depth 4),
            (New-Object System.Text.UTF8Encoding($false))
        )

        $passwordBox.Text = ""
        $statusLabel.Text = "Success. A source invoice and document list were saved."
        [System.Windows.Forms.MessageBox]::Show(
            "Read-only preflight succeeded. No 1C data was changed. Send the test-write-preflight folder to the developer.",
            "Success",
            "OK",
            "Information"
        )
    }
    catch {
        $passwordBox.Text = ""
        $statusLabel.Text = "The preflight failed. No 1C data was changed."
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Read-only preflight failed", "OK", "Error")
    }
    finally {
        $runButton.Enabled = $true
    }
})

[void]$form.ShowDialog()
