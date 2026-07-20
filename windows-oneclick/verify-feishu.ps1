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
if (-not (Test-Path -LiteralPath $configPath)) { throw "找不到飞书发布配置，请重新完整解压。" }
$config = Get-Content -Raw -Encoding UTF8 -LiteralPath $configPath | ConvertFrom-Json

$status = Invoke-LarkJson -CliArgs @("auth", "status", "--json", "--verify")
if ($status.identities.user.status -ne "ready" -or $status.identities.user.tokenStatus -ne "valid") {
    throw "飞书用户授权未就绪或已过期，请重新登录。"
}
$scopeSet = @{}
foreach ($scope in ([string]$status.identities.user.scope -split '\s+')) { if ($scope) { $scopeSet[$scope] = $true } }
$requiredScopes = @("base:app:read", "base:table:read", "base:record:read")
$missingScopes = @($requiredScopes | Where-Object { -not $scopeSet.ContainsKey($_) })
if ($missingScopes.Count -gt 0) { throw "飞书授权缺少只读权限：$($missingScopes -join ', ')。请重新授权 base 域。" }

$tableResponse = Invoke-LarkJson -CliArgs @("base", "+table-list", "--base-token", [string]$config.base_token, "--as", "user", "--format", "json")
if (-not $tableResponse.ok) { throw "无法读取已配置 Base 的数据表。" }
$tables = @{}
foreach ($table in @($tableResponse.data.tables)) { $tables[[string]$table.id] = [string]$table.name }

$expected = [ordered]@{
    content_units = "内容单元"
    misconceptions = "误区库"
    hints = "提示策略"
    classroom_evidence = "课堂证据"
}
foreach ($key in $expected.Keys) {
    $tableId = [string]$config.tables.$key
    if (-not $tables.ContainsKey($tableId)) { throw "配置中的表 ID 不存在：$key=$tableId。请重新运行配置向导。" }
    if ($tables[$tableId] -ne $expected[$key]) {
        throw ('表 ID {0} 实际对应「{1}」，预期「{2}」。' -f $tableId, $tables[$tableId], $expected[$key])
    }
}

$recordResponse = Invoke-LarkJson -CliArgs @(
    "base", "+record-get",
    "--base-token", [string]$config.base_token,
    "--table-id", [string]$config.tables.content_units,
    "--record-id", [string]$config.unit_record_id,
    "--field-id", "单元ID",
    "--as", "user",
    "--format", "json"
)
if (-not $recordResponse.ok) { throw "无法读取已配置的内容单元记录。" }

Write-Host "WALNUT_FEISHU_CONNECTION_OK" -ForegroundColor Green
Write-Host "Base: $($config.base_url)"
Write-Host "Unit: $($config.unit_id) / $($config.unit_record_id)"
Write-Host "六表结构中的发布必需表和目标记录均可读取；本检查没有写入云端。"
