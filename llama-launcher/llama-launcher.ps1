[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [string]$ModelFilePath,

    [int]$NgL = 999,
    [int]$CtxSize = 131072,
    
    [ValidateSet("xhigh", "medium", "low")]
    [string]$Reasoning = "xhigh"
)

# clamp 
if ($NgL -lt 0) { $NgL = 0 } elseif ($NgL -gt 999) { $NgL = 999 }
if ($CtxSize -lt 32768) { $CtxSize = 32768 } elseif ($CtxSize -gt 262144) { $CtxSize = 262144 }

# env
$RequiredEnvs = @("LLAMA_API_KEY", "AI_MODELS")

Write-Host "=================================================" -ForegroundColor Cyan
Write-Host "                 llama-launcher                  " -ForegroundColor Cyan
Write-Host "=================================================" -ForegroundColor Cyan
Write-Host "`n"

function Check-EnvVars {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$EnvNames
    )
    
    $MissingEnv = @()
    foreach ($envVar in $EnvNames) {
        if (-not (Test-Path "env:\$envVar")) {
            $MissingEnv += $envVar
        }
    }
    return $MissingEnv
}

$missing = Check-EnvVars -EnvNames $RequiredEnvs
if ($missing) {
    Write-Host "`e[1;91m[ ERROR ]`e[0m Missing required environment variables: `e[33m$($missing -join ', ')`e[0m"
    exit 1
}

function Get-LLamaArgs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [ValidateScript({
                if (Test-Path $_) { $true } else { throw "Model file not found at: $_" }
            })]
        [string]$ModelPath,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1024, 1048576)]
        [int]$Context = 131072,

        [Parameter(Mandatory = $false)]
        [ValidateRange(0, 999)]
        [int]$NgL = 999,
        
        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 128)]
        [int]$Parallel = 1,
        
        [string]$HostIP = "192.168.0.245",
        
        [ValidateRange(1, 65535)]
        [int]$Port = 8080,

        [string]$Alias = "kvstorm1",
        [string]$CorsOrigins = "http://localhost,http://192.168.0.245",
        
        [switch]$DisableFlashAttn,
        [switch]$DisableContBatching,
        [switch]$DisableMetrics,
        [switch]$DisableCachePrompt,
        [switch]$DisableJinja
    )

    $argsList = @(
        "--model", $ModelPath,
        "--ctx-size", $Context,
        "--gpu-layers", $NgL,
        "--host", $HostIP,
        "--port", $Port,
        "--parallel", $Parallel
    )

    if (-not [string]::IsNullOrWhiteSpace($Alias)) { 
        $argsList += "--alias", $Alias 
    }
    
    if (-not [string]::IsNullOrWhiteSpace($CorsOrigins)) { 
        $argsList += "--cors-origins", $CorsOrigins
        $argsList += "--cors-credentials"
    }
    
    if (-not $DisableFlashAttn) { $argsList += "--flash-attn", "on" }
    if (-not $DisableContBatching) { $argsList += "--cont-batching" }
    if (-not $DisableMetrics) { $argsList += "--metrics" }
    if (-not $DisableCachePrompt) { $argsList += "--cache-prompt" }
    if (-not $DisableJinja) { $argsList += "--jinja" }

    return $argsList
}

function Get-ModelArgs {
    [CmdletBinding()]
    param(
        [ValidateRange(0.0, 5.0)]
        [float]$Temperature = 0.7,

        [ValidateRange(0.0, 1.0)]
        [float]$TopP = 0.8,

        [ValidateRange(0, 100)]
        [int]$TopK = 20,

        [ValidateRange(0.0, 1.0)]
        [float]$MinP = 0.0,

        [ValidateRange(0.0, 5.0)]
        [float]$PresencePenalty = 0.0,

        [ValidateRange(0.0, 5.0)]
        [float]$RepetitionPenalty = 1.0,

        [string]$ChatKwargs
    )
    
    $argsList = @(
        "--temp", $Temperature,
        "--top-p", $TopP,
        "--top-k", $TopK,
        "--min-p", $MinP,
        "--presence-penalty", $PresencePenalty,
        "--repeat-penalty", $RepetitionPenalty
    )

    # append chat kwargs if valid string provided
    if (-not [string]::IsNullOrWhiteSpace($ChatKwargs)) {
        $argsList += "--chat-template-kwargs", $ChatKwargs
    }

    return $argsList
}

# prompt for mode
$Choice = ""
while ($Choice -notin @("1", "2")) {
    $Choice = Read-Host "Select Mode:`n[1] Thinking`n[2] Instruct`nEnter choice (1 or 2)"
}

