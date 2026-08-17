$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

. (Join-Path $PSScriptRoot "local-business-config.ps1")
try {
    $businessConfig = Get-LocalBusinessConfig -RequireTestInvoice
}
catch {
    [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "Local configuration required", "OK", "Error")
    exit 1
}

$testBaseUrl = "http://localhost/khleb1c_test/odata/standard.odata"
$testVrdPath = "C:\Apache24\htdocs\khleb1c_test\default.vrd"
$expectedDatabasePath = "C:\Baze_Test_Hleb"
$supplierLabel = [string]$businessConfig.supplierLabel
$testInvoiceConfig = $businessConfig.testInvoice
$testMarker = [string]$testInvoiceConfig.marker
$zeroGuid = "00000000-0000-0000-0000-000000000000"

function New-ItemLine {
    param(
        [string]$DocumentKey,
        [int]$LineNumber,
        [string]$UnitKey,
        [string]$ItemKey,
        [double]$Quantity,
        [double]$PurchasePrice,
        [double]$MarkupPercent,
        [double]$RetailPrice,
        [string]$VatRateKey
    )

    $purchaseAmount = [Math]::Round($Quantity * $PurchasePrice, 2, [MidpointRounding]::AwayFromZero)
    $retailAmount = [Math]::Round($Quantity * $RetailPrice, 2, [MidpointRounding]::AwayFromZero)

    return [ordered]@{
        "Ref_Key" = $DocumentKey
        "LineNumber" = $LineNumber
        "ВидАлкогольнойПродукции_Key" = $zeroGuid
        "Всего" = $PurchaseAmount
        "ВсегоПоДокументам" = 0
        "ГТД_Key" = $zeroGuid
        "Единица_Key" = $UnitKey
        "Количество" = $Quantity
        "КоличествоПоДокументам" = 0
        "Коэффициент" = 1
        "Номенклатура_Key" = $ItemKey
        "НоменклатураПоставщика_Key" = $zeroGuid
        "ПриходнаяСумма" = $PurchaseAmount
        "ПриходнаяЦена" = $PurchasePrice
        "ПричинаОтказа_Key" = $zeroGuid
        "Производитель_Key" = $zeroGuid
        "ПроцентНаценки" = $MarkupPercent
        "РозничнаяСумма" = $RetailAmount
        "РозничнаяЦена" = $RetailPrice
        "СертификатСоответствия_Key" = $zeroGuid
        "СтавкаНДС_Key" = $VatRateKey
        "СтатьяРасходов_Key" = $zeroGuid
        "СтранаПроисхождения_Key" = $zeroGuid
        "СуммаНДС" = 0
        "УникальныйНомерСтрокиДокумента" = $LineNumber
        "ХарактеристикаНоменклатуры_Key" = $zeroGuid
    }
}

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

function Find-TestDocument {
    param([hashtable]$Headers)

    $filter = "ВходящийНомерДокумента eq '$testMarker'"
    $query = "`$filter=$([Uri]::EscapeDataString($filter))&`$top=2&`$format=json"
    $response = Invoke-RestMethod -UseBasicParsing -Uri "$testBaseUrl/Document_ПриходнаяНакладная`?$query" -Headers $Headers -Method Get -TimeoutSec 60
    return @($response.value)
}

$configuredItems = @($testInvoiceConfig.items)
$configuredPurchaseTotal = 0.0
$configuredRetailTotal = 0.0
foreach ($configuredItem in $configuredItems) {
    $configuredPurchaseTotal += [double]$configuredItem.quantity * [double]$configuredItem.purchasePrice
    $configuredRetailTotal += [double]$configuredItem.quantity * [double]$configuredItem.retailPrice
}
$configuredPurchaseTotal = [Math]::Round($configuredPurchaseTotal, 2, [MidpointRounding]::AwayFromZero)
$configuredRetailTotal = [Math]::Round($configuredRetailTotal, 2, [MidpointRounding]::AwayFromZero)

$form = New-Object System.Windows.Forms.Form
$form.Text = "1C Bread Connector - create unposted TEST invoice"
$form.Size = New-Object System.Drawing.Size(600, 410)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false

$targetLabel = New-Object System.Windows.Forms.Label
$targetLabel.Text = "WRITE TEST: C:\Baze_Test_Hleb ONLY"
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

$detailsLabel = New-Object System.Windows.Forms.Label
$detailsLabel.Text = "Creates one UNPOSTED invoice: $supplierLabel, $($configuredItems.Count) lines, purchase total $configuredPurchaseTotal RUB.`r`nMarker: $testMarker. Re-running cannot create a duplicate with this marker."
$detailsLabel.Location = New-Object System.Drawing.Point(24, 158)
$detailsLabel.Size = New-Object System.Drawing.Size(540, 58)
$form.Controls.Add($detailsLabel)

