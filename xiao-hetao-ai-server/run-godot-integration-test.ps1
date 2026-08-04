$ErrorActionPreference = "Stop"

$demoRoot = Split-Path $PSScriptRoot -Parent
$nodeExe = Join-Path $demoRoot "tools\node\node.exe"
$godotExe = Join-Path $demoRoot "tools\godot-4.5.2\Godot_v4.5.2-stable_win64_console.exe"
$projectDir = Join-Path $demoRoot "my_topdown_game-main"
$serverScript = Join-Path $PSScriptRoot "server.mjs"
$serverProcess = $null

if (-not (Test-Path -LiteralPath $nodeExe)) {
    $nodeCandidates = @(Get-Command node.exe,node -CommandType Application -ErrorAction SilentlyContinue)
    if ($nodeCandidates.Count -eq 0) {
        throw 'Node.js 20+ is missing. Add it to PATH or place the portable runtime under tools/node.'
    }
    $nodeExe = $nodeCandidates[0].Source
}
if (-not (Test-Path -LiteralPath $godotExe)) {
    $godotCandidates = @(Get-Command godot4_console.exe,godot4.exe,godot.exe,Godot_v4.5.2-stable_win64_console.exe,Godot_v4.5.2-stable_win64.exe -CommandType Application -ErrorAction SilentlyContinue)
    if ($godotCandidates.Count -eq 0) {
        throw 'Godot 4.5.2 is missing. Add it to PATH or place the portable runtime under tools/godot-4.5.2.'
    }
    $godotExe = $godotCandidates[0].Source
}
$exitCode = 1
$integrationDataRoot = Join-Path $PSScriptRoot ".integration-data"
$testDataDir = Join-Path $integrationDataRoot ([guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $testDataDir -Force | Out-Null
$portProbe = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
$portProbe.Start()
$testPort = ([System.Net.IPEndPoint]$portProbe.LocalEndpoint).Port
$portProbe.Stop()
$testEndpoint = "http://127.0.0.1:$testPort"

$env:XIAO_HETAO_MOCK = "1"
$env:PORT = "$testPort"
$env:XIAO_HETAO_AI_ENDPOINT = "$testEndpoint/api/xiao-hetao/hint"
$env:XIAO_HETAO_EVENT_ENDPOINT = "$testEndpoint/api/learning-events"
$env:XIAO_HETAO_EVENT_DATA_DIR = $testDataDir
try {
    # Start-Process can fail on Windows when the inherited environment contains
    # both Path and PATH. ProcessStartInfo inherits the exact environment block
    # without PowerShell rebuilding it, so the local mock test remains stable.
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $nodeExe
    $startInfo.Arguments = '"' + $serverScript + '"'
    $startInfo.WorkingDirectory = $PSScriptRoot
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $serverProcess = [System.Diagnostics.Process]::new()
    $serverProcess.StartInfo = $startInfo
    if (-not $serverProcess.Start()) { throw "Xiao Hetao AI test server process did not start." }

    $ready = $false
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        Start-Sleep -Milliseconds 100
        try {
            $health = Invoke-RestMethod -Uri "$testEndpoint/health" -TimeoutSec 1
            if ($health.status -eq "ok" -and $health.mode -eq "mock") {
                $ready = $true
                break
            }
        } catch {
            if ($serverProcess.HasExited) { break }
        }
    }
    if (-not $ready) { throw "Xiao Hetao AI test server did not start." }

    $godotOutput = @(& $godotExe --headless --path $projectDir --rendering-method gl_compatibility --quit-after 3600 res://scenes/demo/data_garden/data_garden.tscn -- --demo-ai-test 2>&1)
    $exitCode = $LASTEXITCODE
    $godotOutput | ForEach-Object { Write-Output $_ }
    if ($exitCode -eq 0) {
        $godotText = $godotOutput -join "`n"
        if (-not $godotText.Contains("XIAO_HETAO_GODOT_AI_OK")) {
            throw "Godot did not report the AI contract marker."
        }
        if ($godotText -match "(?m)^(SCRIPT ERROR|ERROR:|WARNING:)") {
            throw "Godot AI integration emitted an error or warning."
        }
        $sessionMatch = [regex]::Match($godotText, "LEARNING_EVENT_GODOT_OK\s+(session_[A-Za-z0-9_-]+)")
        if (-not $sessionMatch.Success) { throw "Godot did not report a learning event session ID." }
        $sessionId = $sessionMatch.Groups[1].Value
        $summary = Invoke-RestMethod -Uri "$testEndpoint/api/learning-sessions/$sessionId" -TimeoutSec 3
        if (-not $summary.completed -or $summary.hint_requests -ne 1 -or $summary.event_count -lt 4) {
            throw "Learning event session aggregation did not match the Godot run."
        }
        Write-Output "LEARNING_EVENT_GODOT_SERVER_OK $sessionId"
    }
} finally {
    if ($null -ne $serverProcess -and -not $serverProcess.HasExited) {
        $serverProcess.Kill()
        $serverProcess.WaitForExit(5000) | Out-Null
    }
    Remove-Item Env:XIAO_HETAO_MOCK -ErrorAction SilentlyContinue
    Remove-Item Env:PORT -ErrorAction SilentlyContinue
    Remove-Item Env:XIAO_HETAO_AI_ENDPOINT -ErrorAction SilentlyContinue
    Remove-Item Env:XIAO_HETAO_EVENT_ENDPOINT -ErrorAction SilentlyContinue
    Remove-Item Env:XIAO_HETAO_EVENT_DATA_DIR -ErrorAction SilentlyContinue
    $dataRootFull = [System.IO.Path]::GetFullPath($integrationDataRoot)
    $testDataFull = [System.IO.Path]::GetFullPath($testDataDir)
    if ($testDataFull.StartsWith($dataRootFull, [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $testDataFull)) {
        Remove-Item -LiteralPath $testDataFull -Recurse -Force
    }
}

if ($exitCode -ne 0) {
    throw "Godot AI integration exited with code $exitCode."
}
