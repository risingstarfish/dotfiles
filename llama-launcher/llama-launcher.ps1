[CmdletBinding()]
param (
    [string]$ModelFilePath = "",

    [string]$llamaBinary = "",

    [string]$ChatTemplate = "",

    [ValidateRange(0, 999)]
    [int]$NgL = 999,
    
    [ValidateRange(4096, 262144)]
    [int]$CtxSize = 262144,

    [ValidateSet("xhigh", "medium", "low")]
    [string]$Reasoning = "medium",

    [ValidateSet("thinking", "instruct")]
    [string]$Mode = "",

    [string]$HostIP = "0.0.0.0",

    [ValidateRange(1, 65535)]
    [int]$Port = 9931
)

Set-StrictMode -Version Latest

# env check
$RequiredEnvs = @("LLAMA_API_KEY", "AI_MODELS")
$MissingEnv = @()
foreach ($envVar in $RequiredEnvs) {
    if (-not (Test-Path "env:$envVar")) {
        $MissingEnv += $envVar
    }
}
if ($MissingEnv) {
    Write-Host "Error: Missing required environment variables: $($MissingEnv -join ', ')" -ForegroundColor Red
    exit 1
}

# defaults from env
if ([string]::IsNullOrWhiteSpace($ModelFilePath)) {
    $ModelFilePath = Join-Path $env:AI_MODELS "Qwen3.8-27B-UD-Q8_K_XL.gguf"
}
if ([string]::IsNullOrWhiteSpace($ChatTemplate)) {
    $ChatTemplate = Join-Path $env:AI_MODELS "Qwen3.5_chat_template.jinja"
}

# binary detection
if ([string]::IsNullOrWhiteSpace($llamaBinary)) {
    $llamaBinary = (Get-Command "llama-server" -ErrorAction SilentlyContinue)?.Source
    if (-not $llamaBinary) {
        $llamaBinary = (Get-Command "ik-llama-server" -ErrorAction SilentlyContinue)?.Source
    }
    if (-not $llamaBinary) {
        Write-Host "Error: Neither 'llama-server' nor 'ik-llama-server' found in PATH." -ForegroundColor Red
        Write-Host "Specify explicitly:  llama-launcher -llamaBinary <path-to-binary>" -ForegroundColor DarkGray
        exit 1
    }
}

if (-not (Test-Path $llamaBinary)) {
    Write-Host "Error: Binary not found: $llamaBinary" -ForegroundColor Red
    exit 1
}

$binName = [System.IO.Path]::GetFileNameWithoutExtension($llamaBinary)
$isIkLlama = $binName -eq 'ik-llama-server'

if (-not (Test-Path $ModelFilePath)) {
    Write-Host "Error: Model file not found: $ModelFilePath" -ForegroundColor Red
    exit 1
}
if (-not (Test-Path $ChatTemplate)) {
    Write-Host "Error: Chat template not found: $ChatTemplate" -ForegroundColor Red
    exit 1
}

# port
$bindAddr = if ($HostIP -eq "0.0.0.0") {
    [System.Net.IPAddress]::Any
} else {
    [System.Net.IPAddress]::Parse($HostIP)
}
try {
    $listener = [System.Net.Sockets.TcpListener]::new($bindAddr, $Port)
    $listener.Start()
    $listener.Stop()
} catch [System.Net.Sockets.SocketException] {
    Write-Host "Error: Port $Port is already in use on $HostIP." -ForegroundColor Red
    exit 1
}


Write-Host "=================================================" -ForegroundColor Cyan
Write-Host "                 llama-launcher                  " -ForegroundColor Cyan
Write-Host "=================================================" -ForegroundColor Cyan
Write-Host "  Binary : $llamaBinary" -ForegroundColor Cyan
Write-Host "  Model  : $ModelFilePath" -ForegroundColor Cyan
Write-Host "  Host   : $HostIP : $Port" -ForegroundColor Cyan
Write-Host ""

if ([string]::IsNullOrWhiteSpace($Mode)) {
    $Choice = ""
    while ($Choice -notin @("1", "2")) {
        $Choice = Read-Host "Select Mode:`n[1] Thinking`n[2] Instruct`nEnter choice (1 or 2)"
    }
    $Mode = if ($Choice -eq "1") { "thinking" } else { "instruct" }
}

if ($Mode -eq "thinking") {
    Write-Host "Mode: Thinking" -ForegroundColor Yellow
    $ChatKwargs = '{"reasoning_effort":"' + $Reasoning + '"}'
    $modelArgs = @(
        "--temp", "1.0",
        "--top-p", "0.95",
        "--top-k", "20",
        "--min-p", "0.0",
        "--presence-penalty", "0.0",
        "--repeat-penalty", "1.0",
        "--chat-template-kwargs", $ChatKwargs
    )
}
else {
    Write-Host "Mode: Instruct" -ForegroundColor Yellow
    $ChatKwargs = '{"enable_thinking":false,"reasoning_effort":"' + $Reasoning + '"}'
    $modelArgs = @(
        "--temp", "0.7",
        "--top-p", "0.80",
        "--top-k", "20",
        "--min-p", "0.0",
        "--presence-penalty", "1.5",
        "--repeat-penalty", "1.0",
        "--chat-template-kwargs", $ChatKwargs
    )
}

