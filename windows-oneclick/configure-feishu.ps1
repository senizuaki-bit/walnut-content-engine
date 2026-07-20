param(
    [string]$BaseUrl = ""
)

$ErrorActionPreference = "Stop"

$demoRoot = $PSScriptRoot
if (-not (Test-Path -LiteralPath (Join-Path $demoRoot "content-engine"))) {
    $parentRoot = Split-Path -Parent $PSScriptRoot
    if (Test-Path -LiteralPath (Join-Path $parentRoot "content-engine")) { $demoRoot = $parentRoot }
}

function Invoke-LarkJson {
    param([Parameter(Mandatory = $true)][string[]]$CliArgs)
    $output = & lark-cli @CliArgs 2>&1
    $exitCode = $LASTEXITCODE
    $text = ($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
    if ($exitCode -ne 0) { throw "lark-cli 执行失败：$text" }
    try { return $text | ConvertFrom-Json } catch { throw "lark-cli 没有返回有效 JSON：$text" }
}

if (-not (Get-Command lark-cli -ErrorAction SilentlyContinue)) {
    throw "找不到 lark-cli。请先运行 npm install -g @larksuite/cli，关闭并重新打开 PowerShell。"
}

$configPath = Join-Path $demoRoot "content-engine\feishu\publish-config.json"
if (-not (Test-Path -LiteralPath $configPath)) { throw "找不到 content-engine/feishu/publish-config.json，请重新完整解压。" }
$current = Get-Content -Raw -Encoding UTF8 -LiteralPath $configPath | ConvertFrom-Json

$status = Invoke-LarkJson -CliArgs @("auth", "status", "--json", "--verify")
if ($status.identities.user.status -ne "ready" -or $status.identities.user.tokenStatus -ne "valid") {
    throw "飞书用户授权尚未就绪。请按教程运行 lark-cli auth login --domain base --no-wait --json。"
}

if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
    $BaseUrl = Read-Host "粘贴目标飞书多维表格链接（直接回车使用预置演示 Base：$($current.base_url)）"
    if ([string]::IsNullOrWhiteSpace($BaseUrl)) { $BaseUrl = [string]$current.base_url }
}
if ($BaseUrl -notmatch '^https://') { throw "请输入完整的 https:// 飞书多维表格链接。" }

$resolved = Invoke-LarkJson -CliArgs @("base", "+url-resolve", "--url", $BaseUrl, "--as", "user", "--format", "json")
if (-not $resolved.ok -or [string]::IsNullOrWhiteSpace([string]$resolved.data.base_token)) { throw "无法从链接解析 Base token。" }
$baseToken = [string]$resolved.data.base_token

$tableResponse = Invoke-LarkJson -CliArgs @("base", "+table-list", "--base-token", $baseToken, "--as", "user", "--format", "json")
if (-not $tableResponse.ok) { throw "无法读取目标 Base 的数据表。" }
$tableByName = @{}
foreach ($table in @($tableResponse.data.tables)) { $tableByName[[string]$table.name] = [string]$table.id }

$requiredTables = [ordered]@{
    content_units = "内容单元"
    misconceptions = "误区库"
    hints = "提示策略"
    classroom_evidence = "课堂证据"
}
$missingTables = @($requiredTables.Values | Where-Object { -not $tableByName.ContainsKey([string]$_) })
if ($missingTables.Count -gt 0) { throw "目标 Base 缺少数据表：$($missingTables -join '、')。" }

$unitId = if ([string]::IsNullOrWhiteSpace([string]$current.unit_id)) { "UNIT-DATA-GARDEN-LOOP" } else { [string]$current.unit_id }
$unitTableId = $tableByName["内容单元"]
$recordResponse = Invoke-LarkJson -CliArgs @("base", "+record-list", "--base-token", $baseToken, "--table-id", $unitTableId, "--field-id", "单元ID", "--limit", "200", "--as", "user", "--format", "json")
if (-not $recordResponse.ok) { throw "无法读取内容单元记录。" }

$recordIds = @($recordResponse.data.record_id_list)
$rows = @($recordResponse.data.data)
$unitRecordId = $null
for ($index = 0; $index -lt $recordIds.Count; $index++) {
    $row = @($rows[$index])
    if ($row.Count -gt 0 -and [string]$row[0] -eq $unitId) {
        $unitRecordId = [string]$recordIds[$index]
        break
    }
}
if ([string]::IsNullOrWhiteSpace($unitRecordId)) { throw "内容单元表中找不到 单元ID=$unitId。" }

$newConfig = [ordered]@{
    base_url = $BaseUrl
    base_token = $baseToken
    unit_id = $unitId
    unit_record_id = $unitRecordId
    poll_interval_ms = if ($current.poll_interval_ms) { [int]$current.poll_interval_ms } else { 3000 }
    tables = [ordered]@{
        content_units = $tableByName["内容单元"]
        misconceptions = $tableByName["误区库"]
        hints = $tableByName["提示策略"]
        classroom_evidence = $tableByName["课堂证据"]
    }
}
$json = $newConfig | ConvertTo-Json -Depth 5
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($configPath, "$json`n", $utf8NoBom)

Write-Host ""
Write-Host "飞书多维表格配置完成。" -ForegroundColor Green
Write-Host "Base: $BaseUrl"
Write-Host "内容单元记录: $unitId / $unitRecordId"
Write-Host "本步骤只读取了云端结构；没有修改任何飞书记录。"
Write-Host "下一步：运行 验证飞书多维表格连接.bat"
