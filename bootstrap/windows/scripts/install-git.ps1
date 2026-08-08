# install-git-windows.ps1
# Automates Git for Windows installation with explicit component selection

$InstallerUrl = "https://github.com/git-for-windows/git/releases/download/v2.47.0.windows.1/Git-2.47.0-64-bit.exe"
$InstallerPath = "$env:TEMP\GitInstaller.exe"
$InstallDir    = "$env:USERPROFILE\opt\Git"

# === 1. DOWNLOAD (if not cached) ===
if (-not (Test-Path $InstallerPath)) {
    Write-Host "⬇️ Downloading Git for Windows installer..."
    Invoke-WebRequest -Uri $InstallerUrl -OutFile $InstallerPath -UseBasicParsing
}

# === 2. IDEMPOTENCY CHECK ===
if (Test-Path "$InstallDir\bin\git.exe") {
    Write-Host "✅ Git for Windows already installed, skipping."
    exit 0
}

# === 3. RUN SILENT INSTALLER ===
Write-Host "⚙️ Installing Git for Windows (with OpenSSH & GCM)..."
$Args = @(
    "/VERYSILENT",          # No UI
    "/NOCANCEL",            # Prevents user from cancelling mid-install
    "/NORESTART",           # Doesn't force reboot
    "/DIR=`"$InstallDir`"", # Install location
    "/COMPONENTS=`"gitandunixutils,gitlfs,windowsconsole,shellintegration,gitcredentialmanager,gitssh`"" # Explicit features
)

$Process = Start-Process -FilePath $InstallerPath -ArgumentList $Args -Wait -PassThru

if ($Process.ExitCode -eq 0) {
    Write-Host "✅ Git for Windows installed successfully."
} else {
    Write-Error "❌ Git installation failed with exit code $($Process.ExitCode)"
    exit 1
}

# === 4. REFRESH PATH IN CURRENT SESSION ===
# Git installer updates system/user PATH, but running PowerShell won't see it yet
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "User") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "Machine")
Write-Host "🔄 PATH refreshed for current session."
