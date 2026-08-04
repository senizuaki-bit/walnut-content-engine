param(
    [Parameter(Mandatory = $true)]
    [string]$OutboxPath,
    [string]$BaseToken = "A7IcbT6oHaUKXIsAjHrcrlhinwg",
    [string]$TableId = "tblmEnpQOZDuyMAX",
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$resolvedPath = (Resolve-Path -LiteralPath $OutboxPath).Path
$currentDirectory = [System.IO.Path]::GetFullPath((Get-Location).Path + [System.IO.Path]::DirectorySeparatorChar)
if (-not $resolvedPath.StartsWith($currentDirectory, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "飞书 outbox 必须位于当前工作目录内。"
}
$relativeJsonPath = $resolvedPath.Substring($currentDirectory.Length).Replace("\", "/")
$jsonArgument = "@./$relativeJsonPath"
$jsonText = Get-Content -LiteralPath $resolvedPath -Raw -Encoding UTF8
$fields = $jsonText | ConvertFrom-Json
$sessionId = [string]$fields."会话ID"
if ([string]::IsNullOrWhiteSpace($sessionId)) {
    throw "飞书 outbox 缺少会话ID。"
}

$searchArgs = @(
    "base", "+record-search",
    "--base-token", $BaseToken,
    "--table-id", $TableId,
    "--keyword", $sessionId,
    "--search-field", "会话ID",
    "--field-id", "会话ID",
    "--limit", "20",
    "--format", "json",
    "--as", "user"
)
$searchOutput = (& lark-cli @searchArgs | Out-String) | ConvertFrom-Json
if (-not $searchOutput.ok) {
    throw "查询飞书课堂证据失败。"
}

$matchingRecordIds = @()
for ($index = 0; $index -lt $searchOutput.data.record_id_list.Count; $index++) {
    if ([string]$searchOutput.data.data[$index][0] -eq $sessionId) {
        $matchingRecordIds += [string]$searchOutput.data.record_id_list[$index]
    }
}
if ($matchingRecordIds.Count -gt 1) {
    throw "会话ID $sessionId 在飞书中存在多条记录，已停止避免覆盖错误记录。"
}

$writeArgs = @(
    "base", "+record-upsert",
    "--base-token", $BaseToken,
    "--table-id", $TableId,
    "--json", $jsonArgument,
    "--as", "user"
)
if ($matchingRecordIds.Count -eq 1) {
    $writeArgs += @("--record-id", $matchingRecordIds[0])
}
if ($DryRun) {
    $writeArgs += "--dry-run"
}

& lark-cli @writeArgs
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
$mode = if ($DryRun) { "dry-run" } elseif ($matchingRecordIds.Count -eq 1) { "updated" } else { "created" }
Write-Output "FEISHU_SESSION_SYNC_OK $sessionId $mode"
