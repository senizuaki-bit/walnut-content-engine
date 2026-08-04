[CmdletBinding()]
param(
    [switch]$SkipNode,
    [switch]$SkipAI
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$workspaceRoot = $PSScriptRoot
$projectRoot = Join-Path $workspaceRoot "my_topdown_game-main"
$godotExe = Join-Path $workspaceRoot "tools\godot-4.5.2\Godot_v4.5.2-stable_win64_console.exe"
$nodeExe = Join-Path $workspaceRoot "tools\node\node.exe"
$logRoot = Join-Path $projectRoot "qa\logs\final"
$script:passedCases = 0

if (-not (Test-Path -LiteralPath $godotExe)) {
    $godotCandidates = @(Get-Command godot4_console.exe,godot4.exe,godot.exe,Godot_v4.5.2-stable_win64_console.exe,Godot_v4.5.2-stable_win64.exe -CommandType Application -ErrorAction SilentlyContinue)
    if ($godotCandidates.Count -eq 0) {
        throw 'Godot 4.5.2 is missing. Add it to PATH or place the portable runtime under tools/godot-4.5.2.'
    }
    $godotExe = $godotCandidates[0].Source
}
if (-not $SkipNode -and -not (Test-Path -LiteralPath $nodeExe)) {
    $nodeCandidates = @(Get-Command node.exe,node -CommandType Application -ErrorAction SilentlyContinue)
    if ($nodeCandidates.Count -eq 0) {
        throw 'Node.js 20+ is missing. Add it to PATH or place the portable runtime under tools/node.'
    }
    $nodeExe = $nodeCandidates[0].Source
}

foreach ($requiredPath in @($projectRoot, $godotExe)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Required test path is missing: $requiredPath"
    }
}

New-Item -ItemType Directory -Path $logRoot -Force | Out-Null

function Assert-CleanOutput {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Text,
        [string[]]$ExpectedMarkers = @()
    )

    $forbidden = [regex]::Matches($Text, "(?m)^(?:SCRIPT ERROR|ERROR:|WARNING:)")
    if ($forbidden.Count -gt 0) {
        $first = $forbidden[0].Value
        throw "[$Name] emitted forbidden diagnostic '$first'. See qa/logs/final/$Name.log"
    }
    foreach ($marker in $ExpectedMarkers) {
        if (-not $Text.Contains($marker)) {
            throw "[$Name] did not emit expected marker '$marker'. See qa/logs/final/$Name.log"
        }
    }
}

function Save-TestLog {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][object[]]$Output
    )

    $lines = @($Output | ForEach-Object { $_.ToString() })
    $logPath = Join-Path $logRoot "$Name.log"
    Set-Content -LiteralPath $logPath -Value $lines -Encoding UTF8
    return @{
        Lines = $lines
        Text = $lines -join [Environment]::NewLine
        Path = $logPath
    }
}

function Invoke-GodotCase {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$Scene = "",
        [string[]]$UserArgs = @(),
        [string[]]$ExpectedMarkers = @(),
        [switch]$EditorParse
    )

    Write-Host "[RUN ] $Name"
    $arguments = [System.Collections.Generic.List[string]]::new()
    foreach ($argument in @(
        "--headless",
        "--path", $projectRoot,
        "--rendering-method", "gl_compatibility",
        "--quit-after", "3600"
    )) {
        $arguments.Add($argument)
    }
    if ($EditorParse) {
        # --import performs the full editor filesystem/script scan but exits
        # without reopening and tearing down the saved editor workspace, a
        # Godot 4.5 headless path that can intermittently access-violate.
        $arguments.Add("--import")
    } else {
        if ([string]::IsNullOrWhiteSpace($Scene)) {
            throw "[$Name] requires a scene path."
        }
        $arguments.Add($Scene)
        if ($UserArgs.Count -gt 0) {
            $arguments.Add("--")
            foreach ($argument in $UserArgs) {
                $arguments.Add($argument)
            }
        }
    }

    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = @(& $godotExe @arguments 2>&1)
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorAction
    }
    $log = Save-TestLog -Name $Name -Output $output
    if ($exitCode -ne 0) {
        throw "[$Name] exited with code $exitCode. See $($log.Path)"
    }
    Assert-CleanOutput -Name $Name -Text $log.Text -ExpectedMarkers $ExpectedMarkers
    $script:passedCases += 1
    Write-Host "[PASS] $Name"
}

function Invoke-NodeCase {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string[]]$ExpectedMarkers
    )

    Write-Host "[RUN ] $Name"
    Push-Location $WorkingDirectory
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = @(& $nodeExe $ScriptPath 2>&1)
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorAction
        Pop-Location
    }
    $log = Save-TestLog -Name $Name -Output $output
    if ($exitCode -ne 0) {
        throw "[$Name] exited with code $exitCode. See $($log.Path)"
    }
    Assert-CleanOutput -Name $Name -Text $log.Text -ExpectedMarkers $ExpectedMarkers
    $script:passedCases += 1
    Write-Host "[PASS] $Name"
}

function Invoke-PowerShellCase {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][string[]]$ExpectedMarkers
    )

    Write-Host "[RUN ] $Name"
    $powershellExe = Join-Path $PSHOME "powershell.exe"
    $previousErrorAction = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = @(& $powershellExe -NoProfile -ExecutionPolicy Bypass -File $ScriptPath 2>&1)
        $exitCode = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousErrorAction
    }
    $log = Save-TestLog -Name $Name -Output $output
    if ($exitCode -ne 0) {
        throw "[$Name] exited with code $exitCode. See $($log.Path)"
    }
    Assert-CleanOutput -Name $Name -Text $log.Text -ExpectedMarkers $ExpectedMarkers
    $script:passedCases += 1
    Write-Host "[PASS] $Name"
}

