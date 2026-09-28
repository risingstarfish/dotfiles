#!/usr/bin/env pwsh
# dotfiles.ps1

$ErrorActionPreference = 'Stop'

# D3: Home directory resolution parity
$resolvedHome = ""
if (-not [string]::IsNullOrEmpty($env:HOME) -and [System.IO.Directory]::Exists($env:HOME)) {
    $resolvedHome = $env:HOME
} elseif (-not [string]::IsNullOrEmpty($env:USERPROFILE) -and [System.IO.Directory]::Exists($env:USERPROFILE)) {
    $resolvedHome = $env:USERPROFILE
} elseif (-not [string]::IsNullOrEmpty($HOME) -and [System.IO.Directory]::Exists($HOME)) {
    $resolvedHome = $HOME
}

if ([string]::IsNullOrEmpty($resolvedHome) -or -not [System.IO.Directory]::Exists($resolvedHome)) {
    [Console]::Error.Write("Error: unable to resolve `$HOME")
    exit 1
}

$env:HOME = $resolvedHome
if ([string]::IsNullOrEmpty($env:USERPROFILE)) {
    $env:USERPROFILE = $resolvedHome
}

$script:DOTFILES_START_TIME = if (-not [string]::IsNullOrEmpty($env:DOTFILES_START_TIME)) {
    $env:DOTFILES_START_TIME
} else {
    [DateTime]::Now.ToString("yyyy-MM-dd_HHmmss")
}
$script:DOTFILES_ENV = if (-not [string]::IsNullOrEmpty($env:DOTFILES_ENV)) { $env:DOTFILES_ENV } else { "production" }
$script:DOTFILES_LOG_DIR = if (-not [string]::IsNullOrEmpty($env:DOTFILES_LOG_DIR)) { $env:DOTFILES_LOG_DIR } else { "$($env:HOME)/.config/dotfiles/logs" }
$script:INIT_LOG_FILE = "$($script:DOTFILES_LOG_DIR)/initialise.log"
$script:DOTFILES_CACHE_DIR = if (-not [string]::IsNullOrEmpty($env:DOTFILES_CACHE_DIR)) { $env:DOTFILES_CACHE_DIR } else { "$($env:HOME)/.cache/dotfiles" }
$script:DOTFILES_BACKUP_DIR = "$($script:DOTFILES_CACHE_DIR)/backups"
$script:DOTFILES_MANIFEST_FILE = "$($script:DOTFILES_CACHE_DIR)/manifest.tsv"
$script:DOTFILES_LOCK_FILE = "$($script:DOTFILES_CACHE_DIR)/dotfiles.lock"
$script:DOTFILES_LOCK_TIMEOUT = if (-not [string]::IsNullOrEmpty($env:DOTFILES_LOCK_TIMEOUT)) { [int]$env:DOTFILES_LOCK_TIMEOUT } else { 3600 }
$script:DOTFILES_LOG = if (-not [string]::IsNullOrEmpty($env:DOTFILES_LOG)) { $env:DOTFILES_LOG } else { "1" }
$script:SILENCE_INIT_LOG_MSG = "true"
$script:DOTFILES_LOCAL_MODS = if (-not [string]::IsNullOrEmpty($env:DOTFILES_LOCAL_MODS)) { $env:DOTFILES_LOCAL_MODS } else { "0" }
$script:DOTFILES_MAX_BACKUPS = if (-not [string]::IsNullOrEmpty($env:DOTFILES_MAX_BACKUPS)) { $env:DOTFILES_MAX_BACKUPS } else { "10" }
$script:DOTFILES_AUTORESTART = if (-not [string]::IsNullOrEmpty($env:DOTFILES_AUTORESTART)) { $env:DOTFILES_AUTORESTART } else { "0" }
$script:DOTFILES_IGNORE_HANDOFF = if (-not [string]::IsNullOrEmpty($env:DOTFILES_IGNORE_HANDOFF)) { $env:DOTFILES_IGNORE_HANDOFF } else { "0" }

# OS constants
$script:OS_CACHYOS = 'cachyos'
$script:OS_MACOS   = 'macos'
$script:OS_WINDOWS = 'windows'
$script:OS_DEBIAN  = 'debian'
$script:OS_UNKNOWN = 'unknown'

# Runtime constants
$script:RUNTIME_NATIVE  = 'native'
$script:RUNTIME_WSL     = 'wsl'
$script:RUNTIME_GITBASH = 'gitbash'
$script:RUNTIME_UNKNOWN = 'unknown'

$script:WINDOWS_SUDO_REG_LOCATION = 'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Sudo'