$serverArgs = @(
    "--model", $ModelFilePath,
    "--ctx-size", $CtxSize,
    "--gpu-layers", $NgL,
    "--host", $HostIP,
    "--port", $Port,
    "--parallel", "1",
    "--chat-template-file", $ChatTemplate,
    "--cache-type-k", "q8_0",
    "--cache-type-v", "q8_0",
    "--alias", "kvstorm1",
    "--flash-attn", "on",
    "--cont-batching",
    "--metrics",
    "--jinja"
)

if ($isIkLlama) {
    $serverArgs += "--spec-type", "mtp:n_max=3,p_min=0.75"
}
else {
    $serverArgs += "--spec-type", "draft-mtp"
    $serverArgs += "--spec-draft-n-max", "3"
    $serverArgs += "--cors-origins", "http://localhost"
    $serverArgs += "--cors-credentials"
    $serverArgs += "--cache-prompt"
}

$llamaArgs = $serverArgs + $modelArgs

Write-Host ""
Write-Host "  [ Binary ] $llamaBinary" -ForegroundColor Green
Write-Host "  [ Model  ] $ModelFilePath" -ForegroundColor Green
Write-Host "  [ Ctx    ] $CtxSize" -ForegroundColor Green
Write-Host "  [ GPU-L  ] $NgL" -ForegroundColor Green
Write-Host "  [ Mode   ] $Mode" -ForegroundColor Green
Write-Host ""

# log setup
$logDir = if ($env:LLAMA_LAUNCHER_LOG_DIR) { $env:LLAMA_LAUNCHER_LOG_DIR } else { "$env:USERPROFILE\.config\llama-launcher" }
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Force -Path $logDir | Out-Null }
$logFile = Join-Path $logDir "${binName}_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

$retryCount = 0
$success = $false
$minUptimeSeconds = 5
$maxRetries = 5
$displayMax = "$maxRetries"

$envRetry = $env:LLAMA_LAUNCHER_MAX_RETRY
if (-not [string]::IsNullOrWhiteSpace($envRetry)) {
    $envRetry = $envRetry.Trim().ToLower()

    if ($envRetry -eq 'max' -or $envRetry -eq 'infinite') {
        $maxRetries = [int]::MaxValue
        $displayMax = "Infinite"
    }
    elseif ($envRetry -match '^\d+$') {
        $maxRetries = [int]$envRetry
        $displayMax = "$maxRetries"
    }
    elseif ($envRetry -ne 'auto') {
        Write-Host "Warning: Invalid LLAMA_LAUNCHER_MAX_RETRY value '$envRetry'. Defaulting to 5." -ForegroundColor Yellow
    }
}

trap {
    Write-Host ""
    Write-Host "[ llama-launcher ] Interrupted." -ForegroundColor Yellow
    exit 130
}

while ($retryCount -lt $maxRetries -and -not $success) {
    Write-Host ""
    Write-Host "Starting $llamaBinary (Attempt $($retryCount + 1) of $displayMax)..." -ForegroundColor Green
    Write-Host "Command: $llamaBinary $($llamaArgs -join ' ')" -ForegroundColor White
    Write-Host "==================================================" -ForegroundColor Cyan

    $startTime = Get-Date

    "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] --- Attempt $($retryCount + 1) ---" | Out-File $logFile -Append

    & $llamaBinary @llamaArgs 2>&1 | ForEach-Object { $_.ToString() } | Tee-Object -FilePath $logFile -Append

    $endTime = Get-Date
    $runTime = $endTime - $startTime

    if ($LASTEXITCODE -eq 0) {
        $success = $true
        Write-Host "Server shut down cleanly." -ForegroundColor Green
    }
    else {
        Write-Host "Server crashed with exit code $LASTEXITCODE." -ForegroundColor Red

        if ($runTime.TotalSeconds -lt $minUptimeSeconds) {
            Write-Host "CRITICAL: Server crashed immediately (ran < $minUptimeSeconds s)." -ForegroundColor Red
            Write-Host "Likely cause: invalid args, bad model path, or port conflict." -ForegroundColor Red
            Write-Host "Log: $logFile" -ForegroundColor DarkGray
            Write-Host "Aborting to prevent infinite loop." -ForegroundColor Red
            exit $LASTEXITCODE
        }

        $retryCount++
        $elapsed = [math]::Round($runTime.TotalSeconds)
        Write-Host "Server crashed after running for $elapsed s." -ForegroundColor Yellow
        Write-Host "Log: $logFile" -ForegroundColor DarkGray

        if ($retryCount -lt $maxRetries) {
            Write-Host "Restarting in 5 seconds..." -ForegroundColor Yellow
            Start-Sleep -Seconds 5
        }
        else {
            Write-Host "Maximum retries ($displayMax) reached. Abandoning." -ForegroundColor Red
            exit $LASTEXITCODE
        }
    }
}
