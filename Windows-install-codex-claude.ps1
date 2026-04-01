param(
    [string]$ApiKey,
    [Alias("CodexHome")]
    [string]$SetupHome,
    [string]$ClaudeAuthToken
)

$ErrorActionPreference = "Stop"

$codexBaseUrl = "https://aizhiwen.top"
$codexModel = "gpt-5.4"
$codexReviewModel = "gpt-5.4"
$codexReasoningEffort = "xhigh"

$claudeBaseUrl = "https://aizhiwen.top"
$claudeDisableTraffic = "1"
$claudeAttributionHeader = "0"

function Get-PlainTextFromSecureString {
    param(
        [Parameter(Mandatory = $true)]
        [System.Security.SecureString]$SecureString
    )

    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
    try {
        return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function ConvertTo-HashtableRecursive {
    param(
        [Parameter(Mandatory = $true)]
        $Value
    )

    if ($null -eq $Value) {
        return $null
    }

    if ($Value -is [System.Collections.IDictionary]) {
        $table = [ordered]@{}
        foreach ($key in $Value.Keys) {
            $table[$key] = ConvertTo-HashtableRecursive -Value $Value[$key]
        }
        return $table
    }

    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
        $items = New-Object System.Collections.ArrayList
        foreach ($item in $Value) {
            [void]$items.Add((ConvertTo-HashtableRecursive -Value $item))
        }
        return ,$items.ToArray()
    }

    if ($Value -is [pscustomobject]) {
        $table = [ordered]@{}
        foreach ($property in $Value.PSObject.Properties) {
            $table[$property.Name] = ConvertTo-HashtableRecursive -Value $property.Value
        }
        return $table
    }

    return $Value
}

function Backup-IfExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Timestamp
    )

    if (Test-Path -LiteralPath $Path) {
        $backupPath = "$Path.bak-$Timestamp"
        Copy-Item -LiteralPath $Path -Destination $backupPath -Force
        Write-Host "Backed up: $backupPath"
    }
}

function Write-Utf8NoBomFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    $secureApiKey = Read-Host "Please enter your OPENAI_API_KEY" -AsSecureString
    $ApiKey = Get-PlainTextFromSecureString -SecureString $secureApiKey
}

if ([string]::IsNullOrWhiteSpace($ClaudeAuthToken)) {
    $secureClaudeToken = Read-Host "Please enter your ANTHROPIC_AUTH_TOKEN" -AsSecureString
    $ClaudeAuthToken = Get-PlainTextFromSecureString -SecureString $secureClaudeToken
}

if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    throw "OPENAI_API_KEY cannot be empty."
}

if ([string]::IsNullOrWhiteSpace($ClaudeAuthToken)) {
    throw "ANTHROPIC_AUTH_TOKEN cannot be empty."
}

$homeDir = if (-not [string]::IsNullOrWhiteSpace($SetupHome)) {
    $SetupHome
}
elseif ($HOME) {
    $HOME
}
else {
    $env:USERPROFILE
}

$codexDir = Join-Path $homeDir ".codex"
$claudeDir = Join-Path $homeDir ".claude"

$codexConfigPath = Join-Path $codexDir "config.toml"
$codexAuthPath = Join-Path $codexDir "auth.json"
$claudeSettingsPath = Join-Path $claudeDir "settings.json"
$claudeCmdEnvPath = Join-Path $claudeDir "claude-code-env.cmd"
$claudePs1EnvPath = Join-Path $claudeDir "claude-code-env.ps1"
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

New-Item -ItemType Directory -Path $codexDir -Force | Out-Null
New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null

Backup-IfExists -Path $codexConfigPath -Timestamp $timestamp
Backup-IfExists -Path $codexAuthPath -Timestamp $timestamp
Backup-IfExists -Path $claudeSettingsPath -Timestamp $timestamp
Backup-IfExists -Path $claudeCmdEnvPath -Timestamp $timestamp
Backup-IfExists -Path $claudePs1EnvPath -Timestamp $timestamp