# Runtime state: single flat namespace (DF_*) matching dotfiles.sh:40-65
$script:DF_MAIN_ACTION         = ""
$script:DF_LOG_LEVEL           = ""
$script:DF_DRY_RUN             = 0
$script:DF_NOCONFIRM           = 0
$script:DF_INTERACTIVE         = 0
$script:DF_FORCE               = 0
$script:DF_NO_LOG              = 0
$script:DF_PRINT_TIME          = 0
$script:DF_NO_REGENERATE       = 0
$script:DF_NO_BACKUP           = 0
$script:DF_REMOVE_ERRORS       = 0
$script:DF_UNINSTALL_ERRORS    = 0
$script:DF_REPAIR_ERRORS       = 0
$script:DF_RESET_ERRORS        = 0
$script:DF_CLEAN_ERRORS        = 0
$script:DF_CLEAN_DAYS          = ""
$script:DF_CLEAN_KEEP          = ""
$script:DF_ERROR_COUNT         = 0
$script:DF_CLEAN_LOGS          = 0
$script:DF_CLEAN_BACKUPS       = 0
$script:DF_SRC_PATH            = ""
$script:DF_MODULE_DIR          = ""
$script:DF_TARGET_OS           = if ($env:DF_TARGET_OS) { $env:DF_TARGET_OS } else { "" }
$script:DF_TARGET_RUNTIME      = if ($env:DF_TARGET_RUNTIME) { $env:DF_TARGET_RUNTIME } else { "" }
$script:DF_TARGET_ENV          = if ($env:DF_TARGET_ENV) { $env:DF_TARGET_ENV } else { "" }
$script:DF_IS_ELEVATED         = if ($env:DF_IS_ELEVATED) { [int]$env:DF_IS_ELEVATED } else { $null }
$script:WINDOWS_SUDO           = if ($env:WINDOWS_SUDO) { [int]$env:WINDOWS_SUDO } else { $null }
$script:DF_MANIFEST            = @()
$script:DF_AVAILABLE_MODULES   = @()
$script:DF_ALL_MODULES         = @()
$script:DF_UNAVAILABLE_MODULES = @{}
$script:DF_MODULE_ACTION       = @{}
$script:DF_MODULE_DEST         = @{}
$script:DF_MODULE_CMD          = @{}
$script:DF_CATEGORY_MAP        = @{}
$script:DF_USER_MODULES        = @()

$script:SOURCE_FILES = @(
    "source/utility.ps1",
    "source/print.ps1",
    "source/argparse.ps1",
    "source/action.ps1"
)

function pwsh_version_check {
    log_trace "Entering (PSVersion='$($PSVersionTable.PSVersion)')"
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        log_error "PowerShell v5.1 or newer required. Detected: $($PSVersionTable.PSVersion)"
        [Console]::Error.WriteLine("Error: This script requires PowerShell v5.1 or newer.")
        return $false
    }
    log_debug "PowerShell version $($PSVersionTable.PSVersion) validated successfully."
    return $true
}

