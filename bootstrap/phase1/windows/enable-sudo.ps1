# Purpose: Enable Windows sudo via registry modification with safe rollback

# === CONFIGURATION ===
$RegPath      = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\AppModelUnlock"
$RegValueName = "AllowDevelopmentWithoutDevLicense"
$TargetValue  = 1

# === 0. PREREQUISITE ===
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "❌ This script must be run as Administrator."
    exit 1
}

# === 1. BACKUP ===
Write-Host "📦 [BACKUP] Checking current registry state..."
$BackupValue = $null
$KeyExists   = Test-Path -Path $RegPath
if ($KeyExists) {
    $BackupValue = (Get-ItemProperty -Path $RegPath -Name $RegValueName -ErrorAction SilentlyContinue).$RegValueName
    if ($null -ne $BackupValue) {
        Write-Host "   Current value: $BackupValue"
    } else {
        Write-Host "   Value does not exist (will be created)"
    }
} else {
    Write-Host "   ⚠️ Registry path missing. Creating it..."
    New-Item -Path $RegPath -Force | Out-Null
}

# === 2. SET ===
Write-Host "⚙️ [SET] Enabling Windows sudo capability..."
try {
    Set-ItemProperty -Path $RegPath -Name $RegValueName -Value $TargetValue -Type DWord -Force
    Write-Host "   ✅ Value written to registry"
} catch {
    Write-Error "   ❌ Failed to set registry value: $_"
    exit 1
}

# === 3. CHECK ===
Write-Host "🔍 [CHECK] Verifying registry change..."
try {
    $CurrentValue = (Get-ItemProperty -Path $RegPath -Name $RegValueName -ErrorAction Stop).$RegValueName
} catch {
    Write-Error "   ❌ Verification read failed: $_"
    exit 1
}

# === 4. VALID -> DONE ===
if ($CurrentValue -eq $TargetValue) {
    Write-Host "✅ [DONE] sudo capability is now enabled."
    Write-Host "   📝 Note: Sign out/in or restart your PC for the change to take effect."
    exit 0
}

# === 5. INVALID -> RESTORE BACKUP ===
Write-Host "❌ [INVALID] Verification failed. Expected $TargetValue, got $CurrentValue. Rolling back..."
if ($null -ne $BackupValue) {
    Set-ItemProperty -Path $RegPath -Name $RegValueName -Value $BackupValue -Type DWord -Force
    Write-Host "   🔄 Restored backup value: $BackupValue"
} else {
    Remove-ItemProperty -Path $RegPath -Name $RegValueName -Force -ErrorAction SilentlyContinue
    Write-Host "   🔄 Removed newly created value."
}
exit 1