if ($Choice -eq "1") {
    Write-Host "`nMode: Thinking selected." -ForegroundColor Yellow
    $ChatKwargs = '{"reasoning_effort":"' + $Reasoning + '"}'
    $modelArgs = Get-ModelArgs -Temperature 1.0 -TopP 0.95 -TopK 20 -MinP 0.0 -PresencePenalty 0.0 -RepetitionPenalty 1.0 -ChatKwargs $ChatKwargs
}
else {
    Write-Host "`nMode: Instruct selected." -ForegroundColor Yellow
    $ChatKwargs = '{"enable_thinking":false,"reasoning_effort":"' + $Reasoning + '"}'
    $modelArgs = Get-ModelArgs -Temperature 0.7 -TopP 0.80 -TopK 20 -MinP 0.0 -PresencePenalty 1.5 -RepetitionPenalty 1.0 -ChatKwargs $ChatKwargs
}

# build args
$serverArgs = Get-LLamaArgs -ModelPath $ModelFilePath -Context $CtxSize -NgL $NgL
$llamaArgs = $serverArgs + $modelArgs

$maxRetries = 5
$retryCount = 0
$success = $false


$logDir = if ($env:LLAMA_LAUNCHER_LOG_DIR) { $env:LLAMA_LAUNCHER_LOG_DIR } else { "$env:USERPROFILE\.config\llama-launcher" }
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }
$logFile = Join-Path $logDir "llama-server_crash_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"


# launch and restart
$maxRetries = 5
$displayMax = "5"

$envRetry = $env:LLAMA_LAUNCHER_MAX_RETRY
if (-not [string]::IsNullOrWhiteSpace($envRetry)) {
    $envRetry = $envRetry.Trim().ToLower()
    
    if ($envRetry -eq 'max' -or $envRetry -eq 'infinite') {
        $maxRetries = [int]::MaxValue
        $displayMax = "Infinite"
    }
    elseif ($envRetry -match '^\d+$') {
        $maxRetries = [int]$envRetry
        $displayMax = $maxRetries
    }
    elseif ($envRetry -ne 'auto') {
        Write-Host "Warning: Invalid LLAMA_LAUNCHER_MAX_RETRY value '$envRetry'. Defaulting to 5." -ForegroundColor Yellow
    }
}

$retryCount = 0
$success = $false
$minUptimeSeconds = 5 # min seconds it must run to be successful

while ($retryCount -lt $maxRetries -and -not $success) {
    Write-Host "`nStarting llama-server (Attempt $($retryCount + 1) of $displayMax)..." -ForegroundColor Green
    Write-Host "Command: llama-server $($llamaArgs -join ' ')" -ForegroundColor White
    Write-Host "==================================================" -ForegroundColor Cyan

    $startTime = Get-Date

    # have to extract raw text since 2>&1 in powershell wraps in ErrorRecord object
    & llama-server @llamaArgs 2>&1 | ForEach-Object { $_.ToString() } | Tee-Object -FilePath $logFile -Append

    $endTime = Get-Date
    $runTime = $endTime - $startTime

    if ($LASTEXITCODE -eq 0) {
        $success = $true
        Write-Host "Server shut down cleanly." -ForegroundColor Green
    }
    else {
        Write-Host "Server crashed with exit code $LASTEXITCODE." -ForegroundColor Red
        
        # check if it crashed immediately
        if ($runTime.TotalSeconds -lt $minUptimeSeconds) {
            Write-Host "CRITICAL: Server crashed immediately (ran for less than $minUptimeSeconds seconds)." -ForegroundColor Red
            Write-Host "This usually indicates invalid arguments, a bad model path, or the port is already in use." -ForegroundColor Red
            Write-Host "Error details logged to: $logFile" -ForegroundColor DarkGray
            Write-Host "Aborting restart to prevent infinite loop." -ForegroundColor Red
            exit $LASTEXITCODE
        }

        $retryCount++
        Write-Host "Server crashed after running for $([math]::Round($runTime.TotalSeconds)) seconds." -ForegroundColor Yellow
        Write-Host "Error details logged to: $logFile" -ForegroundColor DarkGray
        
        if ($retryCount -lt $maxRetries) {
            Write-Host "Restarting in 5 seconds..." -ForegroundColor Yellow
            Start-Sleep -Seconds 5
        }
        else {
            Write-Host "Maximum retry limit ($maxRetries) reached. Abandoning startup." -ForegroundColor Red
            exit $LASTEXITCODE
        }
    }
}