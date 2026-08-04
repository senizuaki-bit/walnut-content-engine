param(
    [switch]$TestAI,
    [string]$VariantId = ""
)

$ErrorActionPreference = "Stop"

$demoRoot = $PSScriptRoot
$godotExe = Join-Path $demoRoot "tools\godot-4.5.2\Godot_v4.5.2-stable_win64.exe"
$godotConsoleExe = Join-Path $demoRoot "tools\godot-4.5.2\Godot_v4.5.2-stable_win64_console.exe"
$nodeExe = Join-Path $demoRoot "tools\node\node.exe"
$projectDir = Join-Path $demoRoot "my_topdown_game-main"
$serverDir = Join-Path $demoRoot "xiao-hetao-ai-server"
$serverScript = Join-Path $serverDir "server.mjs"
$serverOut = Join-Path $serverDir "server.stdout.log"
$serverErr = Join-Path $serverDir "server.stderr.log"
$contentEngineDir = Join-Path $demoRoot "content-engine"
$contentPublisher = Join-Path $contentEngineDir "scripts\publish-from-feishu.mjs"
$contentWatcher = Join-Path $contentEngineDir "scripts\watch-feishu-publish.mjs"
$publisherOut = Join-Path $contentEngineDir "publisher.stdout.log"
$publisherErr = Join-Path $contentEngineDir "publisher.stderr.log"
$serverProcess = $null
$startedServer = $false
$publisherProcess = $null
$startedPublisher = $false

if (-not (Test-Path -LiteralPath $godotExe)) {
    $godotCandidates = @(Get-Command godot4.exe,godot.exe,Godot_v4.5.2-stable_win64.exe,Godot_v4.5.2-stable_win64_console.exe -CommandType Application -ErrorAction SilentlyContinue)
    if ($godotCandidates.Count -eq 0) {
        throw 'Godot 4.5.2 is missing. Add it to PATH or place the portable runtime under tools/godot-4.5.2.'
    }
    $godotExe = $godotCandidates[0].Source
}
if (-not (Test-Path -LiteralPath $godotConsoleExe)) {
    $godotConsoleExe = $godotExe
}
if (-not (Test-Path -LiteralPath $nodeExe)) {
    $nodeCandidates = @(Get-Command node.exe,node -CommandType Application -ErrorAction SilentlyContinue)
    if ($nodeCandidates.Count -gt 0) {
        $nodeExe = $nodeCandidates[0].Source
    }
}
$previousVariantId = [Environment]::GetEnvironmentVariable("XIAO_HETAO_VARIANT_ID", "Process")

if (-not (Test-Path -LiteralPath $godotExe)) {
    throw "Godot portable runtime is missing: $godotExe"
}

if (-not [string]::IsNullOrWhiteSpace($VariantId)) {
    $manifestPath = Join-Path $projectDir "content\generated\UNIT-DATA-GARDEN-LOOP.json"
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        throw "Content manifest is missing: $manifestPath"
    }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $knownVariantIds = @($manifest.transfer_variants | ForEach-Object { [string]$_.variant_id })
    if ($VariantId -notin $knownVariantIds) {
        throw "Unknown VariantId '$VariantId'. Available values: $($knownVariantIds -join ', ')"
    }
    $env:XIAO_HETAO_VARIANT_ID = $VariantId
    Write-Host "[data-garden] Selected transfer variant: $VariantId"
}

