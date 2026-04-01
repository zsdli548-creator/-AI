param(
    [string]$ApiKey,
    [Alias("OpenClawHome")]
    [string]$SetupHome,
    [switch]$SkipInstall,
    [switch]$SkipGatewayService
)

$ErrorActionPreference = "Stop"

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

function Read-SetupConfig {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Setup config not found: $Path"
    }

    $values = [ordered]@{}
    foreach ($line in Get-Content -LiteralPath $Path) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith("#")) {
            continue
        }

        $parts = $trimmed -split "=", 2
        if ($parts.Count -ne 2) {
            continue
        }

        $name = $parts[0].Trim()
        $value = $parts[1].Trim()

        if (
            ($value.StartsWith('"') -and $value.EndsWith('"')) -or
            ($value.StartsWith("'") -and $value.EndsWith("'"))
        ) {
            $value = $value.Substring(1, $value.Length - 2)
        }

        $values[$name] = $value
    }

    return $values
}

function Get-ConfigValue {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Config,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$DefaultValue
    )

    if ($Config.Contains($Name) -and -not [string]::IsNullOrWhiteSpace([string]$Config[$Name])) {
        return [string]$Config[$Name]
    }

    return $DefaultValue
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

function Convert-ToEnvLiteral {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    if ($Value -match "^[A-Za-z0-9_./:\-]+$") {
        return $Value
    }

    $escaped = $Value.Replace("\", "\\").Replace('"', '\"')
    return '"' + $escaped + '"'
}

function Update-EnvVarFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$Value
    )

    $lines = New-Object System.Collections.Generic.List[string]
    if (Test-Path -LiteralPath $Path) {
        foreach ($line in Get-Content -LiteralPath $Path) {
            if ($line -match "^\s*$([Regex]::Escape($Name))=") {
                continue
            }
            $lines.Add($line)
        }
    }

    $lines.Add("$Name=$(Convert-ToEnvLiteral -Value $Value)")
    Write-Utf8NoBomFile -Path $Path -Content (($lines -join "`n") + "`n")
}

function Add-ToPathIfExists {
    param(
        [string]$PathEntry
    )

    if ([string]::IsNullOrWhiteSpace($PathEntry) -or -not (Test-Path -LiteralPath $PathEntry)) {
        return
    }

    $currentParts = $env:PATH -split ";"
    if ($currentParts -contains $PathEntry) {
        return
    }

    $env:PATH = "$PathEntry;$env:PATH"
}

function Resolve-OpenClawCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$HomeDir
    )

    $command = Get-Command openclaw -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $candidates = @(
        (Join-Path $HomeDir ".openclaw\bin\openclaw.cmd"),
        (Join-Path $HomeDir ".openclaw\bin\openclaw.ps1"),
        (Join-Path $HomeDir ".local\bin\openclaw.cmd"),
        (Join-Path $HomeDir ".local\bin\openclaw.ps1")
    )

    if ($env:APPDATA) {
        $candidates += (Join-Path $env:APPDATA "npm\openclaw.cmd")
        $candidates += (Join-Path $env:APPDATA "npm\openclaw.ps1")
    }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            Add-ToPathIfExists -PathEntry (Split-Path -Parent $candidate)
            return $candidate
        }
    }

    $npmCommand = Get-Command npm -ErrorAction SilentlyContinue
    if ($npmCommand) {
        try {
            $prefix = (& $npmCommand.Source config get prefix 2>$null | Select-Object -First 1).Trim()
            if (-not [string]::IsNullOrWhiteSpace($prefix)) {
                Add-ToPathIfExists -PathEntry $prefix
                $npmCandidates = @(
                    (Join-Path $prefix "openclaw.cmd"),
                    (Join-Path $prefix "openclaw.ps1")
                )
                foreach ($npmCandidate in $npmCandidates) {
                    if (Test-Path -LiteralPath $npmCandidate) {
                        return $npmCandidate
                    }
                }
            }
        }
        catch {
        }
    }

    return $null
}

function Ensure-OpenClawInstalled {
    param(
        [Parameter(Mandatory = $true)]
        [string]$HomeDir,
        [Parameter(Mandatory = $true)]
        [string]$InstallChannel
    )

    $existing = Resolve-OpenClawCommand -HomeDir $HomeDir
    if ($existing) {
        return $existing
    }

    if ($SkipInstall) {
        throw "OpenClaw is not installed and -SkipInstall was provided."
    }

    Write-Host "OpenClaw not found. Installing with the official Windows installer..."
    $installScript = (Invoke-WebRequest -UseBasicParsing "https://openclaw.ai/install.ps1").Content
    $installerBlock = [scriptblock]::Create($installScript)

    if ($InstallChannel -and $InstallChannel -ne "latest") {
        & $installerBlock -NoOnboard -Tag $InstallChannel
    }
    else {
        & $installerBlock -NoOnboard
    }

    $resolved = Resolve-OpenClawCommand -HomeDir $HomeDir
    if (-not $resolved) {
        throw "OpenClaw installation completed, but the 'openclaw' command could not be resolved in this session."
    }

    return $resolved
}

function Invoke-ExternalChecked {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code ${LASTEXITCODE}: $Command $($Arguments -join ' ')"
    }
}

