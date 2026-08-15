# Port Zsh Dotfiles to PowerShell — Plan

## Goal
Convert the entire zsh dotfile setup into a clean PowerShell profile under `oh-my-posh/scripts/` (and supporting files), fully replacing the current monolithic-style profile with a modular architecture.

---

## Current State (as of last update)

### Zsh baseline (unchanged — 840 lines total)
| File | Lines | Purpose |
|---|---|---|
| `zsh/.zshrc` | 473 | Main config: history, logging/sourcing chain, plugins (zimfw), p10k, fastfetch, fzf, zoxide, rbenv |
| `zsh/.aliases` | 58 | Nav (`..`, `...`), ls/eza variants, code (`codium-insiders`), grep, sudo pass-through, mac branch |
| `zsh/.functions` | 54 | `mkcd`, `fs` (file size) |
| `zsh/.git_functions` | 29 | `gac` (add+commit), `gacp` (add+commit+push) |
| `zsh/.zsh_options` | 51 | Key bindings, history sharing/correcting, autocd, glob dots, dir stack size |
| `zsh/.zstyles` | 134 | Completion menu/formatting/colors, vcs_info (git branch in prompt), history substring search |
| `zsh/.zimrc` | 41 | Zimfw module declarations (p10k, vi-mode, fzf-tab, zoxide, github-cli, fzf, git, exa, autosuggestions, syntax-highlighting, etc.) |

### PowerShell current state (modular — ~60 lines main profile + scripts)
| File | Lines | Purpose |
|---|---|---|
| `oh-my-posh/Microsoft.PowerShell_profile.ps1` | 19 | Sourcing entry point + oh-my-posh init |
| `oh-my-posh/scripts/Set-MSVC-Environment.ps1` | 47 | Auto-detect MSVC toolchain + SDK, update PATH/INCLUDE/LIB |
| `oh-my-posh/scripts/AutoCd.ps1` | 54 | CommandNotFound handler (autocd, location history via cd-extras) |
| `oh-my-posh/scripts/Update-Modules.ps1` | 190 | Full module upgrader using PSResourceGet |
| `oh-my-posh/scripts/nproc.ps1` | 1 | Logical processor count |
| `oh-my-posh/scripts/md5.ps1` | 1 | Hash utility (MD5) |
| `oh-my-posh/scripts/sha1.ps1` | 1 | Hash utility — **BUG: defines `sha256` with SHA1 algo** |
| `oh-my-posh/scripts/sha256.ps1` | 1 | Hash utility — **BUG: defines `sha256` with SHA256 algo** (shadowed by sha1.ps1) |

### Pre-existing (not in git, assumed at `$env:USERPROFILE/`)
- `.zshrc.local` — local overrides toggled by `mode.sh`
- `.exports`, `.paths`, `.aliases`, `.functions`, `.git_functions` — sourced from zshrc but not yet ported

---

## Output Directory Structure

```
oh-my-posh/
├── Microsoft.PowerShell_profile.ps1   # Main entry point (thin wrapper)
├── scripts/
│   ├── Set-MSVC-Environment.ps1       # existing — keep
│   ├── AutoCd.ps1                     # existing — keep
│   ├── Update-Modules.ps1             # existing — keep
│   ├── nproc.ps1                      # existing — keep
│   ├── md5.ps1                        # existing — fix name collision
│   ├── sha1.ps1                       # existing — fix function name
│   ├── sha256.ps1                     # existing — keep (after sha1 fix)
│   ├── aliases.ps1                    # NEW — port of zsh/.aliases
│   ├── functions.ps1                  # NEW — port of zsh/.functions + .git_functions
│   ├── psreadline.config.ps1          # NEW — port of zsh/.zstyles
│   └── modules.ps1                    # NEW — module loading (posh-git, etc.)
├── utils/
│   └── Set-ShellMode.ps1              # NEW — port of mode.sh
└── themes/tiger.omp.json              # existing — active theme
```

---

## File-by-File Conversion

### 0. Fix Existing Bugs

**`oh-my-posh/scripts/sha1.ps1`**: function named `sha256` but computes SHA1 → rename to `function sha1 { Get-FileHash -Algorithm SHA1 $args }`
**`oh-my-posh/scripts/md5.ps1`**: same bug — named `md5` but computes MD5 via `Get-FileHash -Algorithm MD5`. The function name is correct, the algorithm call is correct. OK as-is.

### 1. `zsh/.aliases` → `scripts/aliases.ps1` (NEW)

Port each alias to a global advanced function:

```powershell
function global:c { Clear-Host }
function global:path { $env:PATH -split ';' }
# History with formatted timestamps
function global:history { Get-History | Format-Table Id, StartTime, EndTime, CommandLine }

# bat fallback chain (not directly applicable in PS — skip or alias to system)
# zsh checks for bat/batcat → keep as-is if using external coreutils

# Navigation
function global:..  { Set-Location .. }
function global:... { Set-Location ../.. }
function global:....{ Set-Location ../../.. }
function global:.....{ Set-Location ../../../.. }
function global:-   { Set-Location - <@args> }

# ls/eza variants (same flags as zsh)
function global:ls  { eza --icons --group-directories-first @args }
function global:ll  { eza -l --icons --no-user --group-directories-first --time-style long-iso @args }
function global:la  { eza -la --icons --no-user --group-directories-first --time-style long-iso @args }
function global:ld  { eza -ld --icons --time-style long-iso @args }

# Code
function global:code   { codium-insiders @args }
function global:c.     { codium-insiders . }

# Grep (via coreutils on Windows)
function global:grep  { grep --color=auto @args }
function global:fgrep { fgrep --color=auto @args }
function global:egrep { egrep --color=auto @args }

# sudo pass-through
$null = New-Alias -Name sudo -Value sudo -Force
```

**Mac branch removed** — no Homebrew/brewup/afk on Windows.

### 2. `zsh/.functions` → `scripts/functions.ps1` (NEW)

```powershell
function global:mkcd {
    if (-not $args[0]) { Write-Error 'Usage: mkcd <directory_name>'; return }
    if ($args.Count -gt 1) { Write-Error 'Too many arguments'; return }
    if (Test-Path $args[0] -PathType Container) {
        Set-Location $args[0]
    } else {
        mkdir -Force $args[0] | Out-Null
        Set-Location $args[0]
    }
}

function global:fs {
    # Port du wrapper from zsh (bsd vs gnu du flags)
    if (du -b /dev/null 2>&1 | Select-String .) { $flag = '-sbh' } else { $flag = '-sh' }
    if ($args) { & du $flag @args } else { & du $flag .[^.]* .* }
}

# From zsh/.git_functions — merged here
function global:gac {
    if (-not $args[0]) { Write-Error 'Usage: gac <message>'; return }
    git add .; git commit -m $args[0]
}

function global:gacp {
    if (-not $args[0]) { Write-Error 'Usage: gacp <message>'; return }
    $branch = (git symbolic-ref --short -q HEAD)
    git add -A; git commit -m $args[0]; git push origin $branch
}
```

### 3. `zsh/.zsh_options` → merged into `Microsoft.PowerShell_profile.ps1`

Each zsh option maps to PS:

| Zsh Option | PowerShell Equivalent | Where in profile |
|---|---|---|
| `bindkey -e` | `Set-PSReadlineOption -EditMode Windows` | After modules loaded |
| `setopt CORRECT` | PS doesn't auto-correct; use external tools | Skip / note |
| `EXTENDED_HISTORY`, `INC_APPEND_HISTORY`, `SHARE_HISTORY` | `$env:HISTFILE`; PSReadLine history export on exit | Profile init block |
| `NO_BEEP` | `Set-PSReadlineOption -BellStyle None` | After modules loaded |
| `AUTO_MENU`, `AUTO_LIST` | `Set-PSReadlineOption -MenuType AnimatedMenu; Set-PSReadlineOption -MaximumSuggestions 20` | After modules loaded |
| `AUTO_CD` | Already in `AutoCd.ps1` — keep as-is | (existing) |
| `GLOB_DOTS` | PS matches dotfiles by default with `-Path` | No action needed |
| `DIRSTACKSIZE=20` | Not native in PS; skip unless tracking manually | Skip |
| `ALIASES`, `APPEND_HISTORY` | Built into PS behavior | No action |

### 4. `zsh/.zstyles` → `scripts/psreadline.config.ps1` (NEW)

Port completion styling to PSReadLine options + colors:

```powershell
# Completion menu (replaces zstyle ':completion:*' menu select)
Set-PSReadlineOption -MenuType AnimatedMenu
Set-PSReadlineOption -MaximumSuggestions 20

# Verbose completions with descriptions (replaces zstyle verbose/group-name)
# PSReadLine shows descriptions in the menu automatically when animated menu is on

# Case-insensitive + substring matching — default in PSReadLine
# No equivalent needed for: matcher-list, completer order, add-space, list-always

# Completion colors (port from zsh format strings)
Set-PSReadlineOption -Colors @{
    Command        = [System.ConsoleColor]::Yellow   # %F{yellow}-- --%f  descriptions
    Parameter      = [System.ConsoleColor]::Cyan     # %F{cyan} messages
    Type           = [System.ConsoleColor]::Green
    Member         = [System.ConsoleColor]::Blue
    Variable       = [System.ConsoleColor]::Magenta
    Error          = [System.ConsoleColor]::Red      # %F{red} warnings
    InlineHint     = [System.ConsoleColor]::Gray
    PredictionInputText = [System.ConsoleColor]::DarkGray
    PredictionOutputText   = [System.ConsoleColor]::Gray
}

# Key bindings (menu select via Tab)
Set-PSReadlineKeyHandler -Key Tab -Function MenuComplete

# History substring search (replaces zhistory-substring-search zstyle)
Set-PSReadlineOption -PredictionSource History
Set-PSReadlineOption -PredictionViewStyle ListView
```