$sourceStageHarness = "res://qa/source_room_stage_test.tscn"

Invoke-GodotCase -Name "editor-parse" -EditorParse
Invoke-GodotCase -Name "loop-run-state" -Scene $sourceStageHarness -UserArgs @("--loop-run-state-test") -ExpectedMarkers @("LOOP_RUN_STATE_SMOKE_OK")
Invoke-GodotCase -Name "scene-flow" -Scene $sourceStageHarness -UserArgs @("--scene-flow-test") -ExpectedMarkers @("SCENE_FLOW_SMOKE_OK")
Invoke-GodotCase -Name "source-room-stage" -Scene $sourceStageHarness -UserArgs @("--source-room-stage-test") -ExpectedMarkers @(
    "SOURCE_ROOM_STAGE_SPAWN_OK",
    "SOURCE_ROOM_STAGE_EXACT_KILL_OK",
    "SOURCE_ROOM_STAGE_GATE_REWARD_OK",
    "SOURCE_ROOM_STAGE_PORTAL_OK",
    "SOURCE_ROOM_STAGE_E2E_OK"
)
Invoke-GodotCase -Name "home" -Scene "res://scenes/demo/loop_oasis/home_base.tscn" -UserArgs @("--home-test") -ExpectedMarkers @("HOME_BASE_SMOKE_OK")
Invoke-GodotCase -Name "theme-map" -Scene "res://scenes/demo/loop_oasis/multi_scene/theme_map.tscn" -UserArgs @("--theme-map-test") -ExpectedMarkers @("THEME_MAP_SMOKE_OK")
Invoke-GodotCase -Name "level-prep" -Scene "res://scenes/demo/loop_oasis/multi_scene/level_prep.tscn" -UserArgs @("--level-prep-test") -ExpectedMarkers @("LEVEL_PREP_SMOKE_OK")

$adventureRooms = @(
    "r0_observe",
    "r1_safe_program",
    "puzzle_bridge",
    "pulse_defense",
    "r4_transfer",
    "boss_guardian"
)
foreach ($roomId in $adventureRooms) {
    Invoke-GodotCase -Name "adventure-$roomId" -Scene "res://scenes/demo/loop_oasis/multi_scene/$roomId.tscn" -UserArgs @("--adventure-room-test") -ExpectedMarkers @("ADVENTURE_ROOM_CONTRACT_OK=$roomId")
}

$facilities = @(
    @("farm", "farm.tscn"),
    @("growth", "growth_chamber.tscn"),
    @("archive", "archive_star_map.tscn"),
    @("workshop", "workshop_range.tscn")
)
foreach ($facility in $facilities) {
    $facilityId = $facility[0]
    $facilityScene = $facility[1]
    Invoke-GodotCase -Name "facility-$facilityId" -Scene "res://scenes/demo/loop_oasis/multi_scene/$facilityScene" -UserArgs @("--facility-test") -ExpectedMarkers @("FACILITY_SCENE_OK $facilityId")
}

Invoke-GodotCase -Name "settlement" -Scene "res://scenes/demo/loop_oasis/multi_scene/settlement.tscn" -UserArgs @("--settlement-test") -ExpectedMarkers @("SETTLEMENT_SMOKE_OK")
Invoke-GodotCase -Name "multi-scene-e2e" -Scene "res://qa/multiscene_e2e_harness.tscn" -ExpectedMarkers @(
    "MULTISCENE_SCENE_CONTRACT_OK",
    "MULTISCENE_ROUTE_PUZZLE_FIRST_OK",
    "MULTISCENE_ROUTE_COMBAT_FIRST_OK",
    "MULTISCENE_GATES_OK",
    "MULTISCENE_PERSISTENCE_OK",
    "MULTISCENE_NO_POPUP_FAKE_OK",
    "MULTISCENE_E2E_OK"
)
Invoke-GodotCase -Name "legacy-teaching-core" -Scene "res://scenes/demo/data_garden/data_garden.tscn" -UserArgs @("--demo-test") -ExpectedMarkers @("DATA_GARDEN_SMOKE_OK")

if (-not $SkipNode) {
    if (-not (Test-Path -LiteralPath $nodeExe)) {
        throw "Bundled Node.js is missing: $nodeExe"
    }
    $contentRoot = Join-Path $workspaceRoot "content-engine"
    Invoke-NodeCase -Name "content-publisher" -WorkingDirectory $contentRoot -ScriptPath "scripts\publish-from-feishu.test.mjs" -ExpectedMarkers @("CONTENT_PUBLISHER_TEST_OK")
    Invoke-NodeCase -Name "content-generation" -WorkingDirectory $contentRoot -ScriptPath "scripts\generation.test.mjs" -ExpectedMarkers @("CONTENT_GENERATION_TEST_OK")
    Invoke-NodeCase -Name "xiao-hetao-server" -WorkingDirectory (Join-Path $workspaceRoot "xiao-hetao-ai-server") -ScriptPath "server.test.mjs" -ExpectedMarkers @("XIAO_HETAO_SERVER_TEST_OK")
}

if (-not $SkipAI) {
    Invoke-PowerShellCase -Name "xiao-hetao-godot-mock" -ScriptPath (Join-Path $workspaceRoot "xiao-hetao-ai-server\run-godot-integration-test.ps1") -ExpectedMarkers @(
        "XIAO_HETAO_GODOT_AI_OK",
        "LEARNING_EVENT_GODOT_OK",
        "LEARNING_EVENT_GODOT_SERVER_OK"
    )
}

Write-Host ""
Write-Host "ALL_AUTOMATED_TESTS_OK cases=$script:passedCases"
