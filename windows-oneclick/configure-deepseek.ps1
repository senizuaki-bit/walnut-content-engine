param(
    [string]$ApiKey = "",
    [string]$Model = "deepseek-v4-flash"
)

$ErrorActionPreference = "Stop"

$demoRoot = $PSScriptRoot
if (-not (Test-Path -LiteralPath (Join-Path $demoRoot "xiao-hetao-ai-server"))) {
    $parentRoot = Split-Path -Parent $PSScriptRoot
    if (Test-Path -LiteralPath (Join-Path $parentRoot "xiao-hetao-ai-server")) { $demoRoot = $parentRoot }
}

function Set-DotEnvValues {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Values
    )

    $lines = New-Object System.Collections.Generic.List[string]
    if (Test-Path -LiteralPath $Path) {
        foreach ($line in [System.IO.File]::ReadAllLines($Path)) { $lines.Add($line) }
    }

    foreach ($key in $Values.Keys) {
        $replacement = "$key=$($Values[$key])"
        $pattern = "^\s*$([regex]::Escape([string]$key))\s*="
        $found = $false
        for ($index = 0; $index -lt $lines.Count; $index++) {
            if ($lines[$index] -match $pattern) {
                $lines[$index] = $replacement
                $found = $true
                break
            }
        }
        if (-not $found) { $lines.Add($replacement) }
    }

    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent | Out-Null }
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($Path, $lines, $utf8NoBom)
}

$envPath = Join-Path $demoRoot "xiao-hetao-ai-server\.env"
$pointer = [IntPtr]::Zero
$plainKey = $ApiKey

try {
    if ([string]::IsNullOrWhiteSpace($plainKey)) {
        $secureKey = Read-Host "请输入新的 DeepSeek API Key（输入不会显示）" -AsSecureString
        $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
        $plainKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    }

    if ([string]::IsNullOrWhiteSpace($plainKey)) { throw "API Key 不能为空。" }
    if ($plainKey -notmatch '^sk-[A-Za-z0-9_-]{16,}$') { throw "输入内容不像有效的 DeepSeek API Key。" }
    if ([string]::IsNullOrWhiteSpace($Model)) { throw "模型 ID 不能为空。" }

    $updates = [ordered]@{
        DEEPSEEK_API_KEY = $plainKey
        DEEPSEEK_MODEL = $Model.Trim()
        DEEPSEEK_BASE_URL = "https://api.deepseek.com"
        HOST = "127.0.0.1"
        PORT = "8787"
        REQUEST_TIMEOUT_MS = "8000"
    }
    Set-DotEnvValues -Path $envPath -Values $updates

    Write-Host ""
    Write-Host "DeepSeek 配置已保存到本机；原有火山引擎等配置已保留。" -ForegroundColor Green
    Write-Host "下一步：运行 验证DeepSeek连接.bat"
} finally {
    if ($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
    $plainKey = $null
    $ApiKey = $null
}
