# print.ps1

if ($script:__PRINT_PS1_INCLUDED__) {
    return
}
$script:__PRINT_PS1_INCLUDED__ = $true

function print_help {
    _enter
    $helpText = @"
OVERVIEW: Installs and synchronizes dotfiles and shell configuration.

USAGE: pwsh -NoProfile -File dotfiles.ps1 <action> [options]

ALL ACTIONS:

INSTALL
      --install              Install (or reinstall) available dotfiles.
  -u, --update               Update from Git before installing.
  -r, --remove <module...>   Remove target modules <module>, semicolon-separated.
  -R, --repair               Remove orphaned symlinks and generated files, then re-link/generate.
      --reset                Remove all symlinks and generated files managed by this tool.
                             (note: copied/merged files will remain)
      --uninstall            Deletes symlinks, logs, and backups, then deletes install directory.

MAINTENANCE
      --clean [N]            Clean backups and reset both log files.
      --clean-logs           Reset both log files.
      --clean-backups [N]    Clean backups.
                             N: remove backup dirs older than N days.
                             (default when omitted: keep the latest
                              DOTFILES_MAX_BACKUPS dirs)

INFORMATION
  -l, --list                 Display all available modules.
      --version              Show the version and git information of this program.
  -h, --help                 Show this help message.

ALL OPTIONS:

INSTALL MODULES
  -i, --include <module...>  Install ONLY the specified modules <module>, semicolon-separated.
  -x, --exclude <module...>  Install all modules EXCEPT specified <module>, semicolon-separated.

BEHAVIOUR
  -n, --dry-run              Print planned actions without modifying the disk.
  -K, --autorestart          Automatically restart shell at script end.
  -G, --no-regenerate        Do not regenerate relevant files if they already exist.
      --no-backup            Do not backup pre-existing copied files.
  -I, --interactive          Prompt for confirmation before every action/modification.
      --noconfirm            Do not prompt for any confirmation.
  -y, --yes                  Auto-accept yes to prompts. Alias to --noconfirm.
  -f, --force                Overwrite existing files/links without backup.

LOGGING
  -d, --debug                Print debug output (useful for diagnosing).
  -q, --quiet                Suppress all standard output except errors.
      --log-level <level>    Set log verbosity <level>. Valid options are: trace, debug, info,
                             notice, warn, or error. (default: info)
      --no-log               Disable logging to stdout (still writes to file).
      --time                 Print total execution time at script finish.

ENVIRONMENT VARIABLES
  Global (Always Active):
    DOTFILES_LOG_DIR         Path to store log files. (default: ~/.config/dotfiles/logs)
    DOTFILES_CACHE_DIR       Path to store temporary cache. (default: ~/.cache/dotfiles)
    DOTFILES_LOG             Set to 0 or false to disable log file writing. (default: 1)
    DOTFILES_LOCAL_MODS      Set to 1 or true to install with uncommitted local changes.
                             (default: 0)
    DOTFILES_AUTORESTART     Set to 1 or true to restart shell at script finish. (default: 0)
    DOTFILES_MAX_BACKUPS     Maximum number of backups to keep. Set to 0 to keep all (default: 10)
Windows Specific:
    DOTFILES_IGNORE_HANDOFF  Set to 1 or true to ignore the Windows Powershell notice. (default 0)
"@
    [Console]::Out.WriteLine($helpText.Replace("`r`n", "`n"))
    _exit
}

function git_or_unknown {
    _enter
    $default = [string]$args[0]
    $gitArgs = if ($args.Count -gt 1) { $args[1..($args.Count - 1)] } else { @() }
    $nativeSrc = _native_path $script:DF_SRC_PATH
    try {
        $out = & git -C $nativeSrc @gitArgs 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace(($out -join "`n"))) {
            _exit
            return ($out -join "`n").Trim()
        }
    } catch {}
    _exit
    return $default
}