function Invoke-ExternalCapture {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $output = & $Command @Arguments 2>$null
    if ($LASTEXITCODE -ne 0) {
        return $null
    }

    if ($output -is [System.Array]) {
        return ($output | Where-Object { $_ -ne $null } | ForEach-Object { $_.ToString() }) -join "`n"
    }

    return [string]$output
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$setupConfigPath = Join-Path $scriptRoot "openclaw-api-setup.env"
$setupConfig = Read-SetupConfig -Path $setupConfigPath

$baseUrl = Get-ConfigValue -Config $setupConfig -Name "OPENCLAW_BASE_URL" -DefaultValue "https://aizhiwen.top"
$model = Get-ConfigValue -Config $setupConfig -Name "OPENCLAW_MODEL" -DefaultValue "gpt-5.4"
$reasoningEffort = Get-ConfigValue -Config $setupConfig -Name "OPENCLAW_REASONING_EFFORT" -DefaultValue "xhigh"
$providerApi = Get-ConfigValue -Config $setupConfig -Name "OPENCLAW_PROVIDER_API" -DefaultValue "openai-responses"
$installChannel = Get-ConfigValue -Config $setupConfig -Name "OPENCLAW_INSTALL_CHANNEL" -DefaultValue "latest"

if ($reasoningEffort -eq "xhigh" -and $providerApi -ne "openai-responses") {
    Write-Warning "OPENCLAW_PROVIDER_API is '$providerApi'. GPT-5.4 xhigh is usually paired with the OpenAI Responses API."
}

if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    $secureApiKey = Read-Host "Please enter your OPENAI_API_KEY" -AsSecureString
    $ApiKey = Get-PlainTextFromSecureString -SecureString $secureApiKey
}

if ([string]::IsNullOrWhiteSpace($ApiKey)) {
    throw "OPENAI_API_KEY cannot be empty."
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

$openclawDir = Join-Path $homeDir ".openclaw"
$envFilePath = Join-Path $openclawDir ".env"
$defaultConfigPath = Join-Path $openclawDir "openclaw.json"
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"

New-Item -ItemType Directory -Path $openclawDir -Force | Out-Null

Backup-IfExists -Path $envFilePath -Timestamp $timestamp
Update-EnvVarFile -Path $envFilePath -Name "OPENAI_API_KEY" -Value $ApiKey

$openclawCommand = Ensure-OpenClawInstalled -HomeDir $homeDir -InstallChannel $installChannel

$configPathOutput = Invoke-ExternalCapture -Command $openclawCommand -Arguments @("config", "file")
$configPath = if (-not [string]::IsNullOrWhiteSpace($configPathOutput)) {
    $configPathOutput.Trim()
}
else {
    $defaultConfigPath
}

Backup-IfExists -Path $configPath -Timestamp $timestamp

$batchOperations = @(
    @{ path = "gateway.mode"; value = "local" },
    @{ path = "agents.defaults.model.primary"; value = "openai/$model" },
    @{ path = "agents.defaults.thinkingDefault"; value = $reasoningEffort },
    @{ path = "models.mode"; value = "merge" },
    @{ path = "models.providers.openai.baseUrl"; value = $baseUrl },
    @{ path = "models.providers.openai.api"; value = $providerApi },
    @{ path = "models.providers.openai.apiKey"; value = '${OPENAI_API_KEY}' }
)

$batchFilePath = Join-Path ([System.IO.Path]::GetTempPath()) "openclaw-config-$PID.json"
try {
    Write-Utf8NoBomFile -Path $batchFilePath -Content (($batchOperations | ConvertTo-Json -Depth 10) + "`n")

    Invoke-ExternalChecked -Command $openclawCommand -Arguments @("config", "set", "--batch-file", $batchFilePath, "--dry-run")
    Invoke-ExternalChecked -Command $openclawCommand -Arguments @("config", "set", "--batch-file", $batchFilePath)
}
finally {
    if (Test-Path -LiteralPath $batchFilePath) {
        Remove-Item -LiteralPath $batchFilePath -Force
    }
}

Invoke-ExternalChecked -Command $openclawCommand -Arguments @("config", "validate")

$doctorWarning = $null
try {
    Invoke-ExternalChecked -Command $openclawCommand -Arguments @("doctor", "--non-interactive")
}
catch {
    $doctorWarning = $_.Exception.Message
}

$gatewayWarning = $null
if (-not $SkipGatewayService) {
    try {
        Invoke-ExternalChecked -Command $openclawCommand -Arguments @("gateway", "install", "--json")
    }
    catch {
        $gatewayWarning = $_.Exception.Message
    }

    try {
        Invoke-ExternalChecked -Command $openclawCommand -Arguments @("gateway", "start", "--json")
        Invoke-ExternalChecked -Command $openclawCommand -Arguments @("gateway", "status", "--require-rpc")
    }
    catch {
        if ($gatewayWarning) {
            $gatewayWarning = "$gatewayWarning | $($_.Exception.Message)"
        }
        else {
            $gatewayWarning = $_.Exception.Message
        }
    }
}

Write-Host ""
Write-Host "OpenClaw setup completed."
Write-Host "Config file:          $configPath"
Write-Host "Global env file:      $envFilePath"
Write-Host "Default model:        openai/$model"
Write-Host "Reasoning level:      $reasoningEffort"
Write-Host "OpenAI base URL:      $baseUrl"

if ($doctorWarning) {
    Write-Warning "openclaw doctor reported a warning: $doctorWarning"
}

if ($SkipGatewayService) {
    Write-Host "Gateway service:      skipped by request"
    Write-Host "Manual start:         $openclawCommand gateway run"
}
elseif ($gatewayWarning) {
    Write-Warning "Gateway service was not fully started automatically: $gatewayWarning"
    Write-Host "Manual start:         $openclawCommand gateway run"
}
else {
    Write-Host "Gateway service:      installed and started"
}