**vcs_info completely removed** — oh-my-posh theme's git segment already displays branch, dirty state, ahead/behind. The `tiger.omp.json` theme likely has git status segments configured.

### 5. `zsh/.zimrc` → `scripts/modules.ps1` (NEW)

| Zim Module | PowerShell Replacement | Load Method |
|---|---|---|
| `romkatv/powerlevel10k` | **oh-my-posh** (already in profile) | (no action — theme sourced in main profile) |
| `jeffreytse/zsh-vi-mode` | Skip — vi mode not needed or use oh-my-posh keybindings | (no action) |
| `Aloxaf/fzf-tab` | PSReadLine AnimatedMenu + fzf | posh-fzf module |
| `shanwker1223/zim-alias-finder` | Skip — no equivalent; PS tab finds aliases natively | (no action) |
| `hlissner/zsh-autopair` | PSReadLine built-in autopairs | (no action) |
| `kiesman99/zim-zoxide` | **zoxide** | `` & zoxide init powershell `` (inline in profile) |
| `joke/zim-github-cli` | **gh** CLI on PATH + posh-git for local repo info | no module needed |
| `fzf` | **fzf** + posh-fzf | `Import-Module posh-fzf` |
| `ssh` | Built-in | (no action) |
| `git-info` | **posh-git** | `Import-Module posh-git` |
| `duration-info` | Custom timing wrappers in functions.ps1 | manual |
| `prompt-pwd` | Oh-my-posh handles PWD display | (no action) |
| `exa` | **eza** binary on PATH | no module needed |
| `magic-enter` | Custom function: Enter runs command, Ctrl+Enter for newline | Set-PSReadlineKeyHandler |
| `environment` | Built into PS profiles | (no action) |
| `git` | **posh-git** | `Import-Module posh-git` |
| `input` | PSReadLine built-in | (no action) |
| `termtitle` | Oh-my-posh handles console title | (no action) |
| `utility` | functions.ps1 ported above | (manual) |
| `run-help` | `Get-Help -ShowWindow` | (no action — built-in) |
| `archive` | Compress-Archive / Expand-Archive | (no action — built-in) |
| `zsh-users/zsh-completions` | PSReadLine tab completion + zoxide completions | (no action) |
| `completion` | PSReadLine tab completion | (no action) |
| `zsh-users/zsh-autosuggestions` | PSReadLine prediction source | Set-PSReadlineOption -PredictionSource History |
| `zsh-users/zsh-syntax-highlighting` | PSReadLine built-in syntax highlighting | (no action — always enabled) |

```powershell
# scripts/modules.ps1
if (-not (Get-Module posh-git -ListAvailable)) { Install-Module posh-git -Scope CurrentUser -Force }
Import-Module posh-git

# fzf integration (posh-fzf provides keyboard shortcuts for fuzzy search)
try { Import-Module posh-fzf } catch { Write-Warning 'posh-fzf not installed — install via Install-Module posh-fzf' }
```

### 6. `zsh/.p10k.zsh` → SKIP

Powerlevel10k's interactive configuration file. You've switched to oh-my-posh with `tiger.omp.json` — no equivalent needed. The git branch, status, and prompt styling are all handled by your oh-my-posh theme.

### 7. `zsh/.zshrc` heavy sections → merged into new files

