param(
    [string]$ApiKey = "",
    [string]$TextModel = "",
    [string]$VisionModel = "",
    [string]$ImageModel = ""
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

function Read-Default {
    param([string]$Prompt, [string]$DefaultValue)
    $value = Read-Host "$Prompt [$DefaultValue]"
    if ([string]::IsNullOrWhiteSpace($value)) { return $DefaultValue }
    return $value.Trim()
}

$envPath = Join-Path $demoRoot "xiao-hetao-ai-server\.env"
$pointer = [IntPtr]::Zero
$plainKey = $ApiKey

try {
    if ([string]::IsNullOrWhiteSpace($plainKey)) {
        $secureKey = Read-Host "请输入火山方舟 API Key（输入不会显示）" -AsSecureString
        $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey)
        $plainKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)
    }
    if ([string]::IsNullOrWhiteSpace($plainKey) -or $plainKey.Length -lt 12 -or $plainKey -match '\s') {
        throw "输入内容不像有效的火山方舟 API Key。"
    }

    if ([string]::IsNullOrWhiteSpace($TextModel)) { $TextModel = Read-Default "文本模型 ID" "doubao-seed-2-0-pro-260215" }
    if ([string]::IsNullOrWhiteSpace($VisionModel)) { $VisionModel = Read-Default "视觉审核模型 ID" $TextModel }
    if ([string]::IsNullOrWhiteSpace($ImageModel)) { $ImageModel = Read-Default "Seedream 图片模型 ID" "doubao-seedream-5-0-lite-260128" }

    $updates = [ordered]@{
        ARK_API_KEY = $plainKey
        ARK_TEXT_API_URL = "https://ark.cn-beijing.volces.com/api/v3/chat/completions"
        ARK_TEXT_MODEL = $TextModel.Trim()
        ARK_VISION_API_URL = "https://ark.cn-beijing.volces.com/api/v3/chat/completions"
        ARK_VISION_MODEL = $VisionModel.Trim()
        SKIN_IMAGE_API_URL = "https://ark.cn-beijing.volces.com/api/v3/images/generations"
        SKIN_IMAGE_MODEL = $ImageModel.Trim()
        GENERATION_TEXT_PROVIDER = "ark"
        GENERATION_TEXT_FALLBACK_PROVIDER = "deepseek"
        GENERATION_VISION_PROVIDER = "ark"
        GENERATION_VISION_FALLBACK_PROVIDER = "none"
        GENERATION_VISION_REQUIRED = "true"
        GENERATION_REQUEST_TIMEOUT_MS = "90000"
        SKIN_IMAGE_TIMEOUT_MS = "360000"
        SKIN_IMAGE_RESPONSE_FORMAT = "url"
        SKIN_IMAGE_REFERENCE_MODE = "array"
        SKIN_VISUAL_REPAIR_ATTEMPTS = "2"
    }
    Set-DotEnvValues -Path $envPath -Values $updates

    Write-Host ""
    Write-Host "火山引擎配置已保存到本机；原有 DeepSeek 等配置已保留。" -ForegroundColor Green
    Write-Host "下一步：先运行 验证火山引擎连接.bat，再按教程进行离线/真实世界生成。"
} finally {
    if ($pointer -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
    $plainKey = $null
    $ApiKey = $null
}