function print_version {
    _enter
    $lastChecked = [DateTime]::Now.ToString("yyyy-MM-dd HH:mm:ss zzz")
    $installDir  = git_or_unknown "<unknown>" "rev-parse" "--show-toplevel"
    $branch      = git_or_unknown "<unknown>" "rev-parse" "--abbrev-ref" "HEAD"
    $remote      = git_or_unknown "<unknown>" "config" "--get" "remote.origin.url"
    $version     = git_or_unknown "<unknown>" "describe" "--tags" "--always"
    $commitHash  = git_or_unknown "<unknown>" "rev-parse" "HEAD"
    $shortHash   = if ($commitHash.Length -gt 12 -and $commitHash -ne "<unknown>") { $commitHash.Substring(0, 12) } else { $commitHash }
    $commitMsg   = git_or_unknown "<unknown>" "log" "-1" "--pretty=%B"

    $verText = @"
dotfiles $version built from branch $branch at commit $shortHash ($commitMsg)
Date: $lastChecked
Repository: $installDir
Remote: $remote
"@
    [Console]::Out.WriteLine($verText.Replace("`r`n", "`n"))
    [Console]::Out.WriteLine("")
    _exit
}

function _test_is_symlink {
    param([string]$nativePath)
    try {
        $item = Get-Item -LiteralPath $nativePath -Force -ErrorAction Stop
        return [bool]($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)
    } catch {
        return $false
    }
}

function _test_symlink_target_exists {
    param([string]$nativePath)
    try {
        $item = Get-Item -LiteralPath $nativePath -Force -ErrorAction Stop
        $target = if ($item.LinkTarget) { $item.LinkTarget } elseif ($item.Target) { [string]($item.Target | Select-Object -First 1) } else { "" }
        if ([string]::IsNullOrEmpty($target)) {
            return (Test-Path -LiteralPath $nativePath)
        }
        if (-not [System.IO.Path]::IsPathRooted($target)) {
            $parent = [System.IO.Path]::GetDirectoryName($nativePath)
            $target = [System.IO.Path]::Combine($parent, $target)
        }
        return ([System.IO.File]::Exists($target) -or [System.IO.Directory]::Exists($target))
    } catch {
        return $false
    }
}

