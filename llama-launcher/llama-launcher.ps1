[CmdletBinding()]
param (
    [string]$ModelFilePath = "",

    [string]$llamaBinary = "",

    [string]$ChatTemplate = "",

    [ValidateRange(0, 999)]
    [int]$NgL = 999,
    
    [ValidateRange(4096, 262144)]
    [int]$CtxSize = 32768, #131072

    [ValidateSet("xhigh", "medium", "low")]
    [string]$Reasoning = "medium",

    [ValidateSet("thinking", "instruct")]
    [string]$Mode = "",

    [string]$HostIP = "0.0.0.0",

    [ValidateRange(1, 65535)]
    [int]$Port = 9931
)

Set-StrictMode -Version Latest
$defaultModel = "Qwen3.8-27B-UD-IQ3_S.mtp.gguf"

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

# defaults from env / prompt for model
if ([string]::IsNullOrWhiteSpace($ModelFilePath)) {

    Write-Host ""
    Write-Host "Available models in $($env:AI_MODELS):" -ForegroundColor Cyan
    $modelFiles = @(Get-ChildItem -Path $env:AI_MODELS -Filter "*.gguf" -ErrorAction SilentlyContinue)
    if ($modelFiles.Count -eq 0) {
        Write-Host "  (no .gguf files found)" -ForegroundColor DarkGray
    }

    # collapse split shards (name-00001-of-00003.gguf) into one entry per model
    $shardPattern = '-\d{5}-of-\d{5}$'
    $groups = @($modelFiles | Group-Object -Property { $_.BaseName -replace $shardPattern, '' })

    # build sortable list: [name, totalSize, firstShardFile]
    $groups = @($groups | ForEach-Object {
            $totalSize = ($_.Group | Measure-Object Length -Sum).Sum
            $firstShard = $_.Group | Where-Object { $_.Name -match '-00001-of-' } | Select-Object -First 1
            [PSCustomObject]@{
                Name       = $_.Name
                TotalSize  = $totalSize
                FirstShard = if ($firstShard) { $firstShard } else { $_.Group | Sort-Object Name | Select-Object -First 1 }
                Count      = $_.Count
            }
        } | Sort-Object TotalSize -Descending)

    # separate the default model out of the numbered list
    $defaultBase = [System.IO.Path]::GetFileNameWithoutExtension($defaultModel) -replace $shardPattern, ''
    $defaultEntry = $groups | Where-Object { $_.Name -eq $defaultBase } | Select-Object -First 1
    $otherEntries = @($groups | Where-Object { $_.Name -ne $defaultBase })
    $models = @($otherEntries | ForEach-Object { $_.FirstShard })

    # --- size formatter ---
    function Format-Size([long]$bytes) {
        if ($bytes -ge 1TB) { "{0:N1} TB" -f ($bytes / 1TB) }
        elseif ($bytes -ge 1GB) { "{0:N1} GB" -f ($bytes / 1GB) }
        elseif ($bytes -ge 1MB) { "{0:N1} MB" -f ($bytes / 1MB) }
        else { "{0:N1} KB" -f ($bytes / 1KB) }
    }


    # --- display ---
    if ($defaultEntry) {
        $sz = Format-Size $defaultEntry.TotalSize
        Write-Host "  [*] $($defaultEntry.FirstShard.Name)  ($sz)" -ForegroundColor Yellow
    }

    $idx = 1
    foreach ($e in $otherEntries) {
        $sz = Format-Size $e.TotalSize
        Write-Host "  [$idx] $($e.FirstShard.Name)  ($sz)" -ForegroundColor White
        $idx++
    }
    Write-Host "  [p] Paste a custom path" -ForegroundColor DarkGray
    Write-Host "  [Enter / *] Use default: $defaultModel" -ForegroundColor DarkGray
    Write-Host ""

    $modelChoice = Read-Host "Select a model (number, path, or 'p')"

    if ([string]::IsNullOrWhiteSpace($modelChoice) -or $modelChoice -eq '*') {
        $ModelFilePath = Join-Path $env:AI_MODELS $defaultModel
    }
    elseif ($modelChoice -eq 'p') {
        $ModelFilePath = Read-Host "Enter model file path"
    }
    elseif ($modelChoice -match '^\d+$' -and [int]$modelChoice -ge 1 -and [int]$modelChoice -le $models.Count) {
        $ModelFilePath = $models[[int]$modelChoice - 1].FullName
    }
    else {
        $ModelFilePath = $modelChoice
    }
}




# chat template: only for Qwen3.8, skip for Flash-Next
$modelFileName = [System.IO.Path]::GetFileName($ModelFilePath)
$isFlashNext = $modelFileName -match '(?i)flash[-_]?next'
$isMtp = $modelFileName -match '(?i)mtp'

