# --- Parameter Definition ---
param(
    [int]$NgL = 999 
)


# --- Configuration Variables ---
$MODEL_FILENAME = "MTP/Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf"
$AI_MODELS_PATH = $env:AI_MODELS
$MODEL_PATH = Join-Path $AI_MODELS_PATH $MODEL_FILENAME
$CONTEXT_SIZE = 262144 
$MAX_MODE_ATTEMPTS = 5 
llama-server --cors-origins http://localhost,http://192.168.10.240,http://192.168.0.197 --cors-credentials --host 192.168.10.240,192.168.0.197 --port 8080 --alias kvstorm1 --min-p 0 --model ~/Downloads/MTP/Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf --ctx-size 262144 --jinja --flash-attn on -np 1 --spec-type draft-mtp --spec-draft-n-max 2 --cont-batching --metrics --cache-prompt --gpu-layers 999 --repeat-penalty 0 --temp 0.6 --top-p 0.95 --top-k 20 --presence-penalty 0 \
# --- Helper Functions ---

function Get-BaseArgs {
    param(
        [string]$ModelPath,
        [int]$Context,
        [int]$NgL,
        [float]$RepeatPenalty
    )

    if (-not $env:LLAMA_API_KEY) {
        Write-Error "LLAMA_API_KEY environment variable is not set. Please set it before running."
        exit
    }
    
    return @(
        "--cors-origins", "http://localhost,http://192.168.10.246",
        "--cors-credentials",
        "--host", "192.168.10.246",
        "--port", "8080",
        "--alias", "kvstorm1",
        "--min-p", "0",
        "--model", $ModelPath,
        "--ctx-size", $Context,
        # "--multiline-input",
        "--jinja",
        "--flash-attn", "on",
        "-np", "1",
        "--spec-type", "draft-mtp",
        "--spec-draft-n-max", "2",
        "--cont-batching",
        "--metrics",
        "--cache-prompt",
        # runtime variables
        #--split-mode 
        "--gpu-layers", $NgL, 
        "--repeat-penalty", $RepeatPenalty      
    )
}

function Get-ThinkingArgs {
    param(
        [float]$Temperature,
        [float]$TopP,
        [int]$TopK,
        [float]$PresencePenalty
    )
    return @(
        "--temp", $Temperature,
        "--top-p", $TopP,
        "--top-k", $TopK,
        "--presence-penalty", $PresencePenalty
    )
}

function Get-InstructArgs {
    param(
        [float]$Temperature,
        [float]$TopP,
        [int]$TopK,
        [float]$PresencePenalty
    )
    $ChatKwargs = '{"enable_thinking": false}'
    return @(
        "--temp", $Temperature,
        "--top-p", $TopP,
        "--top-k", $TopK,
        "--presence-penalty", $PresencePenalty,
        "--chat-template-kwargs", $ChatKwargs
    )
}

# --- Execution ---

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "   Llama-SERVER Launcher: Qwen3.6-35B-A3B-MTP-GGUF" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

if (-not $env:AI_MODELS) {
    Write-Error "Environment variable AI_MODELS is not set."
    exit 1
}

if (-not (Test-Path $MODEL_PATH)) {
    Write-Error "Model file not found at: $MODEL_PATH"
    Write-Host "Please ensure '$MODEL_FILENAME' exists in $AI_MODELS_PATH"
    exit 1
}

Write-Host "Model: $MODEL_FILENAME" -ForegroundColor Green
Write-Host "GPU Layers: $NgL" -ForegroundColor Yellow
Write-Host "Context Window: $CONTEXT_SIZE" -ForegroundColor Yellow

# Menu Loop with Attempt Tracking
$attemptCount = 0
$isValid = $false


do {
    $attemptCount++
    $remaining = $MAX_MODE_ATTEMPTS - $attemptCount

    Write-Host "`nSelect Mode:" -ForegroundColor Cyan
    Write-Host "1. Thinking (Precise Coding)" -ForegroundColor White
    Write-Host "2. Thinking (General Tasks)" -ForegroundColor White
    Write-Host "3. Instruct (General Tasks)" -ForegroundColor White
    Write-Host "4. Instruct (Reasoning)" -ForegroundColor White
    Write-Host "0. Exit" -ForegroundColor White

    $Choice = Read-Host "Enter choice (0-4)"

    if ($Choice -match "^[0-4]$") {
        $isValid = $true
    }
    else {
        if ($remaining -gt 0) {
            Write-Warning "Invalid. $remaining attempts remaining."
        }
        else {
            Write-Error "Max attempts reached. Exiting."
            exit 1
        }
    }
} while (-not $isValid)

if ($Choice -eq "0") {
    Write-Host "Exiting." -ForegroundColor Gray
    exit 0
}


$llamaArgs = Get-BaseArgs -ModelPath $MODEL_PATH -Context $CONTEXT_SIZE -NgL $NgL -RepeatPenalty $RepeatPenalty 

switch ($Choice) {
    "1" { $llamaArgs += Get-ThinkingArgs -Temperature 0.6 -TopP 0.95 -TopK 20 -PresencePenalty 0.0 }
    "2" { $llamaArgs += Get-ThinkingArgs -Temperature 1.0 -TopP 0.95 -TopK 20 -PresencePenalty 1.5 }
    "3" { $llamaArgs += Get-InstructArgs -Temperature 0.7 -TopP 0.8 -TopK 20 -PresencePenalty 1.5 }
    "4" { $llamaArgs += Get-InstructArgs -Temperature 1.0 -TopP 0.95 -TopK 20 -PresencePenalty 1.5 }
}

Write-Host "`nStarting llama-server..." -ForegroundColor Green
Write-Host "Command: llama-server $($llamaArgs)" -ForegroundColor White
Write-Host "==================================================" -ForegroundColor Cyan

& llama-server $llamaArgs

if ($LASTEXITCODE -ne 0) {
    Write-Error "llama-server exited with code $LASTEXITCODE"
}