function list_modules {
    _enter
    $installed_src = @{}
    [void](manifest_read ([ref]$installed_src))

    [Console]::Out.WriteLine("")
    [Console]::Out.WriteLine("AVAILABLE MODULES")
    [Console]::Out.WriteLine("")

    $current_category = ""
    $env_sfx = ".$($script:DF_TARGET_ENV)"
    $os_sfx  = ".$($script:DF_TARGET_OS)"
    $rt_sfx  = ".$($script:DF_TARGET_RUNTIME)"

    $module_list = if ($script:DF_ALL_MODULES -and $script:DF_ALL_MODULES.Count -gt 0) {
        $script:DF_ALL_MODULES
    } else {
        $script:DF_AVAILABLE_MODULES
    }

    foreach ($src in $module_list) {
        $dest   = if ($script:DF_MODULE_DEST.ContainsKey($src))   { $script:DF_MODULE_DEST[$src] }   else { "" }
        $action = if ($script:DF_MODULE_ACTION.ContainsKey($src)) { $script:DF_MODULE_ACTION[$src] } else { "" }
        $filename = $src.Substring($src.LastIndexOf('/') + 1)
        if ($filename.EndsWith(".gen")) {
            $filename = $filename.Substring(0, $filename.Length - 4)
        }
        $raw_cat = $src.Substring(0, $src.IndexOf('/'))
        $category = if ($script:DF_CATEGORY_MAP.ContainsKey($raw_cat)) { $script:DF_CATEGORY_MAP[$raw_cat] } else { $raw_cat }

        if ($category.EndsWith($env_sfx)) {
            $category = $category.Substring(0, $category.Length - $env_sfx.Length)
        } elseif ($category.EndsWith($os_sfx)) {
            $category = $category.Substring(0, $category.Length - $os_sfx.Length)
        } elseif (-not [string]::IsNullOrEmpty($script:DF_TARGET_RUNTIME) -and $category.EndsWith($rt_sfx)) {
            $category = $category.Substring(0, $category.Length - $rt_sfx.Length)
        }

        if ($filename.EndsWith($env_sfx)) {
            $filename = $filename.Substring(0, $filename.Length - $env_sfx.Length)
        } elseif ($filename.EndsWith($os_sfx)) {
            $filename = $filename.Substring(0, $filename.Length - $os_sfx.Length)
        } elseif (-not [string]::IsNullOrEmpty($script:DF_TARGET_RUNTIME) -and $filename.EndsWith($rt_sfx)) {
            $filename = $filename.Substring(0, $filename.Length - $rt_sfx.Length)
        }

        if ($category -ne $current_category) {
            [Console]::Out.WriteLine($category)
            $current_category = $category
        }

        $status = "✗"
        if ($script:DF_UNAVAILABLE_MODULES.ContainsKey($src)) {
            $status = "?"
        } else {
            $canon_dest = _canonical_path $dest
            $native_dest = _native_path $dest
            $is_symlink = _test_is_symlink $native_dest
            $file_exists = [System.IO.File]::Exists($native_dest)
            $file_nonempty = if ($file_exists) { ([System.IO.FileInfo]::new($native_dest)).Length -gt 0 } else { $false }

            if ($installed_src.ContainsKey($canon_dest) -or $installed_src.ContainsKey($dest)) {
                switch ($action) {
                    "symlink" {
                        if ($is_symlink -and (_test_symlink_target_exists $native_dest)) {
                            $status = "✓"
                        } else {
                            $status = "!"
                        }
                    }
                    "copy" {
                        if ($file_exists) {
                            $status = "✓"
                        } else {
                            $status = "!"
                        }
                    }
                    "generate" {
                        if ($file_exists -and $file_nonempty) {
                            $status = "✓"
                        } else {
                            $status = "!"
                        }
                    }
                }
            } else {
                if (-not [string]::IsNullOrEmpty($dest)) {
                    switch ($action) {
                        "symlink" {
                            if ($is_symlink -and (_test_symlink_target_exists $native_dest)) {
                                $status = "✓"
                            } elseif ($is_symlink) {
                                $status = "!"
                            }
                        }
                        "generate" {
                            if ($file_exists -and $file_nonempty) {
                                $status = "✓"
                            } elseif ($file_exists) {
                                $status = "!"
                            }
                        }
                        default {
                            if ($file_exists) {
                                $status = "✓"
                            }
                        }
                    }
                }
            }
        }

        [Console]::Out.WriteLine("  $status $filename")
    }

    [Console]::Out.WriteLine("")
    [Console]::Out.WriteLine("  ✓  installed & healthy")
    [Console]::Out.WriteLine("  ✗  not installed")
    [Console]::Out.WriteLine("  !  installed but broken / stale")
    [Console]::Out.WriteLine("  ?  unavailable on this platform")
    [Console]::Out.WriteLine("")
    _exit
}

function print_banner {
    _enter
    $esc = "`e"
    $lines = @(
        "${esc}[1;96m  ____        _    __ _ _             ${esc}[0m",
        "${esc}[1;96m |  _ \  ___ | |_ / _(_) | ___  ___   ${esc}[0m",
        "${esc}[1;96m | | | |/ _ \| __| |_| | |/ _ \/ __|  ${esc}[0m",
        "${esc}[1;96m | |_| | (_) | |_|  _| | |  __/\__ \  ${esc}[0m",
        "${esc}[1;96m |____/ \___/ \__|_| |_|_|\___||___/  ${esc}[0m",
        "${esc}[1;90m -----------------------------------${esc}[0m",
        "${esc}[1;97m     Automated Environment Setup    ${esc}[0m",
        "${esc}[1;90m -----------------------------------${esc}[0m"
    )
    [Console]::Out.WriteLine(($lines -join "`n"))
    _exit
}

function print_end {
    _enter
    $msgLine = if ($script:DOTFILES_AUTORESTART -eq 1) {
        if (is_windows_bash) {
            "│  Returning to shell...                    │"
        } else {
            "│  Restarting shell...                      │"
            . $PROFILE
        }
    } else {
        "│  Run `. `$PROFILE` to apply your changes.    │"
    }
    $box = @(
        "",
        "╭───────────────────────────────────────────╮",
        "│                                           │",
        "│          INSTALLATION COMPLETE!           │",
        "│                                           │",
        $msgLine,
        "│                                           │",
        "╰───────────────────────────────────────────╯",
        ""
    )
    [Console]::Out.WriteLine(($box -join "`n"))
    _exit
}
