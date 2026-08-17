Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

$form = New-Object System.Windows.Forms.Form
$form.Text = "1C Bread Connector - read-only check"
$form.Size = New-Object System.Drawing.Size(560, 310)
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
$statusLabel.Text = "This check reads metadata only. It cannot change 1C data."
$statusLabel.Location = New-Object System.Drawing.Point(24, 150)
$statusLabel.Size = New-Object System.Drawing.Size(500, 40)
$form.Controls.Add($statusLabel)

$checkButton = New-Object System.Windows.Forms.Button
$checkButton.Text = "Run read-only check"
$checkButton.Location = New-Object System.Drawing.Point(24, 202)
$checkButton.Size = New-Object System.Drawing.Size(500, 38)
$form.Controls.Add($checkButton)

$checkButton.Add_Click({
    if ([string]::IsNullOrWhiteSpace($userBox.Text) -or [string]::IsNullOrWhiteSpace($passwordBox.Text)) {
        [System.Windows.Forms.MessageBox]::Show("Enter the dedicated 1C user and password.", "Missing data", "OK", "Warning")
        return
    }

    $checkButton.Enabled = $false
    $statusLabel.Text = "Checking the local 1C publication..."
    $form.Refresh()

    try {
        $baseUrl = $urlBox.Text.Trim().TrimEnd('/')
        $credentialText = "{0}:{1}" -f $userBox.Text, $passwordBox.Text
        $credentialBytes = [System.Text.Encoding]::UTF8.GetBytes($credentialText)
        $authValue = [Convert]::ToBase64String($credentialBytes)
        $headers = @{ Authorization = "Basic $authValue" }

        $metadataResponse = Invoke-WebRequest -UseBasicParsing -Uri "$baseUrl/`$metadata" -Headers $headers -Method Get -TimeoutSec 30
        if ($metadataResponse.StatusCode -ne 200) {
            throw "Metadata request returned HTTP $($metadataResponse.StatusCode)."
        }

        [xml]$metadataXml = $metadataResponse.Content
        $entityNodes = $metadataXml.SelectNodes("//*[local-name()='EntitySet']")
        $entityNames = @($entityNodes | ForEach-Object { $_.Name } | Where-Object { $_ } | Sort-Object -Unique)

        $diagnosticsDir = Join-Path $PSScriptRoot "diagnostics"
        New-Item -ItemType Directory -Path $diagnosticsDir -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $diagnosticsDir "metadata.xml"), $metadataResponse.Content, (New-Object System.Text.UTF8Encoding($false)))

        $summary = [ordered]@{
            checkedAt = (Get-Date).ToString("o")
            baseUrl = $baseUrl
            httpStatus = $metadataResponse.StatusCode
            entitySetCount = $entityNames.Count
            entitySets = $entityNames
            containsBusinessValues = $false
        }
        [System.IO.File]::WriteAllText((Join-Path $diagnosticsDir "summary.json"), ($summary | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding($false)))

        $passwordBox.Text = ""
        $statusLabel.Text = "Success. Metadata was saved to the diagnostics folder."
        [System.Windows.Forms.MessageBox]::Show("Read-only connection succeeded. No 1C data was changed. Send the diagnostics folder to the developer.", "Success", "OK", "Information")
    }
    catch {
        $passwordBox.Text = ""
        $statusLabel.Text = "The check failed. No 1C data was changed."
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Connection failed", "OK", "Error")
    }
    finally {
        $checkButton.Enabled = $true
    }
})

[void]$form.ShowDialog()