$statusLabel = New-Object System.Windows.Forms.Label
$statusLabel.Text = "No write has been attempted."
$statusLabel.Location = New-Object System.Drawing.Point(24, 228)
$statusLabel.Size = New-Object System.Drawing.Size(540, 52)
$form.Controls.Add($statusLabel)

$createButton = New-Object System.Windows.Forms.Button
$createButton.Text = "Create ONE unposted TEST invoice"
$createButton.Location = New-Object System.Drawing.Point(24, 296)
$createButton.Size = New-Object System.Drawing.Size(540, 42)
$form.Controls.Add($createButton)

$createButton.Add_Click({
    if ([string]::IsNullOrWhiteSpace($userBox.Text) -or [string]::IsNullOrWhiteSpace($passwordBox.Text)) {
        [System.Windows.Forms.MessageBox]::Show("Enter the dedicated 1C user and password.", "Missing data", "OK", "Warning")
        return
    }

    $createButton.Enabled = $false
    $statusLabel.Text = "Running safety checks against the test copy..."
    $form.Refresh()
    $writeAttempted = $false

    try {
        if ($testBaseUrl -ne "http://localhost/khleb1c_test/odata/standard.odata") {
            throw "Safety check failed: unexpected OData address."
        }
        if (-not (Test-Path -LiteralPath $testVrdPath -PathType Leaf)) {
            throw "Safety check failed: test publication default.vrd was not found."
        }

        $vrdText = [System.IO.File]::ReadAllText($testVrdPath)
        if (-not $vrdText.Contains('base="/khleb1c_test"')) {
            throw "Safety check failed: default.vrd has an unexpected publication base."
        }
        if (-not $vrdText.Contains('ib="File=&quot;C:\Baze_Test_Hleb&quot;;"')) {
            throw "Safety check failed: default.vrd is not connected to C:\Baze_Test_Hleb."
        }
        if (-not $vrdText.Contains('<standardOdata enable="true"')) {
            throw "Safety check failed: standard OData is not enabled in the test publication."
        }

        $headers = Get-AuthHeaders -UserName $userBox.Text -Password $passwordBox.Text
        $metadataResponse = Invoke-WebRequest -UseBasicParsing -Uri "$testBaseUrl/`$metadata" -Headers $headers -Method Get -TimeoutSec 60
        if ($metadataResponse.StatusCode -ne 200) {
            throw "Test metadata request returned HTTP $($metadataResponse.StatusCode)."
        }

        $existing = Find-TestDocument -Headers $headers
        if ($existing.Count -gt 0) {
            $passwordBox.Text = ""
            $statusLabel.Text = "The test invoice already exists. No duplicate was created."
            [System.Windows.Forms.MessageBox]::Show(
                "The test invoice already exists. Number: $($existing[0].Number). Ref_Key: $($existing[0].Ref_Key). No duplicate was created.",
                "Already exists",
                "OK",
                "Information"
            )
            return
        }

        $confirmation = [System.Windows.Forms.MessageBox]::Show(
            "Create ONE UNPOSTED invoice in C:\Baze_Test_Hleb?`r`n`r`nSupplier: $supplierLabel`r`n$($configuredItems.Count) item lines`r`nPurchase total: $configuredPurchaseTotal RUB`r`nMarker: $testMarker`r`n`r`nThe document will NOT be posted.",
            "Confirm TEST write",
            "YesNo",
            "Warning"
        )
        if ($confirmation -ne [System.Windows.Forms.DialogResult]::Yes) {
            $passwordBox.Text = ""
            $statusLabel.Text = "Cancelled. No write was attempted."
            return
        }

        $newDocumentKey = [Guid]::NewGuid().ToString()
        $now = Get-Date
        $dateText = $now.ToString("yyyy-MM-ddTHH:mm:ss")
        $paymentDateText = $now.Date.ToString("yyyy-MM-ddTHH:mm:ss")

        $items = @()
        for ($itemIndex = 0; $itemIndex -lt $configuredItems.Count; $itemIndex++) {
            $configuredItem = $configuredItems[$itemIndex]
            $items += New-ItemLine `
                -DocumentKey $newDocumentKey `
                -LineNumber ($itemIndex + 1) `
                -UnitKey ([string]$configuredItem.unitKey) `
                -ItemKey ([string]$configuredItem.itemKey) `
                -Quantity ([double]$configuredItem.quantity) `
                -PurchasePrice ([double]$configuredItem.purchasePrice) `
                -MarkupPercent ([double]$configuredItem.markupPercent) `
                -RetailPrice ([double]$configuredItem.retailPrice) `
                -VatRateKey ([string]$testInvoiceConfig.vatRateKey)
        }

        $payload = [ordered]@{
            "Ref_Key" = $newDocumentKey
            "Date" = $dateText
            "DeletionMark" = $false
            "Posted" = $false
            "Валюта_Key" = [string]$testInvoiceConfig.currencyKey
            "ВариантРасчетаНДС" = "ВСумме"
            "ВидРаспределенияЗаказовПоставщику" = "НеРаспределять"
            "ВходящаяДатаДокумента" = $paymentDateText
            "ВходящийНомерДокумента" = $testMarker
            "ДатаОплаты" = $paymentDateText
            "Договор_Key" = [string]$testInvoiceConfig.contractKey
            "Комментарий" = "ТЕСТ ХЛЕБ. НЕ ПРОВОДИТЬ. $testMarker"
            "Контрагент_Key" = [string]$businessConfig.counterpartyKey
            "Кратность" = 1
            "КратностьВзаиморасчетов" = 1
            "Курс" = 1
            "КурсВзаиморасчетов" = 1
            "Склад_Key" = [string]$testInvoiceConfig.warehouseKey
            "СуммаВВалютеДоговора" = $configuredPurchaseTotal
            "СуммаДокументаПрих" = $configuredPurchaseTotal
            "СуммаДокументаРозница" = $configuredRetailTotal
            "СуммаНДС" = 0
            "ТипЦен_Key" = [string]$testInvoiceConfig.priceTypeKey
            "ТорговыйОбъект_Key" = [string]$testInvoiceConfig.tradeObjectKey
            "Фирма_Key" = [string]$testInvoiceConfig.companyKey
            "Товары" = $items
        }

        $jsonBody = $payload | ConvertTo-Json -Depth 12
        $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($jsonBody)
        $outputDir = Join-Path $PSScriptRoot "test-create-result"
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $outputDir "request.json"), $jsonBody, (New-Object System.Text.UTF8Encoding($false)))

        $writeAttempted = $true
        $createResponse = Invoke-RestMethod -UseBasicParsing -Uri "$testBaseUrl/Document_ПриходнаяНакладная?`$format=json" -Headers $headers -Method Post -ContentType "application/json; charset=utf-8" -Body $bodyBytes -TimeoutSec 120

        $created = Find-TestDocument -Headers $headers
        if ($created.Count -ne 1) {
            throw "The POST request returned, but exactly one test document could not be verified. Do not run the test again until the result is checked."
        }
        if ($created[0].Posted -ne $false) {
            throw "Safety verification failed: the created document is unexpectedly posted. Do not continue."
        }

        [System.IO.File]::WriteAllText((Join-Path $outputDir "response.json"), ($createResponse | ConvertTo-Json -Depth 20), (New-Object System.Text.UTF8Encoding($false)))
        $summary = [ordered]@{
            createdAt = (Get-Date).ToString("o")
            baseUrl = $testBaseUrl
            verifiedDatabasePath = $expectedDatabasePath
            marker = $testMarker
            Ref_Key = $created[0].Ref_Key
            Number = $created[0].Number
            Date = $created[0].Date
            Posted = $created[0].Posted
            purchaseTotal = $created[0].'СуммаДокументаПрих'
            itemLineCount = @($created[0].'Товары').Count
            containsPassword = $false
        }
        [System.IO.File]::WriteAllText((Join-Path $outputDir "summary.json"), ($summary | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding($false)))

        $passwordBox.Text = ""
        $statusLabel.Text = "Success. One unposted test invoice was created and verified."
        [System.Windows.Forms.MessageBox]::Show(
            "Success. One UNPOSTED test invoice was created in C:\Baze_Test_Hleb.`r`n`r`nNumber: $($created[0].Number)`r`nRef_Key: $($created[0].Ref_Key)`r`n`r`nSend the test-create-result folder to the developer.",
            "TEST write succeeded",
            "OK",
            "Information"
        )
    }
    catch {
        $passwordBox.Text = ""
        if ($writeAttempted) {
            $statusLabel.Text = "A write was attempted. Do not rerun until the result is checked."
            $errorPrefix = "A TEST write was attempted. Do not rerun the connector yet."
        }
        else {
            $statusLabel.Text = "The safety check failed. No write was attempted."
            $errorPrefix = "No write was attempted."
        }
        [System.Windows.Forms.MessageBox]::Show("$errorPrefix`r`n`r`n$($_.Exception.Message)", "TEST write result", "OK", "Error")
    }
    finally {
        $createButton.Enabled = $true
    }
})

[void]$form.ShowDialog()
