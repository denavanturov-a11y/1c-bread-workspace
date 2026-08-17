$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

$testBaseUrl = "http://localhost/khleb1c_test/odata/standard.odata"
$testVrdPath = "C:\Apache24\htdocs\khleb1c_test\default.vrd"
$expectedDatabasePath = "C:\Baze_Test_Hleb"

function Get-AuthHeaders {
    param([string]$UserName, [string]$Password)

    $credentialText = "{0}:{1}" -f $UserName, $Password
    $credentialBytes = [System.Text.Encoding]::UTF8.GetBytes($credentialText)
    $authValue = [Convert]::ToBase64String($credentialBytes)
    return @{
        Authorization = "Basic $authValue"
        Accept = "application/json"
    }
}

function Resolve-RequestPath {
    $defaultPath = Join-Path $PSScriptRoot "test-create-result\request.json"
    if (Test-Path -LiteralPath $defaultPath -PathType Leaf) {
        return $defaultPath
    }

    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = "Select request.json from test-create-result"
    $dialog.Filter = "request.json|request.json|JSON files (*.json)|*.json"
    $dialog.Multiselect = $false
    if ($dialog.ShowDialog() -ne [System.Windows.Forms.DialogResult]::OK) {
        return $null
    }
    return $dialog.FileName
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "1C Bread Connector - verify TEST write"
$form.Size = New-Object System.Drawing.Size(600, 370)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

$targetLabel = New-Object System.Windows.Forms.Label
$targetLabel.Text = "READ-ONLY VERIFICATION: C:\Baze_Test_Hleb"
$targetLabel.Location = New-Object System.Drawing.Point(24, 20)
$targetLabel.AutoSize = $true
$targetLabel.Font = New-Object System.Drawing.Font($targetLabel.Font, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($targetLabel)

$urlBox = New-Object System.Windows.Forms.TextBox
$urlBox.Text = $testBaseUrl
$urlBox.Location = New-Object System.Drawing.Point(24, 46)
$urlBox.Size = New-Object System.Drawing.Size(540, 24)
$urlBox.ReadOnly = $true
$form.Controls.Add($urlBox)

$userLabel = New-Object System.Windows.Forms.Label
$userLabel.Text = "1C user"
$userLabel.Location = New-Object System.Drawing.Point(24, 90)
$userLabel.AutoSize = $true
$form.Controls.Add($userLabel)

$userBox = New-Object System.Windows.Forms.TextBox
$userBox.Location = New-Object System.Drawing.Point(24, 112)
$userBox.Size = New-Object System.Drawing.Size(260, 24)
$form.Controls.Add($userBox)

$passwordLabel = New-Object System.Windows.Forms.Label
$passwordLabel.Text = "1C password (not saved)"
$passwordLabel.Location = New-Object System.Drawing.Point(304, 90)
$passwordLabel.AutoSize = $true
$form.Controls.Add($passwordLabel)

$passwordBox = New-Object System.Windows.Forms.TextBox
$passwordBox.Location = New-Object System.Drawing.Point(304, 112)
$passwordBox.Size = New-Object System.Drawing.Size(260, 24)
$passwordBox.UseSystemPasswordChar = $true
$form.Controls.Add($passwordBox)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = "Only reads the exact Ref_Key stored in test-create-result\request.json."
$statusLabel.Location = New-Object System.Drawing.Point(24, 158)
$statusLabel.Size = New-Object System.Drawing.Size(540, 68)
$form.Controls.Add($statusLabel)

$verifyButton = New-Object System.Windows.Forms.Button
$verifyButton.Text = "Verify created document (read-only)"
$verifyButton.Location = New-Object System.Drawing.Point(24, 252)
$verifyButton.Size = New-Object System.Drawing.Size(540, 42)
$form.Controls.Add($verifyButton)

$verifyButton.Add_Click({
    if ([string]::IsNullOrWhiteSpace($userBox.Text) -or [string]::IsNullOrWhiteSpace($passwordBox.Text)) {
        [System.Windows.Forms.MessageBox]::Show("Enter the dedicated 1C user and password.", "Missing data", "OK", "Warning")
        return
    }

    $verifyButton.Enabled = $false
    $statusLabel.Text = "Checking the exact document key in the test copy..."
    $form.Refresh()

    try {
        if (-not (Test-Path -LiteralPath $testVrdPath -PathType Leaf)) {
            throw "Safety check failed: test publication default.vrd was not found."
        }
        $vrdText = [System.IO.File]::ReadAllText($testVrdPath)
        if (-not $vrdText.Contains('base="/khleb1c_test"') -or -not $vrdText.Contains('ib="File=&quot;C:\Baze_Test_Hleb&quot;;"')) {
            throw "Safety check failed: khleb1c_test is not connected to C:\Baze_Test_Hleb."
        }

        $requestPath = Resolve-RequestPath
        if ([string]::IsNullOrWhiteSpace($requestPath)) {
            $passwordBox.Text = ""
            $statusLabel.Text = "Cancelled. No request was sent."
            return
        }

        $requestPayload = Get-Content -LiteralPath $requestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $refKey = [string]$requestPayload.Ref_Key
        if ($refKey -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
            throw "request.json does not contain a valid Ref_Key."
        }

        $headers = Get-AuthHeaders -UserName $userBox.Text -Password $passwordBox.Text
        $documentUrl = "$testBaseUrl/Document_ПриходнаяНакладная(guid'$refKey')?`$format=json"
        $document = Invoke-RestMethod -UseBasicParsing -Uri $documentUrl -Headers $headers -Method Get -TimeoutSec 60

        $outputDir = Split-Path -Parent $requestPath
        [System.IO.File]::WriteAllText((Join-Path $outputDir "verification.json"), ($document | ConvertTo-Json -Depth 30), (New-Object System.Text.UTF8Encoding($false)))

        $summary = [ordered]@{
            verifiedAt = (Get-Date).ToString("o")
            baseUrl = $testBaseUrl
            verifiedDatabasePath = $expectedDatabasePath
            Ref_Key = $document.Ref_Key
            Number = $document.Number
            Date = $document.Date
            Posted = $document.Posted
            marker = $document.'ВходящийНомерДокумента'
            comment = $document.'Комментарий'
            purchaseTotal = $document.'СуммаДокументаПрих'
            retailTotal = $document.'СуммаДокументаРозница'
            itemLineCount = @($document.'Товары').Count
            readOnly = $true
            containsPassword = $false
        }
        [System.IO.File]::WriteAllText((Join-Path $outputDir "verification-summary.json"), ($summary | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding($false)))

        $passwordBox.Text = ""
        if ($document.Posted -eq $false) {
            $statusLabel.Text = "Verified: the document exists and is unposted."
            $resultTitle = "TEST document verified"
        }
        else {
            $statusLabel.Text = "WARNING: the document exists but is posted. Stop testing."
            $resultTitle = "Unexpected posted state"
        }
        [System.Windows.Forms.MessageBox]::Show(
            "Document found in C:\Baze_Test_Hleb.`r`n`r`nNumber: $($document.Number)`r`nRef_Key: $($document.Ref_Key)`r`nPosted: $($document.Posted)`r`nPurchase total: $($document.'СуммаДокументаПрих')`r`nLines: $(@($document.'Товары').Count)`r`n`r`nSend the test-create-result folder to the developer.",
            $resultTitle,
            "OK",
            "Information"
        )
    }
    catch {
        $passwordBox.Text = ""
        $statusLabel.Text = "Read-only verification failed. No data was changed."
        [System.Windows.Forms.MessageBox]::Show("No data was changed.`r`n`r`n$($_.Exception.Message)", "Verification failed", "OK", "Error")
    }
    finally {
        $verifyButton.Enabled = $true
    }
})

[void]$form.ShowDialog()
