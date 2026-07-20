param(
    [switch]$ConfigOnly,
    [switch]$Yes
)

$ErrorActionPreference = "Stop"

$demoRoot = $PSScriptRoot
if (-not (Test-Path -LiteralPath (Join-Path $demoRoot "xiao-hetao-ai-server"))) {
    $parentRoot = Split-Path -Parent $PSScriptRoot
    if (Test-Path -LiteralPath (Join-Path $parentRoot "xiao-hetao-ai-server")) { $demoRoot = $parentRoot }
}

function Read-DotEnv {
    param([Parameter(Mandatory = $true)][string]$Path)
    $result = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $result }
    foreach ($line in [System.IO.File]::ReadAllLines($Path)) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith("#")) { continue }
        $separator = $trimmed.IndexOf("=")
        if ($separator -lt 1) { continue }
        $key = $trimmed.Substring(0, $separator).Trim()
        $value = $trimmed.Substring($separator + 1).Trim().Trim('"').Trim("'")
        $result[$key] = $value
    }
    return $result
}

$envPath = Join-Path $demoRoot "xiao-hetao-ai-server\.env"
$config = Read-DotEnv -Path $envPath
$required = @("ARK_API_KEY", "ARK_TEXT_API_URL", "ARK_TEXT_MODEL", "ARK_VISION_MODEL", "SKIN_IMAGE_API_URL", "SKIN_IMAGE_MODEL")
$missing = @($required | Where-Object { -not $config.ContainsKey($_) -or [string]::IsNullOrWhiteSpace([string]$config[$_]) })
if ($missing.Count -gt 0) {
    throw "火山引擎配置不完整：$($missing -join ', ')。请先运行 配置火山引擎.bat。"
}

Write-Host "WALNUT_VOLCENGINE_CONFIG_OK" -ForegroundColor Green
Write-Host "Text model: $($config['ARK_TEXT_MODEL'])"
Write-Host "Vision model: $($config['ARK_VISION_MODEL'])"
Write-Host "Image model: $($config['SKIN_IMAGE_MODEL'])"

if ($ConfigOnly) { exit 0 }
if (-not $Yes) {
    $answer = Read-Host "将发起一次很小的火山方舟文本请求，可能产生少量费用。继续？[y/N]"
    if ($answer -notmatch '^(y|yes)$') {
        Write-Host "已取消；本地配置检查通过，没有发起在线请求。"
        exit 0
    }
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$headers = @{ Authorization = "Bearer $($config['ARK_API_KEY'])" }
$body = @{
    model = $config["ARK_TEXT_MODEL"]
    messages = @(@{ role = "user"; content = "只回复 OK" })
    max_tokens = 16
    temperature = 0
    stream = $false
} | ConvertTo-Json -Depth 5

try {
    $response = Invoke-RestMethod `
        -Uri $config["ARK_TEXT_API_URL"] `
        -Method Post `
        -Headers $headers `
        -ContentType "application/json; charset=utf-8" `
        -Body $body `
        -TimeoutSec 45
    $content = [string]$response.choices[0].message.content
    if ([string]::IsNullOrWhiteSpace($content)) { throw "服务返回了空内容。" }
    Write-Host "WALNUT_VOLCENGINE_TEXT_OK" -ForegroundColor Green
    Write-Host "Model: $($response.model)"
} catch {
    throw "火山方舟连接验证失败。请检查 Key、余额、模型权限和模型 ID。详情：$($_.Exception.Message)"
}