$configContent = @"
model_provider = "OpenAI"
model = "$codexModel"
review_model = "$codexReviewModel"
model_reasoning_effort = "$codexReasoningEffort"
disable_response_storage = true
network_access = "enabled"
windows_wsl_setup_acknowledged = true
model_context_window = 1000000
model_auto_compact_token_limit = 900000

[model_providers.OpenAI]
name = "OpenAI"
base_url = "$codexBaseUrl"
wire_api = "responses"
requires_openai_auth = true

[windows]
sandbox = "unelevated"
"@

$codexAuthContent = @{
    OPENAI_API_KEY = $ApiKey
} | ConvertTo-Json -Depth 3

$claudeSettings = [ordered]@{}
if (Test-Path -LiteralPath $claudeSettingsPath) {
    try {
        $existingSettings = Get-Content -LiteralPath $claudeSettingsPath -Raw | ConvertFrom-Json
        $claudeSettings = ConvertTo-HashtableRecursive -Value $existingSettings
    }
    catch {
        $claudeSettings = [ordered]@{}
    }
}

$existingEnv = [ordered]@{}
if ($claudeSettings.Contains("env")) {
    $currentEnv = $claudeSettings["env"]
    if ($currentEnv -is [System.Collections.IDictionary]) {
        foreach ($key in $currentEnv.Keys) {
            $existingEnv[$key] = $currentEnv[$key]
        }
    }
}

$existingEnv["ANTHROPIC_BASE_URL"] = $claudeBaseUrl
$existingEnv["ANTHROPIC_AUTH_TOKEN"] = $ClaudeAuthToken
$existingEnv["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] = $claudeDisableTraffic
$existingEnv["CLAUDE_CODE_ATTRIBUTION_HEADER"] = $claudeAttributionHeader
$claudeSettings["env"] = $existingEnv

$claudeCmdEnvContent = @"
@echo off
set ANTHROPIC_BASE_URL=$claudeBaseUrl
set ANTHROPIC_AUTH_TOKEN=$ClaudeAuthToken
set CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=$claudeDisableTraffic
set CLAUDE_CODE_ATTRIBUTION_HEADER=$claudeAttributionHeader
"@

$claudePs1EnvContent = @(
    ('$env:ANTHROPIC_BASE_URL="{0}"' -f $claudeBaseUrl),
    ('$env:ANTHROPIC_AUTH_TOKEN="{0}"' -f $ClaudeAuthToken),
    ('$env:CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="{0}"' -f $claudeDisableTraffic),
    ('$env:CLAUDE_CODE_ATTRIBUTION_HEADER="{0}"' -f $claudeAttributionHeader)
) -join "`r`n"

Write-Utf8NoBomFile -Path $codexConfigPath -Content ($configContent.TrimStart("`r", "`n") + "`n")
Write-Utf8NoBomFile -Path $codexAuthPath -Content ($codexAuthContent + "`n")
Write-Utf8NoBomFile -Path $claudeSettingsPath -Content (($claudeSettings | ConvertTo-Json -Depth 10) + "`n")
Write-Utf8NoBomFile -Path $claudeCmdEnvPath -Content ($claudeCmdEnvContent.TrimStart("`r", "`n") + "`n")
Write-Utf8NoBomFile -Path $claudePs1EnvPath -Content ($claudePs1EnvContent.TrimStart("`r", "`n") + "`n")

Write-Host ""
Write-Host "Codex and Claude Code configuration installed successfully."
Write-Host "Codex config:        $codexConfigPath"
Write-Host "Codex auth:          $codexAuthPath"
Write-Host "Claude settings:     $claudeSettingsPath"
Write-Host "Claude CMD helper:   $claudeCmdEnvPath"
Write-Host "Claude PS helper:    $claudePs1EnvPath"