if (-not $isFlashNext) {
    if ([string]::IsNullOrWhiteSpace($ChatTemplate)) {
        $ChatTemplate = Join-Path $env:AI_MODELS "Qwen3.5_chat_template.jinja"
    }
}
else {
    Write-Host "Flash-Next model detected — chat template will be skipped." -ForegroundColor DarkGray
    $ChatTemplate = ""
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
elseif (-not [System.IO.Path]::IsPathRooted($llamaBinary)) {
    # bare name / relative-ish input like "ik-llama-server.exe": try PATH resolution
    $resolved = Get-Command $llamaBinary -CommandType Application -ErrorAction SilentlyContinue |
    Select-Object -First 1
    if ($resolved) {
        $llamaBinary = $resolved.Source
    }
}

if (-not (Test-Path $llamaBinary)) {
    Write-Host "Error: Binary not found: $llamaBinary" -ForegroundColor Red
    exit 1
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
if (-not $isFlashNext -and -not (Test-Path $ChatTemplate)) {
    Write-Host "Error: Chat template not found: $ChatTemplate" -ForegroundColor Red
    exit 1
}

# port
$bindAddr = if ($HostIP -eq "0.0.0.0") {
    [System.Net.IPAddress]::Any
}
else {
    [System.Net.IPAddress]::Parse($HostIP)
}
try {
    $listener = [System.Net.Sockets.TcpListener]::new($bindAddr, $Port)
    $listener.Start()
    $listener.Stop()
}
catch [System.Net.Sockets.SocketException] {
    Write-Host "Error: Port $Port is already in use on $HostIP." -ForegroundColor Red
    exit 1
}


Write-Host "=================================================" -ForegroundColor Cyan
Write-Host "                 llama-launcher                  " -ForegroundColor Cyan
Write-Host "=================================================" -ForegroundColor Cyan
Write-Host "  Binary : $llamaBinary" -ForegroundColor Cyan
Write-Host "  Model  : $ModelFilePath" -ForegroundColor Cyan
if (-not $isFlashNext) {
    Write-Host "  ChatTmpl: $ChatTemplate" -ForegroundColor Cyan
}
Write-Host "  Host   : $HostIP : $Port" -ForegroundColor Cyan
Write-Host ""

if ([string]::IsNullOrWhiteSpace($Mode)) {
    $Choice = ""
    while ($Choice -notin @("1", "2")) {
        $Choice = Read-Host "Select Mode:`n[1] Thinking`n[2] Instruct`nEnter choice (1 or 2)"
    }
    $Mode = if ($Choice -eq "1") { "thinking" } else { "instruct" }
}

$ChatKwargs = '{"reasoning_effort":"' + $Reasoning + '"}'
if ($Mode -eq "thinking") {
    Write-Host "Mode: Thinking" -ForegroundColor Yellow
    $modelArgs = @(
        "--temp", "1.0",
        "--top-p", "0.95",
        "--top-k", "20",
        "--min-p", "0.0",
        "--presence-penalty", "0.0",
        "--repeat-penalty", "1.0",
        "--reasoning", "on",
        "--chat-template-kwargs", $ChatKwargs
    )
}
else {
    Write-Host "Mode: Instruct" -ForegroundColor Yellow
    $modelArgs = @(
        "--temp", "0.7",
        "--top-p", "0.80",
        "--top-k", "20",
        "--min-p", "0.0",
        "--presence-penalty", "1.5",
        "--repeat-penalty", "1.0",
        "--reasoning", "off",
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
    "--cache-type-k", "q4_0",
    "--cache-type-v", "q4_0",
    "--alias", "kvstorm1",
    "--flash-attn", "on",
    "--cont-batching",
    "--metrics",
    "--jinja"
)

# chat template only for non-Flash-Next models
if (-not $isFlashNext) {
    $serverArgs += "--chat-template-file", $ChatTemplate
}

# speculative decoding (MTP) only when the model advertises it
if ($isMtp) {
    if ($isIkLlama) {
        $serverArgs += "--spec-type", "mtp:n_max=3,p_min=0.75"
    }
    else {
        $serverArgs += "--spec-type", "draft-mtp"
        $serverArgs += "--spec-draft-n-max", "2"
    }
}

if (-not $isIkLlama) {
    $serverArgs += "--cors-origins", "http://localhost"
    $serverArgs += "--cors-credentials"
    $serverArgs += "--cache-prompt"
    $serverArgs += "--load-mode", "dio" # if dio fails use "none" | "mmap"
}
else {
    $serverArgs += "--no-mmap"
}


$llamaArgs = $serverArgs + $modelArgs

Write-Host ""
Write-Host "  [ Binary ] $llamaBinary" -ForegroundColor Green
Write-Host "  [ Model  ] $ModelFilePath" -ForegroundColor Green
Write-Host "  [ Ctx    ] $CtxSize" -ForegroundColor Green
Write-Host "  [ GPU-L  ] $NgL" -ForegroundColor Green
Write-Host "  [ Mode   ] $Mode" -ForegroundColor Green
if (-not $isFlashNext) {
    Write-Host "  [ ChatT  ] $ChatTemplate" -ForegroundColor Green
}
if ($isMtp) {
    Write-Host "  [ MTP    ] Enabled" -ForegroundColor Green
}
else {
    Write-Host "  [ MTP    ] Disabled" -ForegroundColor Green
}

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

# FIXME: no coloured output from llama-server
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