| Zsh Section | Port Target |
|---|---|
| History vars + histfile setup | `Microsoft.PowerShell_profile.ps1` init block |
| Logging system (`print_title`, `log_message`) | Add to `Microsoft.PowerShell_profile.ps1` as helper or skip (PS has `Write-Host`/`Write-Warning`/`Write-Information`) |
| Sourcing chain (.exports, .paths, .aliases) | Replace with direct `.` of ps1 files in main profile |
| LS_COLORS via gdircolors/dircolors | Skip — PSReadLine doesn't use LS_COLORS; colors set via Set-PSReadlineOption -Colors |
| Powerlevel10k cloning/sourcing | **Remove** — oh-my-posh already handles prompt |
| Zimfw bootstrapping (download, install, init) | **Remove** — replaced by modules.ps1 + module installer on demand |
| rbenv initialization | **Skip** — Windows-only; use mise/nvm-windows if version management needed |
| fastfetch invocation (with custom config) | Keep inline in profile — `` fastfetch --config "$HOME/.config/fastfetch/config.jsonc" `` or `` fastfetch `` |
| .zstyles sourcing | Replace with `. scripts/psreadline.config.ps1` |
| fzf `<(fzf --zsh)` | Replace with posh-fzf module import |
| zoxide init | Keep inline: `` & zoxide init powershell `` |
| iTerm2 shell integration | **Skip** — macOS only |
| DEBUG_MODE / ENABLE_PROFILING toggle | Port to `utils/Set-ShellMode.ps1` (like mode.sh) |

### 8. `.exports`, `.paths` → port as needed

These are sourced from zshrc but don't exist in the repo as separate files (they're presumably local/generated). If they contain:
- Environment variables (EDITOR, LANG, GPG_TTY, model configs) → set directly in profile init block
- PATH modifications (`$HOME/.local/bin`) → `$env:PATH = "$HOME\.local\bin;$env:PATH"` in profile

### 9. `mode.sh` → `utils/Set-ShellMode.ps1` (NEW)

Port the debug/profiling toggle script to PowerShell, toggling flags stored in `$PROFILE + ".flags"` or similar.

---

## Implementation Order

1. **Fix existing bugs** — `sha1.ps1` function name collision
2. **`scripts/aliases.ps1`** — simple, no dependencies
3. **`scripts/functions.ps1`** — merges `.functions` + `.git_functions`
4. **`scripts/modules.ps1`** — module loading (posh-git, posh-fzf)
5. **`scripts/psreadline.config.ps1`** — port of .zstyles
6. **`utils/Set-ShellMode.ps1`** — port of mode.sh
7. **`Microsoft.PowerShell_profile.ps1`** — main orchestrator: thin wrapper that sources scripts in order, adds missing config (history vars, fastfetch, zoxide, psreadline options)

---

## Dependencies to Install

| Tool | Source | Replaces |
|---|---|---|
| `eza` | GitHub / winget / scoop | exa, eza completion |
| `fzf` | GitHub / winget / scoop | fzf + zsh-vi-mode completions |
| `posh-git` | PSGallery | zim-git, git-info |
| `posh-fzf` | PSGallery | fzf integration + alias-finder |
| `cd-extras` | PSGallery (v2.9.4) | AutoCd.ps1 depends on `Set-LocationEx`, `Undo-Location`, `Redo-Location` |
| `zoxide` | GitHub / winget / scoop | zim-zoxide |

---

## Known Non-Translatable Features

| Zsh Feature | Status in PowerShell | Notes |
|---|---|---|
| vcs_info (git branch formatting) | **Replaced** | oh-my-posh theme `tiger.omp.json` handles it via git segment |
| `.zstyles` completion color formats (%F{} etc.) | **Partially replaced** | PSReadLine uses `[System.ConsoleColor]` enum; full zsh format string support not available |
| Zimfw multi-version plugin manager | **Not needed** | Use Install-Module or manual git clone + Import-Module |
| `.zimrc` / `init.zsh` auto-update | **Skipped** | Modules loaded directly from PSGallery |
| iTerm2 shell integration | **Skip** | macOS only |
| rbenv | **Skip** | Windows: use mise, nvm-windows, or asdf |
| GPG_TTY on macOS (Homebrew workaround) | **Adapted** | Keep the tty detection but remove macOS Homebrew workaround |
| HISTFILE zsh format (`:start:elapsed;command`) | **Different** | PSReadLine history has different format; export via `$PROFILE` on-exit handler if cross-shell compatibility needed |
| `setopt HIST_IGNORE_SPACE`, `HIST_FIND_NO_DUPS`, etc. | **Partial** | PSReadLine has `Add-ToHistory -AsConstant` for ignoring certain commands |

---

## Open Questions

1. **`.exports` and `.paths` files** — these are referenced by zshrc as `$HOME/.exports` and `$HOME/.paths`. Do they exist locally on your machine, or should I create template versions in the repo?
2. **cd-extras dependency** — `AutoCd.ps1` references `Set-LocationEx`, `Undo-Location`, `Redo-Location` from cd-extras/LocationHistory. Is this installed and working currently, or is it a TODO you haven't set up yet?
3. **`.zshrc.local`** — the zshrc source chain includes `$HOME/.zshrc.local` (toggled by mode.sh). Should I create a PowerShell equivalent (`$PROFILE + ".local"`) for machine-specific overrides?