function _set_src_path {
    log_trace "Entering (DF_SRC_PATH='$($script:DF_SRC_PATH)')"
    if (-not [string]::IsNullOrEmpty($script:DF_SRC_PATH)) {
        log_debug "DF_SRC_PATH is already set to '$($script:DF_SRC_PATH)'. Skipping."
        return $true
    }
    if ([string]::IsNullOrEmpty($PSScriptRoot)) {
        log_error "Unable to determine source path from PSScriptRoot."
        return $false
    }
    $item = Get-Item -LiteralPath $PSScriptRoot -Force
    $resolved = $item.FullName
    $script:DF_SRC_PATH = $resolved.Replace('\', '/').TrimEnd('/')
    log_debug "Resolved DF_SRC_PATH='$($script:DF_SRC_PATH)'"
    return $true
}

function _set_module_dir {
    log_trace "Entering (DF_MODULE_DIR='$($script:DF_MODULE_DIR)', DF_SRC_PATH='$($script:DF_SRC_PATH)')"
    if (-not [string]::IsNullOrEmpty($script:DF_MODULE_DIR)) {
        return $true
    }
    $script:DF_MODULE_DIR = "$($script:DF_SRC_PATH)/modules"
    $nativeModDir = _native_path $script:DF_MODULE_DIR
    if (-not [System.IO.Directory]::Exists($nativeModDir)) {
        log_error "Unable to locate module directory at '$($script:DF_MODULE_DIR)'"
        [Console]::Error.WriteLine("Error: unable to locate modules/.")
        return $false
    }
    log_debug "Verified module directory exists at '$($script:DF_MODULE_DIR)'"
    return $true
}

function _set_target_env {
    log_trace "Entering (DF_TARGET_OS='$($script:DF_TARGET_OS)', DF_TARGET_RUNTIME='$($script:DF_TARGET_RUNTIME)', DF_TARGET_ENV='$($script:DF_TARGET_ENV)')"
    if (-not [string]::IsNullOrEmpty($script:DF_TARGET_OS) -or -not [string]::IsNullOrEmpty($script:DF_TARGET_RUNTIME) -or -not [string]::IsNullOrEmpty($script:DF_TARGET_ENV)) {
        if ([string]::IsNullOrEmpty($script:DF_TARGET_RUNTIME)) {
            $script:DF_TARGET_RUNTIME = $script:RUNTIME_NATIVE
        }
        if ([string]::IsNullOrEmpty($script:DF_TARGET_ENV)) {
            $script:DF_TARGET_ENV = "$($script:DF_TARGET_OS)-$($script:DF_TARGET_RUNTIME)"
        }
        log_debug "Environment variables already set. Skipping environment detection."
        return $true
    }

    if ($IsWindows -or $env:OS -eq "Windows_NT") {
        $script:DF_TARGET_OS = $script:OS_WINDOWS
        $script:DF_TARGET_RUNTIME = $script:RUNTIME_NATIVE
    } elseif ($IsMacOS) {
        $script:DF_TARGET_OS = $script:OS_MACOS
        $script:DF_TARGET_RUNTIME = $script:RUNTIME_NATIVE
    } elseif ($IsLinux) {
        $unameR = (& uname -r 2>$null | Out-String).Trim()
        if ($unameR -match '(?i)microsoft') {
            $script:DF_TARGET_RUNTIME = $script:RUNTIME_WSL
        } else {
            $script:DF_TARGET_RUNTIME = $script:RUNTIME_NATIVE
        }
        if ([System.IO.File]::Exists("/etc/os-release")) {
            $osRel = [System.IO.File]::ReadAllText("/etc/os-release")
            if ($osRel -match '(?im)^ID=.*cachyos') {
                $script:DF_TARGET_OS = $script:OS_CACHYOS
            } elseif ($osRel -match '(?im)^ID(_LIKE)?=.*debian' -or [System.IO.File]::Exists("/etc/debian_version")) {
                $script:DF_TARGET_OS = $script:OS_DEBIAN
            } else {
                $script:DF_TARGET_OS = $script:OS_UNKNOWN
            }
        } else {
            $script:DF_TARGET_OS = $script:OS_UNKNOWN
        }
    } else {
        $script:DF_TARGET_OS = $script:OS_UNKNOWN
        $script:DF_TARGET_RUNTIME = $script:RUNTIME_UNKNOWN
    }

    $script:DF_TARGET_ENV = "$($script:DF_TARGET_OS)-$($script:DF_TARGET_RUNTIME)"
    log_debug "Detected environment: DF_TARGET_OS='$($script:DF_TARGET_OS)', DF_TARGET_RUNTIME='$($script:DF_TARGET_RUNTIME)', DF_TARGET_ENV='$($script:DF_TARGET_ENV)'"

    if ($script:DF_TARGET_OS -eq $script:OS_UNKNOWN -or $script:DF_TARGET_RUNTIME -eq $script:RUNTIME_UNKNOWN) {
        log_error "Failed to fully detect target environment."
        return $false
    }
    return $true
}

function _set_windows_sudo {
    _enter
    if ($null -ne $script:WINDOWS_SUDO) {
        _exit
        return
    }
    $script:WINDOWS_SUDO = 0
    if ($IsWindows) {
        $sudoCmd = Get-Command sudo -ErrorAction SilentlyContinue
        $regCmd  = Get-Command reg.exe -ErrorAction SilentlyContinue
        if ($null -ne $sudoCmd -and $null -ne $regCmd) {
            $sudoReg = (& reg.exe query $script:WINDOWS_SUDO_REG_LOCATION /v Enabled 2>$null | Out-String)
            if ($sudoReg -match '0x[1-3]') {
                $script:WINDOWS_SUDO = 1
            }
        }
    }
    _exit
}

function _set_date_cmd {
    _enter
    $script:DF_DATE_CMD = "Get-Date"
    $script:DF_DATE_FMT = "yyyy-MM-dd HH:mm:ss.fff"
    _exit
}

function _set_is_elevated {
    _enter
    if ($null -ne $script:DF_IS_ELEVATED) {
        _exit
        return
    }
    $script:DF_IS_ELEVATED = 0
    if ($IsWindows) {
        try {
            $principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
            if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
                $script:DF_IS_ELEVATED = 1
            }
        } catch {}
    } else {
        $uid = (& id -u 2>$null | Out-String).Trim()
        if ($uid -eq "0" -or -not [string]::IsNullOrEmpty($env:SUDO_USER)) {
            $script:DF_IS_ELEVATED = 1
        }
    }
    log_debug "Privilege level DF_IS_ELEVATED=$($script:DF_IS_ELEVATED)"
    _exit
}

