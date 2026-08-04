param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$workspaceRoot = $PSScriptRoot
$nodeExecutable = Join-Path $workspaceRoot "tools\node\node.exe"
$publisherScript = Join-Path $workspaceRoot "content-engine\scripts\publish-from-feishu.mjs"

if (-not (Test-Path -LiteralPath $nodeExecutable)) {
    $nodeCandidates = @(Get-Command node.exe,node -CommandType Application -ErrorAction SilentlyContinue)
    if ($nodeCandidates.Count -eq 0) {
        throw 'Node.js 20+ is missing. Add it to PATH or place the portable runtime under tools/node.'
    }
    $nodeExecutable = $nodeCandidates[0].Source
}

if (-not (Test-Path -LiteralPath $nodeExecutable)) {
    throw "Bundled Node runtime is missing: $nodeExecutable"
}
if (-not (Get-Command lark-cli -ErrorAction SilentlyContinue)) {
    throw "lark-cli is unavailable. Sign in to Feishu first."
}

$publisherArguments = @($publisherScript)
if ($Force) { $publisherArguments += "--force" }
& $nodeExecutable @publisherArguments
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
