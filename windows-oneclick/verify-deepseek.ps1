param(
    [switch]$Mock,
    [switch]$Yes
)

$ErrorActionPreference = "Stop"

$demoRoot = $PSScriptRoot
if (-not (Test-Path -LiteralPath (Join-Path $demoRoot "xiao-hetao-ai-server"))) {
    $parentRoot = Split-Path -Parent $PSScriptRoot
    if (Test-Path -LiteralPath (Join-Path $parentRoot "xiao-hetao-ai-server")) { $demoRoot = $parentRoot }
}
$serverDir = Join-Path $demoRoot "xiao-hetao-ai-server"
$serverScript = Join-Path $serverDir "server.mjs"
$nodeExe = Join-Path $demoRoot "tools\node\node.exe"
$envFile = Join-Path $serverDir ".env"
$stdoutLog = Join-Path $serverDir "live-check.stdout.log"
$stderrLog = Join-Path $serverDir "live-check.stderr.log"
$serverProcess = $null
$validationPort = 8788

if (-not (Test-Path -LiteralPath $nodeExe)) { throw "一键包内的 Node.js 不存在，请重新完整解压。" }
if (-not (Test-Path -LiteralPath $serverScript)) { throw "小核桃 AI 服务文件不存在，请重新完整解压。" }
if (-not $Mock -and -not (Test-Path -LiteralPath $envFile)) {
    Write-Host "尚未配置 DeepSeek，请先运行 配置DeepSeek密钥.bat。" -ForegroundColor Yellow
    exit 2
}

if (-not $Mock -and -not $Yes) {
    $answer = Read-Host "将发起一次很小的 DeepSeek 真实请求，可能产生少量费用。继续？[y/N]"
    if ($answer -notmatch '^(y|yes)$') {
        Write-Host "已取消；没有发起在线请求。"
        exit 0
    }
}

$env:PORT = [string]$validationPort
if ($Mock) { $env:XIAO_HETAO_MOCK = "1" }

try {
    $serverProcess = Start-Process -FilePath $nodeExe `
        -ArgumentList @($serverScript) `
        -WorkingDirectory $serverDir `
        -WindowStyle Hidden `
        -RedirectStandardOutput $stdoutLog `
        -RedirectStandardError $stderrLog `
        -PassThru

    $health = $null
    for ($attempt = 0; $attempt -lt 40; $attempt++) {
        Start-Sleep -Milliseconds 100
        try {
            $health = Invoke-RestMethod -Uri "http://127.0.0.1:$validationPort/health" -TimeoutSec 1
            if ($health.status -eq "ok") { break }
        } catch {
            if ($serverProcess.HasExited) { break }
        }
    }
    if ($null -eq $health -or $health.status -ne "ok") { throw "小核桃 AI 本地服务没有成功启动。" }
    if (-not $Mock -and $health.mode -ne "deepseek") { throw "本地服务没有检测到 DeepSeek API Key。" }

    $payload = @{
        student_id = "live_connection_check"
        age_band = "9-11"
        stage = "main_loop"
        repeat_count = 2
        lit_targets = 0
        failed_attempts = 0
        hint_requests = 1
        observation_done = $true
        action_selected = $true
        action_name = "grow"
    } | ConvertTo-Json

    $reply = Invoke-RestMethod `
        -Uri "http://127.0.0.1:$validationPort/api/xiao-hetao/hint" `
        -Method Post `
        -ContentType "application/json; charset=utf-8" `
        -Body $payload `
        -TimeoutSec 20

    if ($Mock) {
        if ($reply.source -ne "server_fallback") { throw "离线验证返回了意外来源。" }
        Write-Host "XIAO_HETAO_LIVE_VALIDATOR_MOCK_OK" -ForegroundColor Green
    } else {
        if ($reply.source -ne "deepseek") { throw "DeepSeek 没有返回已验证响应，请检查余额、Key、模型和网络。" }
        if ([string]::IsNullOrWhiteSpace([string]$reply.message)) { throw "DeepSeek 返回了空内容。" }
        Write-Host "XIAO_HETAO_DEEPSEEK_LIVE_OK" -ForegroundColor Green
        Write-Host "Model: $($reply.model)"
    }
} finally {
    if ($null -ne $serverProcess -and -not $serverProcess.HasExited) { Stop-Process -Id $serverProcess.Id }
    Remove-Item Env:PORT -ErrorAction SilentlyContinue
    Remove-Item Env:XIAO_HETAO_MOCK -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $stdoutLog, $stderrLog -Force -ErrorAction SilentlyContinue
}