function _set_dotfiles_manifest {
    _enter
    if ($script:DF_MANIFEST -and $script:DF_MANIFEST.Count -gt 0) {
        _exit
        return
    }

    $homePath = ($env:HOME).Replace('\', '/').TrimEnd('/')
    $topgrade_dest = if ($script:DF_TARGET_OS -eq $script:OS_WINDOWS) {
        $appData = if ($env:APPDATA) { ($env:APPDATA).Replace('\', '/').TrimEnd('/') } else { "${homePath}/AppData/Roaming" }
        "${appData}/topgrade/topgrade.toml"
    } else {
        $xdg = if ($env:XDG_CONFIG_HOME) { ($env:XDG_CONFIG_HOME).Replace('\', '/').TrimEnd('/') } else { "${homePath}/.config" }
        "${xdg}/topgrade.toml"
    }

    $script:DF_MANIFEST = @(
        "symlink|zsh/zshrc|${homePath}/.zshrc",
        "symlink|zsh/zsh_options|${homePath}/.zsh_options",
        "symlink|zsh/zstyles|${homePath}/.zstyles",
        "symlink|zsh/zimrc|${homePath}/.zimrc",
        "symlink|zsh/p10k.zsh|${homePath}/.p10k.zsh",
        "symlink|zsh/exports|${homePath}/.exports",
        "symlink|zsh/paths|${homePath}/.paths",
        "symlink|zsh/aliases|${homePath}/.aliases",
        "symlink|zsh/functions|${homePath}/.functions",
        "symlink|zsh/zshrc.toggles|${homePath}/.zshrc.toggles",

        "symlink|bash/bashrc|${homePath}/.bashrc",

        "symlink|git/gitconfig|${homePath}/.gitconfig",
        "copy|git/gitconfig.local.$($script:DF_TARGET_OS)|${homePath}/.gitconfig.local",
        "symlink|git/gitignore|${homePath}/.gitignore",
        "symlink|git/gitattributes|${homePath}/.gitattributes",
        "symlink|git/diff-so-fancy|${homePath}/.local/bin/diff-so-fancy|chmod +x ${homePath}/.local/bin/diff-so-fancy",

        "symlink|ssh/config|${homePath}/.ssh/config|chmod 600 ${homePath}/.ssh/config",
        "generate|ssh/allowed_signers.gen|${homePath}/.ssh/allowed_signers|chmod 600 ${homePath}/.ssh/allowed_signers",

        "symlink|dev/cmakepreset.py|${homePath}/.local/bin/cmakepreset.py|chmod 600 ${homePath}/.local/bin/cmakepreset.py",
        "symlink|dev/internal-flags.cmake|${homePath}/dev/internal-flags.cmake",
        "symlink|dev/cmake-format.py|${homePath}/dev/.cmake-format.py",
        "symlink|dev/clang-format|${homePath}/dev/.clang-format",
        "symlink|dev/clang-tidy|${homePath}/dev/.clang-tidy",
        "symlink|dev/editorconfig|${homePath}/dev/.editorconfig",

        "symlink|topgrade/topgrade.toml|${topgrade_dest}",
        "symlink|fastfetch/config.jsonc.$($script:DF_TARGET_OS)|${homePath}/.config/fastfetch/config.jsonc",
        "symlink|tmux/tmux.conf.$($script:DF_TARGET_OS)|${homePath}/.tmux.conf",
        "symlink|curl/curlrc|${homePath}/.curlrc",
        "symlink|wget/wgetrc|${homePath}/.wgetrc",
        "symlink|shellcheck/shellcheckrc|${homePath}/.shellcheckrc",

        "symlink|claude/settings.json|${homePath}/.claude/settings.json",
        "symlink|claude/plugin.json|${homePath}/.claude/plugin.json",

        "copy|pwsh.$($script:DF_TARGET_OS)/Profile|${homePath}/Documents/Powershell/Microsoft.PowerShell_profile.ps1",
        "copy|pwsh.$($script:DF_TARGET_OS)/Set-MSVC-Environment|${homePath}/Documents/Powershell/Scripts/Set-MSVC-Environment.ps1",
        "copy|pwsh.$($script:DF_TARGET_OS)/Update-Modules|${homePath}/Documents/Powershell/Scripts/Update-Modules.ps1",
        "copy|pwsh.$($script:DF_TARGET_OS)/Print-Env|${homePath}/Documents/Powershell/Scripts/Print-Env.ps1",
        "copy|pwsh.$($script:DF_TARGET_OS)/nproc|${homePath}/Documents/Powershell/Scripts/nproc.ps1",
        "copy|pwsh.$($script:DF_TARGET_OS)/sha256|${homePath}/Documents/Powershell/Scripts/sha256.ps1",
        "copy|pwsh.$($script:DF_TARGET_OS)/sha1|${homePath}/Documents/Powershell/Scripts/sha1.ps1",
        "copy|pwsh.$($script:DF_TARGET_OS)/md5|${homePath}/Documents/Powershell/Scripts/md5.ps1",
        "copy|pwsh.$($script:DF_TARGET_OS)/Exports|${homePath}/Documents/Powershell/Scripts/Exports.ps1",
        "copy|pwsh.$($script:DF_TARGET_OS)/Paths|${homePath}/Documents/Powershell/Scripts/Paths.ps1",
        "copy|pwsh.$($script:DF_TARGET_OS)/Aliases|${homePath}/Documents/Powershell/Scripts/Aliases.ps1",
        "copy|pwsh.$($script:DF_TARGET_OS)/Functions|${homePath}/Documents/Powershell/Scripts/Functions.ps1",

        "symlink|oh-my-posh.$($script:DF_TARGET_OS)/themes/tiger.omp.json|${homePath}/.oh-my-posh/themes/tiger.omp.json",
        "symlink|oh-my-posh.$($script:DF_TARGET_OS)/themes/agnoster.omp.json|${homePath}/.oh-my-posh/themes/agnoster.omp.json",
        "symlink|oh-my-posh.$($script:DF_TARGET_OS)/themes/kushal.omp.json|${homePath}/.oh-my-posh/themes/kushal.omp.json",
        "symlink|oh-my-posh.$($script:DF_TARGET_OS)/themes/powerlevel10k_classic.omp.json|${homePath}/.oh-my-posh/themes/powerlevel10k_classic.omp.json",
        "symlink|oh-my-posh.$($script:DF_TARGET_OS)/themes/powerlevel10k_lean.omp.json|${homePath}/.oh-my-posh/themes/powerlevel10k_lean.omp.json",
        "symlink|oh-my-posh.$($script:DF_TARGET_OS)/themes/powerlevel10k_modern.omp.json|${homePath}/.oh-my-posh/themes/powerlevel10k_modern.omp.json"
    )
    _exit
}

function _populate_arrays {
    _enter
    if ($script:DF_AVAILABLE_MODULES.Count -gt 0 -and $script:DF_MODULE_ACTION.Count -gt 0) {
        log_debug "Module arrays are already populated. Skipping."
        _exit
        return
    }

    $active_modules = [System.Collections.Generic.List[string]]::new()
    $all_modules    = [System.Collections.Generic.List[string]]::new()

    foreach ($item in $script:DF_MANIFEST) {
        $parts    = $item -split '\|'
        $action   = $parts[0]
        $src      = $parts[1]
        $dest     = $parts[2]
        $post_cmd = if ($parts.Count -ge 4) { $parts[3] } else { "" }

        $raw_cat = $src.Substring(0, $src.IndexOf('/'))
        $display_cat = $raw_cat
        if ($display_cat.EndsWith(".$($script:DF_TARGET_ENV)")) {
            $display_cat = $display_cat.Substring(0, $display_cat.Length - ".$($script:DF_TARGET_ENV)".Length)
        } elseif ($display_cat.EndsWith(".$($script:DF_TARGET_OS)")) {
            $display_cat = $display_cat.Substring(0, $display_cat.Length - ".$($script:DF_TARGET_OS)".Length)
        } elseif (-not [string]::IsNullOrEmpty($script:DF_TARGET_RUNTIME) -and $display_cat.EndsWith(".$($script:DF_TARGET_RUNTIME)")) {
            $display_cat = $display_cat.Substring(0, $display_cat.Length - ".$($script:DF_TARGET_RUNTIME)".Length)
        }
        $script:DF_CATEGORY_MAP[$display_cat] = $raw_cat

        # D4 Step 1: Explicit OS exclusion check
        if ($src -eq "topgrade/topgrade.toml" -and $script:DF_TARGET_OS -eq $script:OS_WINDOWS) {
            log_warn "Skipping module '${src}': not supported on OS '$($script:DF_TARGET_OS)'"
            [void]$all_modules.Add($src)
            $script:DF_UNAVAILABLE_MODULES[$src] = 1
            $script:DF_MODULE_ACTION[$src] = $action
            $script:DF_MODULE_DEST[$src]   = $dest
            $script:DF_MODULE_CMD[$src]    = $post_cmd
            continue
        }

        # D4 Step 2 & 3: Exact match -> Runtime suffix fallback -> Base file/dir fallback
        $resolved_src = $src
        $nativeCandidate = _native_path "$($script:DF_MODULE_DIR)/${resolved_src}"

        if (-not ([System.IO.File]::Exists($nativeCandidate) -or [System.IO.Directory]::Exists($nativeCandidate))) {
            if ($src.EndsWith(".$($script:DF_TARGET_OS)") -and -not [string]::IsNullOrEmpty($script:DF_TARGET_RUNTIME)) {
                $rt_src = $src.Substring(0, $src.Length - ".$($script:DF_TARGET_OS)".Length) + ".$($script:DF_TARGET_RUNTIME)"
                $nativeRt = _native_path "$($script:DF_MODULE_DIR)/${rt_src}"
                if ([System.IO.File]::Exists($nativeRt) -or [System.IO.Directory]::Exists($nativeRt)) {
                    $resolved_src = $rt_src
                    $nativeCandidate = $nativeRt
                    log_debug "Module '${src}' resolved via runtime fallback to '${resolved_src}'"
                }
            }
        }

        if (-not ([System.IO.File]::Exists($nativeCandidate) -or [System.IO.Directory]::Exists($nativeCandidate))) {
            $base_src = $src
            if ($base_src.EndsWith(".$($script:DF_TARGET_ENV)")) {
                $base_src = $base_src.Substring(0, $base_src.Length - ".$($script:DF_TARGET_ENV)".Length)
            } elseif ($base_src.EndsWith(".$($script:DF_TARGET_OS)")) {
                $base_src = $base_src.Substring(0, $base_src.Length - ".$($script:DF_TARGET_OS)".Length)
            } elseif ($base_src.Contains(".$($script:DF_TARGET_OS)/")) {
                $base_src = $base_src.Replace(".$($script:DF_TARGET_OS)/", "/")
            }
            if ($base_src -ne $src) {
                $nativeBase = _native_path "$($script:DF_MODULE_DIR)/${base_src}"
                if ([System.IO.File]::Exists($nativeBase) -or [System.IO.Directory]::Exists($nativeBase)) {
                    $resolved_src = $base_src
                    $nativeCandidate = $nativeBase
                    log_debug "Module '${src}' resolved via base fallback to '${resolved_src}'"
                }
            }
        }

        # D4 Step 4: Visible skip on missing source
        if (-not ([System.IO.File]::Exists($nativeCandidate) -or [System.IO.Directory]::Exists($nativeCandidate))) {
            log_warn "Skipping unavailable module '${src}': source does not exist at '$($script:DF_MODULE_DIR)/${src}'"
            [void]$all_modules.Add($src)
            $script:DF_UNAVAILABLE_MODULES[$src] = 1
            $script:DF_MODULE_ACTION[$src] = $action
            $script:DF_MODULE_DEST[$src]   = $dest
            $script:DF_MODULE_CMD[$src]    = $post_cmd
            continue
        }

        log_debug "Module available: '${resolved_src}'"
        [void]$active_modules.Add($resolved_src)
        [void]$all_modules.Add($resolved_src)

        $script:DF_MODULE_ACTION[$resolved_src] = $action
        $script:DF_MODULE_DEST[$resolved_src]   = $dest
        $script:DF_MODULE_CMD[$resolved_src]    = $post_cmd

        $raw_cat = $resolved_src.Substring(0, $resolved_src.IndexOf('/'))
        $display_cat = $raw_cat
        if ($display_cat.EndsWith(".$($script:DF_TARGET_ENV)")) {
            $display_cat = $display_cat.Substring(0, $display_cat.Length - ".$($script:DF_TARGET_ENV)".Length)
        } elseif ($display_cat.EndsWith(".$($script:DF_TARGET_OS)")) {
            $display_cat = $display_cat.Substring(0, $display_cat.Length - ".$($script:DF_TARGET_OS)".Length)
        } elseif (-not [string]::IsNullOrEmpty($script:DF_TARGET_RUNTIME) -and $display_cat.EndsWith(".$($script:DF_TARGET_RUNTIME)")) {
            $display_cat = $display_cat.Substring(0, $display_cat.Length - ".$($script:DF_TARGET_RUNTIME)".Length)
        }
        $script:DF_CATEGORY_MAP[$display_cat] = $raw_cat
    }

    $script:DF_AVAILABLE_MODULES = $active_modules.ToArray()
    $script:DF_ALL_MODULES       = $all_modules.ToArray()
    log_debug "Resolved $($script:DF_AVAILABLE_MODULES.Count) available modules ($($script:DF_ALL_MODULES.Count) total)."
    _exit
}

function check_exists {
    param([string[]]$paths)
    $missing = [System.Collections.Generic.List[string]]::new()
    foreach ($p in $paths) {
        $full = [System.IO.Path]::Combine($PSScriptRoot, $p)
        if (-not [System.IO.File]::Exists($full) -and -not [System.IO.Directory]::Exists($full)) {
            [void]$missing.Add($p)
        }
    }
    if ($missing.Count -gt 0) {
        [Console]::Error.WriteLine("Missing $($missing.Count) path(s):")
        foreach ($m in $missing) {
            [Console]::Error.WriteLine("✗ $m")
        }
        return $false
    }
    return $true
}

function timer_start {
    $script:_TIMER_SW = [System.Diagnostics.Stopwatch]::StartNew()
}

function timer_elapsed {
    if ($null -ne $script:_TIMER_SW) {
        return ("{0:F2}s" -f $script:_TIMER_SW.Elapsed.TotalSeconds)
    }
    return "0.00s"
}

function is_true {
    param([string]$val = "")
    return ($val.ToLowerInvariant() -in @("1", "true"))
}

function acquire_lock {
    _enter
    $nativeLockFile = _native_path $script:DOTFILES_LOCK_FILE
    $lockDir = [System.IO.Path]::GetDirectoryName($nativeLockFile)
    if (-not [System.IO.Directory]::Exists($lockDir)) {
        try {
            [void][System.IO.Directory]::CreateDirectory($lockDir)
        } catch {
            log_error "Cannot create cache directory '${lockDir}' for lock."
            _exit 1
            exit 1
        }
    }

    $now_epoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

    if ([System.IO.File]::Exists($nativeLockFile)) {
        $lock_pid = ""
        $lock_start = ""
        $lock_stamp = ""
        $lock_script = ""
        try {
            $lines = [System.IO.File]::ReadAllLines($nativeLockFile)
            foreach ($l in $lines) {
                $kv = $l.TrimEnd("`r") -split '=', 2
                if ($kv.Count -eq 2) {
                    switch ($kv[0]) {
                        "pid"        { $lock_pid = $kv[1] }
                        "start_time" { $lock_start = $kv[1] }
                        "stamp"      { $lock_stamp = $kv[1] }
                        "script"     { $lock_script = $kv[1] }
                    }
                }
            }
        } catch {}

        $is_stale = $false
        if ($lock_pid -notmatch '^[0-9]+$') {
            $is_stale = $true
        } else {
            $proc = Get-Process -Id ([int]$lock_pid) -ErrorAction SilentlyContinue
            if ($null -eq $proc) {
                $is_stale = $true
            } elseif ($lock_start -match '^[0-9]+$' -and (($now_epoch - [long]$lock_start) -gt $script:DOTFILES_LOCK_TIMEOUT)) {
                $is_stale = $true
            }
        }

        if ($is_stale) {
            log_warn "Removing stale lock '$($script:DOTFILES_LOCK_FILE)' (pid=${lock_pid}, script=${lock_script}, started=${lock_stamp})."
            try { [System.IO.File]::Delete($nativeLockFile) } catch {}
        } else {
            log_error "Another dotfiles instance is currently running (pid=${lock_pid}, script=${lock_script}, started=${lock_stamp})."
            [Console]::Error.WriteLine("Error: Another dotfiles instance (pid=${lock_pid}, script=${lock_script}) holds lock $($script:DOTFILES_LOCK_FILE).")
            _exit 1
            exit 1
        }
    }

    try {
        $content = "pid=${PID}`nstart_time=${now_epoch}`nstamp=$($script:DOTFILES_START_TIME)`nscript=dotfiles.ps1`n"
        $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($content)
        $fs = [System.IO.File]::Open($nativeLockFile, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        $fs.Write($bytes, 0, $bytes.Length)
        $fs.Close()
    } catch {
        log_error "Failed to acquire lock '$($script:DOTFILES_LOCK_FILE)' (race detected)."
        [Console]::Error.WriteLine("Error: Could not acquire concurrency lock $($script:DOTFILES_LOCK_FILE).")
        _exit 1
        exit 1
    }

    log_debug "Acquired concurrency lock '$($script:DOTFILES_LOCK_FILE)' (pid=${PID})."
    _exit
}

function release_lock {
    $nativeLockFile = if (Get-Command _native_path -ErrorAction SilentlyContinue) { _native_path $script:DOTFILES_LOCK_FILE } else { $script:DOTFILES_LOCK_FILE }
    if (-not [string]::IsNullOrEmpty($nativeLockFile) -and [System.IO.File]::Exists($nativeLockFile)) {
        try {
            $lines = [System.IO.File]::ReadAllLines($nativeLockFile)
            $lock_pid = ""
            foreach ($l in $lines) {
                if ($l.StartsWith("pid=")) {
                    $lock_pid = $l.Substring(4).Trim()
                    break
                }
            }
            if ($lock_pid -eq [string]$PID) {
                [System.IO.File]::Delete($nativeLockFile)
            }
        } catch {}
    }
}

function initialise {
    $loggingPath = [System.IO.Path]::Combine($PSScriptRoot, "source/logging.ps1")
    if (-not [System.IO.File]::Exists($loggingPath)) {
        [Console]::Error.WriteLine("Error: missing source/logging.ps1")
        exit 1
    }
    . $loggingPath

    if (-not (_set_src_path)) {
        [Console]::Error.WriteLine("Error: Failed to determine script source path.")
        exit 1
    }

    if (-not (check_exists $script:SOURCE_FILES)) {
        [Console]::Error.WriteLine("One or more required source files are missing.")
        exit 1
    }

    foreach ($sf in $script:SOURCE_FILES) {
        $fullSf = [System.IO.Path]::Combine($PSScriptRoot, $sf)
        . $fullSf
    }

    if (-not (init_logger "--log" $script:INIT_LOG_FILE "--level" "TRACE" "--quiet" "--no-init-message" "--format" "[%l] %d %z [%s] %m")) {
        die 1 'failed to initialise logger.\nCheck that log directory exists and is writable.'
    }

    log_trace "Entering initialisation sequence..."

    if (-not (pwsh_version_check)) {
        die 1 'PowerShell version validation failed.'
    }

    _set_date_cmd
    if (-not (_set_module_dir)) {
        die 1 "Failed to establish module directory."
    }

    if (-not (_set_target_env)) {
        log_warn "Target environment detection failed. Prompting user to proceed."
        [Console]::Error.WriteLine('Warning: unable to determine $DF_TARGET_OS or $DF_TARGET_RUNTIME.')
        [void](prompt_continue 'Some functionality may be limited.')
    }

    _set_is_elevated
    if ($script:DF_TARGET_OS -eq $script:OS_WINDOWS) {
        _set_windows_sudo
    }

    _set_dotfiles_manifest
    _populate_arrays

    log_trace "Initialisation complete."
}

function main {
    param([string[]]$cli_args)
    timer_start
    . initialise
    argparse $cli_args

    acquire_lock
    try {
        $log_cmd = [System.Collections.Generic.List[string]]::new()
        [void]$log_cmd.Add("--level")
        [void]$log_cmd.Add($script:DF_LOG_LEVEL)
        [void]$log_cmd.Add("--format")
        [void]$log_cmd.Add("[%l] %d %z [%s] %m")

        if (is_true ([string]$script:DOTFILES_LOG)) {
            [void]$log_cmd.Add("--log")
            [void]$log_cmd.Add("$($script:DOTFILES_LOG_DIR)/main.log")
        }
        if ($script:DF_NO_LOG -eq 1) {
            [void]$log_cmd.Add("--quiet")
        }
        switch ($script:DOTFILES_ENV) {
            "development" {
                [void]$log_cmd.Add("--verbose")
                [void]$log_cmd.Add("--colour")
            }
            "testing" {
                [void]$log_cmd.Add("--no-colour")
            }
        }

        $log_cmd_arr = $log_cmd.ToArray()
        if (-not (init_logger @log_cmd_arr)) {
            die 1 'failed to initialise logger.\nCheck that log directory exists and is writable.'
        }

        print_banner

        $ec = 0
        switch ($script:DF_MAIN_ACTION) {
            "install" {
                if ((do_install) -ne 0) { $ec = 1 }
            }
            "remove" {
                $rc = do_remove
                if ($rc -eq 130) { exit 130 }
                if ($rc -ne 0) {
                    [Console]::Error.WriteLine("Error: remove finished with $($script:DF_REMOVE_ERRORS) failure(s).")
                    $ec = 1
                }
            }
            "uninstall" {
                $rc = do_uninstall
                if ($rc -eq 130) { exit 130 }
                if ($rc -ne 0) {
                    [Console]::Error.WriteLine("Error: uninstall finished with $($script:DF_UNINSTALL_ERRORS) failure(s).")
                    [Console]::Error.WriteLine("")
                    [Console]::Error.WriteLine("  You may need to manually remove:")
                    [Console]::Error.WriteLine("    $($script:DOTFILES_LOG_DIR)")
                    [Console]::Error.WriteLine("    $($script:DOTFILES_CACHE_DIR)")
                    [Console]::Error.WriteLine("    $($script:DF_SRC_PATH)")
                    [Console]::Error.WriteLine("")
                    $ec = 1
                }
            }
            "update" {
                $rcUp = do_update
                if ($rcUp -eq 130) { exit 130 }
                if ($rcUp -ne 0) { $ec = 1 }
                if ((do_install) -ne 0) { $ec = 1 }
            }
            "repair" {
                if ((do_repair) -ne 0) {
                    [Console]::Error.WriteLine("Error: repair finished with $($script:DF_REPAIR_ERRORS) failure(s).")
                    $ec = 1
                }
            }
            "reset" {
                $rc = do_reset
                if ($rc -eq 130) { exit 130 }
                if ($rc -ne 0) {
                    [Console]::Error.WriteLine("Error: reset finished with $($script:DF_RESET_ERRORS) failure(s).")
                    $ec = 1
                }
            }
            "clean" {
                if ($script:DF_DRY_RUN -eq 1) {
                    $script:LOG_FILE = ""
                }
                if ($script:DF_CLEAN_LOGS -eq 1) {
                    $rc = do_clean_logs
                    if ($rc -eq 130) { exit 130 }
                    if ($rc -ne 0) {
                        [Console]::Error.WriteLine("Error: clean finished with $($script:DF_CLEAN_ERRORS) failure(s).")
                        $ec = 1
                    }
                }
                if ($script:DF_CLEAN_BACKUPS -eq 1) {
                    $rc = do_clean_backups
                    if ($rc -eq 130) { exit 130 }
                    if ($rc -ne 0) {
                        [Console]::Error.WriteLine("Error: clean-backups finished with $($script:DF_CLEAN_ERRORS) failure(s).")
                        $ec = 1
                    }
                }
            }
        }

        print_end

        $elapsed = timer_elapsed
        if ($script:DF_PRINT_TIME -eq 1) {
            [Console]::Out.WriteLine("")
            [Console]::Out.WriteLine("  ⏱  Total: ${elapsed}")
            [Console]::Out.WriteLine("")
        }
        log_trace "Total execution time: ${elapsed}"

        exit $ec
    } finally {
        release_lock
    }
}

main $args