try {
    if ((Test-Path -LiteralPath $nodeExe) -and (Test-Path -LiteralPath $contentPublisher) -and (Get-Command lark-cli -ErrorAction SilentlyContinue)) {
        $oneShotOut = Join-Path $contentEngineDir "publisher-once.stdout.log"
        $oneShotErr = Join-Path $contentEngineDir "publisher-once.stderr.log"
        $oneShot = Start-Process -FilePath $nodeExe `
            -ArgumentList @($contentPublisher) `
            -WorkingDirectory $contentEngineDir `
            -WindowStyle Hidden `
            -RedirectStandardOutput $oneShotOut `
            -RedirectStandardError $oneShotErr `
            -Wait `
            -PassThru
        if ($oneShot.ExitCode -ne 0) {
            Write-Warning "飞书内容发布失败，继续使用上一个已验证版本。详情见 $oneShotErr"
        }
        $publisherProcess = Start-Process -FilePath $nodeExe `
            -ArgumentList @($contentWatcher) `
            -WorkingDirectory $contentEngineDir `
            -WindowStyle Hidden `
            -RedirectStandardOutput $publisherOut `
            -RedirectStandardError $publisherErr `
            -PassThru
        $startedPublisher = $true
    }

    $serverReady = $false
    try {
        $health = Invoke-RestMethod -Uri "http://127.0.0.1:8787/health" -TimeoutSec 1
        $serverReady = $health.status -eq "ok"
    } catch {
        $serverReady = $false
    }

    if (-not $serverReady -and (Test-Path -LiteralPath $nodeExe) -and (Test-Path -LiteralPath $serverScript)) {
        $serverProcess = Start-Process -FilePath $nodeExe `
            -ArgumentList @($serverScript) `
            -WorkingDirectory $serverDir `
            -WindowStyle Hidden `
            -RedirectStandardOutput $serverOut `
            -RedirectStandardError $serverErr `
            -PassThru
        $startedServer = $true

        for ($attempt = 0; $attempt -lt 20; $attempt++) {
            Start-Sleep -Milliseconds 150
            try {
                $health = Invoke-RestMethod -Uri "http://127.0.0.1:8787/health" -TimeoutSec 1
                if ($health.status -eq "ok") {
                    $serverReady = $true
                    break
                }
            } catch {
                if ($serverProcess.HasExited) { break }
            }
        }
    }

    $gameExecutable = if ($TestAI -and (Test-Path -LiteralPath $godotConsoleExe)) { $godotConsoleExe } else { $godotExe }
    $gameArguments = @("--rendering-method", "gl_compatibility", "--path", $projectDir)
    if ($TestAI) {
        $gameArguments = @("--headless", "--path", $projectDir, "--", "--demo-ai-test")
    }
    if ($TestAI) {
        $gameTestOut = Join-Path $serverDir "godot-ai-test.stdout.log"
        $gameTestErr = Join-Path $serverDir "godot-ai-test.stderr.log"
        $gameProcess = Start-Process -FilePath $gameExecutable `
            -ArgumentList $gameArguments `
            -WorkingDirectory $projectDir `
            -RedirectStandardOutput $gameTestOut `
            -RedirectStandardError $gameTestErr `
            -PassThru
    } else {
        $gameProcess = Start-Process -FilePath $gameExecutable `
            -ArgumentList $gameArguments `
            -WorkingDirectory $projectDir `
            -PassThru
    }
    $gameProcess.WaitForExit()
    if ($TestAI) {
        Get-Content -Encoding UTF8 $gameTestOut
        if ((Get-Item -LiteralPath $gameTestErr).Length -gt 0) {
            Get-Content -Encoding UTF8 $gameTestErr
        }
        if ($gameProcess.ExitCode -ne 0) { exit $gameProcess.ExitCode }
    }
} finally {
    if ($startedPublisher -and $null -ne $publisherProcess -and -not $publisherProcess.HasExited) {
        Stop-Process -Id $publisherProcess.Id
    }
    if ((Test-Path -LiteralPath $nodeExe) -and (Test-Path -LiteralPath $contentWatcher) -and (Get-Command lark-cli -ErrorAction SilentlyContinue)) {
        $finalSyncOut = Join-Path $contentEngineDir "publisher-final.stdout.log"
        $finalSyncErr = Join-Path $contentEngineDir "publisher-final.stderr.log"
        Start-Process -FilePath $nodeExe `
            -ArgumentList @($contentWatcher, "--once") `
            -WorkingDirectory $contentEngineDir `
            -WindowStyle Hidden `
            -RedirectStandardOutput $finalSyncOut `
            -RedirectStandardError $finalSyncErr `
            -Wait
    }
    if ($startedServer -and $null -ne $serverProcess -and -not $serverProcess.HasExited) {
        Stop-Process -Id $serverProcess.Id
    }
    if (-not [string]::IsNullOrWhiteSpace($VariantId)) {
        if ($null -eq $previousVariantId) {
            Remove-Item Env:XIAO_HETAO_VARIANT_ID -ErrorAction SilentlyContinue
        } else {
            $env:XIAO_HETAO_VARIANT_ID = $previousVariantId
        }
    }
}
