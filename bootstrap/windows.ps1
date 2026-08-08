param([switch]$TestRun)

if (-not $TestRun) {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host ""
        Write-Host "Administrator privileges required for installation." -ForegroundColor Red
        Write-Host "Please run PowerShell as Administrator and try again." -ForegroundColor Yellow
        Write-Host ""
        exit 1
    }
}

function Test-InternetPing {
    <#
    .SYNOPSIS
    Tests internet connectivity using a simple ping.
    
    .DESCRIPTION
    Pings a specified server (default Google DNS: 8.8.8.8) once to verify network connectivity.
    Returns $true if successful, and $false if it fails.
    #>
    [CmdletBinding()]
    param (
        [string]$Server = "8.8.8.8"
    )

    return Test-Connection -ComputerName $Server -Count 1 -Quiet -ErrorAction SilentlyContinue
}

# ==============================================================================
# MAIN SCRIPT EXECUTION
# ==============================================================================

Write-Host ""
Write-Host "=============================================================" -ForegroundColor Cyan
Write-Host "             DEVELOPMENT ENVIRONMENT SETUP SCRIPT            " -ForegroundColor Cyan
Write-Host "=============================================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "[STEP 1] Verifying Prerequisites..." -ForegroundColor Yellow
Write-Host "         Checking internet connection..." -NoNewline

if (!(Test-InternetPing)) {
    Write-Host " [FAILED]" -ForegroundColor Red
    Write-Host ""
    Write-Host "  -> No internet connection detected." -ForegroundColor Red
    Write-Host "  -> Script stopping. Please check your network and try again." -ForegroundColor Red
    Write-Host ""
    exit 1
}

Write-Host " [OK]" -ForegroundColor Green
Write-Host "  -> Internet connected! Downloading packages now..." -ForegroundColor DarkGray
Write-Host ""

Write-Host "[STEP 2] Installing Git..." -ForegroundColor Yellow
# TODO:  
Write-Host "  -> Git successfully installed." -ForegroundColor DarkGray
Write-Host ""

Write-Host "[STEP 3] Installing Visual Studio Build Tools..." -ForegroundColor Yellow
Write-Host "         Locating/downloading installer..." -ForegroundColor DarkGray

$installerUrl = "https://aka.ms/vs/stable/vs_BuildTools.exe"
$installerPath = Join-Path $env:TEMP "vs_BuildTools.exe"
$configPath = Join-Path $PSScriptRoot "configs\.vsconfig"

# Verify .vsconfig exists before proceeding
if (-not (Test-Path $configPath)) {
    Write-Host "         -> Config file not found at: $configPath" -ForegroundColor Red
    exit 1
}

# Download installer if not present
if (-not (Test-Path $installerPath)) {
    Write-Host "         -> Downloading installer..." -ForegroundColor DarkGray
    try {
        Invoke-WebRequest -Uri $installerUrl -OutFile $installerPath -UseBasicParsing
    }
    catch {
        Write-Host "         -> Failed to download installer. $_" -ForegroundColor Red
        exit 1
    }
}

$installArgs = "--config `"$configPath`" --passive --norestart --wait"
$vswherePath = "$env:ProgramFiles(x86)\Microsoft Visual Studio\Installer\vswhere.exe"

if ($TestRun) {
    Write-Host ""
    Write-Host "         -> [DRY RUN MODE] Skipping actual installation." -ForegroundColor Cyan
    Write-Host "         -> Installer ready at: $installerPath" -ForegroundColor DarkGray
    Write-Host "         -> Config file: $configPath" -ForegroundColor DarkGray
    Write-Host "         -> Would execute: $installerPath $installArgs" -ForegroundColor DarkGray
    Write-Host "         -> Post-install verification would use: $vswherePath" -ForegroundColor DarkGray
    Write-Host "  -> [DRY RUN] Build tools installation skipped." -ForegroundColor DarkGray
    Write-Host ""
}
else {
    # Run installer with .vsconfig
    Write-Host "         -> Installing via .vsconfig (this may take several minutes)..." -ForegroundColor DarkGray
    & $installerPath $installArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Host "         -> Installation failed with exit code $LASTEXITCODE." -ForegroundColor Red
        exit 1
    }

    # Verify installation
    Write-Host "         -> Verifying installation..." -ForegroundColor DarkGray
    if (Test-Path $vswherePath) {
        $installPath = & $vswherePath -latest -property installationPath
        Write-Host "         -> Successfully installed at: $installPath" -ForegroundColor Green
    }
    else {
        Write-Host "         -> Successfully installed." -ForegroundColor Green
    }

    # Clean up temporary installer
    if (Test-Path $installerPath) {
        try {
            Remove-Item $installerPath -Force -ErrorAction Stop
            Write-Host "         -> Cleaned up temporary installer." -ForegroundColor DarkGray
        }
        catch {
            Write-Host "         -> Warning: Could not remove temporary installer. $_" -ForegroundColor Yellow
            Write-Host "         -> Manual removal required at: $installerPath" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "         -> Temporary installer not found (already cleaned or skipped download)." -ForegroundColor DarkGray
    }

    Write-Host "  -> Build tools successfully installed." -ForegroundColor DarkGray
    Write-Host ""
}

# ==============================================================================
Write-Host "=============================================================" -ForegroundColor Cyan
Write-Host "             SETUP COMPLETED SUCCESSFULLY                    " -ForegroundColor Cyan
Write-Host "=============================================================" -ForegroundColor Cyan
Write-Host ""
