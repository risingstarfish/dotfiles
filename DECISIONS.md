# Architectural & Cross-Script Decisions (`DECISIONS.md`)

> **Policy:** This document is **append-only**. Prior entries must never be edited or deleted. Superseding a decision requires appending a new entry that cites and supersedes the prior entry with rationale. Every error encountered during development and verification is appended to the Error Log section at the end of this document.

---

## Phase 0 Decisions (D1 – D8)

### D1 — Line Ending & Character Encoding Policy

- **Decision:**
  1. **Canonical Writer Format:** Both `dotfiles.sh` and `dotfiles.ps1` write `manifest.tsv` (`${DOTFILES_CACHE_DIR}/manifest.tsv`) and both log files (`${DOTFILES_LOG_DIR}/initialise.log`, `${DOTFILES_LOG_DIR}/main.log`) as **UTF-8 without BOM** (`[System.Text.UTF8Encoding]::new($false)` in PowerShell) with **LF (`\n`)** line endings.
  2. **Canonical Reader Tolerance:** All manifest reading and in-place mutation helpers in both scripts strip a trailing CR (`\r`) from every line/field on read (`sub(/\r$/, "")` in awk and `${var%$'\r'}` in bash; `.TrimEnd("`r")` in PowerShell), ignore blank lines, and ignore/preserve `#` header lines (`^#`).
  3. **Single Layer Enforcement:** CR-stripping and header preservation exist exclusively inside the manifest I/O layer (`src/action.sh` and `src/action.ps1`), never at individual action call sites.
- **Rationale:**
  PowerShell's `Set-Content` / `Out-File` emit CRLF and (in Windows PowerShell 5.1) UTF-16LE or UTF-8 with BOM by default, which breaks byte parity and can corrupt awk field matching when `$3` (`ftype`) retains a trailing `\r`. Writing UTF-8 no-BOM with `\n` via `[System.IO.File]` APIs in PowerShell makes `manifest.tsv` byte-identical across bash and PowerShell while reader CR-stripping guarantees resilience if a manifest is ever edited by a Windows tool or older Git Bash configuration.
- **Implementing Files:**
  - `src/action.sh` (`manifest_write`, `manifest_remove`, `manifest_remove_prefix`, `manifest_clear`, `manifest_read`, `_read_manifest_entries`, `do_update`)
  - `src/action.ps1` (`manifest_write`, `manifest_remove`, `manifest_remove_prefix`, `manifest_clear`, `manifest_read`, `_read_manifest_entries`, `do_update`)
  - `src/logging.sh` (`_log_message`, `init_logger`)
  - `src/logging.ps1` (`_log_message`, `init_logger`)
- **Existing Behaviour Preserved / Changed:**
  - Preserves `src/action.sh:317` (`printf '%s\t%s\t%s\n'`) LF emission and `src/action.sh:370-371` / `src/action.sh:1007-1009` trailing `\r` stripping.
  - Hardens `src/action.sh:307,313,330,343` (`manifest_write`, `manifest_remove`, `manifest_remove_prefix`) by stripping `\r` (`sub(/\r$/, "")`) inside the awk programs and hardening `src/action.sh:373,1011` to skip `#` header lines via `[[ ${src} == \#* || ${dest} == \#* ]]` even if a comment contains a tab character.

---

### D2 — Canonical Path Form in the Manifest on Windows & Cross-Script Comparisons

- **Decision:**
  1. **Stored Manifest Path Form:** `manifest.tsv` stores paths in canonical forward-slash POSIX/MSYS form via `_canonical_path` (bash) / `ConvertTo-CanonicalPath` (PowerShell):
     - Backslashes (`\`) are replaced with forward slashes (`/`).
     - Windows drive roots `X:/...` or `X:\...` are normalized to lowercase MSYS form `/<x>/...` (e.g., `C:\Users\tiger\.zshrc` -> `/c/Users/tiger/.zshrc`).
     - Trailing slashes (except root `/`) and redundant `//` are collapsed.
  2. **Native Filesystem Translation in PowerShell:** `src/utility.ps1` provides `_native_path` (`ConvertTo-NativePath`) which converts `/<drive>/...` back to `<Drive>:\...` when `$IsWindows` is true (and leaves `/...` unchanged on Linux/macOS) before invoking native .NET/PowerShell filesystem operations.
  3. **Comparison Parity (`_guard_dest`, `do_repair`, `manifest_remove_prefix`):**
     - In `_guard_dest` (`src/action.sh:181-190`, `src/action.ps1`), both the symlink target (`readlink` / `LinkTarget` / `Target`) and `src` are converted via `_canonical_path` before checking prefix match (`[[ ${canon_target} == "${canon_src}"* ]]` / `$canonTarget.StartsWith($canonSrc)`). If `readlink` returns a relative path, it is resolved relative to `$(dirname "${dest}")` before canonicalization.
     - In `do_repair` (`src/action.sh:1131`, `src/action.ps1`), symlink health compares `_canonical_path(target) == _canonical_path(src)`.
     - In `manifest_remove_prefix` (`src/action.sh:338-345`, `src/action.ps1`), both `$1` (stored `src`) and `prefix` are compared in canonical form (`index(canon($1), canon(prefix)) == 1`).
- **Rationale:**
  Git Bash (`dotfiles.sh`) natively expands `$HOME` and `$DF_SRC_PATH` as `/c/Users/<user>/...`, whereas PowerShell sees `C:\Users\<user>\...`. Normalizing to `/<drive>/...` with forward slashes in `_canonical_path` makes `manifest.tsv` entries byte-identical whether written by `dotfiles.sh` or `dotfiles.ps1`, and ensures `--list`, `--repair`, `--remove`, and `_guard_dest` work seamlessly across both scripts without duplicate rows.
- **Implementing Files:**
  - `src/utility.sh` (`_canonical_path`)
  - `src/utility.ps1` (`_canonical_path`, `_native_path`)
  - `src/action.sh` (`_guard_dest`, `manifest_write`, `manifest_remove`, `manifest_remove_prefix`, `manifest_read`, `_read_manifest_entries`, `do_repair`)
  - `src/action.ps1` (`_guard_dest`, `manifest_write`, `manifest_remove`, `manifest_remove_prefix`, `manifest_read`, `_read_manifest_entries`, `do_repair`)
  - `src/print.sh` (`list_modules`)
  - `src/print.ps1` (`list_modules`)
- **Existing Behaviour Preserved / Changed:**
  - Preserves POSIX `/home/...` and `/Users/...` paths unchanged (`dotfiles.sh:374-428`).
  - Extends `src/action.sh:184` (`_guard_dest`), `src/action.sh:293-378` (`manifest_*`), and `src/action.sh:1131` (`do_repair`) so Windows drive paths (`C:\...` or `C:/...`) and MSYS paths (`/c/...`) normalize to the same string.

---

### D3 — Home Directory Resolution Parity

- **Decision:**
  1. **Resolution Order in both scripts:**
     - `dotfiles.sh` uses `$HOME` (`dotfiles.sh:5-8`), failing with `Error: unable to resolve $HOME` and exit code `1` if unset or not an existing directory.
     - `dotfiles.ps1` resolves the physical home directory using the priority order:
       1. `$env:HOME` (if non-empty and directory exists)
       2. `$env:USERPROFILE` (if non-empty and directory exists)
       3. PowerShell automatic `$HOME` (if non-empty and directory exists)
       4. If none resolve to an existing directory, print `Error: unable to resolve $HOME` to stderr and `exit 1`.
     - Once resolved, `dotfiles.ps1` sets `$env:HOME` (and `$env:USERPROFILE` if unset) to the native directory path and sets `$script:HOME_CANONICAL = _canonical_path $env:HOME` for constructing `DF_MANIFEST` destinations and default `DOTFILES_LOG_DIR` / `DOTFILES_CACHE_DIR`.
- **Rationale:**
  On native Windows launched with `pwsh -NoProfile`, `$env:HOME` is often unset while `$env:USERPROFILE` is `C:\Users\<user>`. In automated tests and on Linux/macOS, callers override `HOME` via `$env:HOME`. Preferring `$env:HOME` when valid and falling back to `$env:USERPROFILE` ensures both throwaway test `HOME` overrides and native Windows `USERPROFILE` environments resolve to the exact same physical directory as `dotfiles.sh`.
- **Implementing Files:**
  - `dotfiles.sh` (`lines 5-20`)
  - `dotfiles.ps1` (bootstrap home resolution and `DF_*` path initialization)
  - `modules/pwsh.windows/Profile` (`$env:HOME` / `$env:USERPROFILE` synchronization)
- **Existing Behaviour Preserved / Changed:**
  - Preserves `dotfiles.sh:5-8` error message and exit code `1`.
  - Synchronizes `$env:HOME` and `$env:USERPROFILE` in `dotfiles.ps1` and `modules/pwsh.windows/Profile:13-15`.

---

### D4 — OS-Variant Resolution & Visibility Policy

- **Decision:**
  Both `_populate_arrays` in `dotfiles.sh` and `_populate_arrays` in `dotfiles.ps1` implement the exact same 4-step resolution rule for every row `action|src|dest|post_cmd` in `DF_MANIFEST`:
  1. **Explicit OS Exclusion Check:** If `src == "topgrade/topgrade.toml"` and `DF_TARGET_OS == "windows"` (`dotfiles.sh:461`), mark the row as unavailable (`DF_UNAVAILABLE_MODULES["${src}"]=1`), emit `log_warn "Skipping module '${src}': not supported on OS '${DF_TARGET_OS}'"`, and record metadata for `--list` display without adding to `DF_AVAILABLE_MODULES`.
  2. **Exact Match:** If `${DF_MODULE_DIR}/${src}` exists on disk, select `src` as resolved.
  3. **Variant Fallback Chain (when exact `${DF_MODULE_DIR}/${src}` does not exist):**
     - **3a. Runtime Suffix Fallback:** If `src` ends with `.${DF_TARGET_OS}` and `DF_TARGET_RUNTIME` is non-empty (e.g. `wsl`), test `${src%.${DF_TARGET_OS}}.${DF_TARGET_RUNTIME}` (resolves `git/gitconfig.local.${DF_TARGET_OS}` -> `git/gitconfig.local.wsl` on WSL).
     - **3b. Base File/Dir Fallback:** Strip `.${DF_TARGET_ENV}` or `.${DF_TARGET_OS}` from `src` (file suffix `foo.bar.<os>` -> `foo.bar`, or directory suffix `cat.<os>/file` -> `cat/file`). If `${DF_MODULE_DIR}/${base_src}` exists on disk (e.g. `fastfetch/config.jsonc.${DF_TARGET_OS}` -> `fastfetch/config.jsonc`), resolve to `base_src` and emit `log_debug "Module '${src}' resolved via base fallback to '${base_src}'"`.
  4. **Visible Skip on Missing Source:** If none of steps 2, 3a, or 3b exist on disk:
     - Emit `log_warn "Skipping unavailable module '${src}': source does not exist at '${DF_MODULE_DIR}/${src}'"`.
     - Record `src` in `DF_ALL_MODULES`, `DF_UNAVAILABLE_MODULES["${src}"]=1`, `DF_MODULE_ACTION`, `DF_MODULE_DEST`, and `DF_CATEGORY_MAP` (so `--list` renders it under its category with status `?` and legend `  ?  unavailable on this OS / missing source`), while excluding it from `DF_AVAILABLE_MODULES` (so `--install` / `--update` do not fail attempting to install non-existent files).
- **Rationale:**
  Fixes T1 and T3 at the population layer (`_populate_arrays`) rather than patching `list_modules`. Base files that exist (`fastfetch/config.jsonc`) and WSL runtime variants (`git/gitconfig.local.wsl`) are automatically utilized, while genuinely missing platform variants (`tmux` on non-macOS, `git/gitconfig.local.debian` on native Debian, `pwsh` and `oh-my-posh` on non-Windows) produce a `log_warn` in logs and appear visibly with `?` in `--list`.
- **Implementing Files:**
  - `dotfiles.sh` (`_populate_arrays`, global arrays `DF_ALL_MODULES`, `DF_UNAVAILABLE_MODULES`)
  - `src/print.sh` (`list_modules`)
  - `dotfiles.ps1` (`_populate_arrays`, global state arrays/hashtables)
  - `src/print.ps1` (`list_modules`)
- **Existing Behaviour Preserved / Changed:**
  - Replaces silent `log_trace` + `continue` at `dotfiles.sh:455-464` with fallback resolution (`3a`/`3b`), `log_warn` on skip, and `DF_ALL_MODULES` / `DF_UNAVAILABLE_MODULES` registration.
  - Updates `src/print.sh:135-215` (`list_modules`) to iterate `DF_ALL_MODULES`, render `?` when `DF_UNAVAILABLE_MODULES["${src}"]` is set, and print the `?` legend line.

---

### D5 — Concurrency Lock

- **Decision:**
  1. **Lock File Location:** `${DOTFILES_CACHE_DIR}/dotfiles.lock` (`DOTFILES_LOCK_FILE`).
  2. **Lock File Format:** UTF-8, LF-delimited `key=value` lines:
     ```
     pid=<PID>
     start_time=<EPOCH_SECONDS>
     stamp=<DOTFILES_START_TIME>
     script=<dotfiles.sh|dotfiles.ps1>
     ```
  3. **Stale-Lock Threshold & Recovery:**
     - Threshold: `DOTFILES_LOCK_TIMEOUT` (default `3600` seconds).
     - When `DOTFILES_LOCK_FILE` already exists, the acquiring script reads `pid`, `start_time`, `stamp`, and `script`.
     - A lock is considered **stale** if:
       - `pid` is missing/non-numeric, OR
       - No live process with `pid` exists (`! kill -0 "$pid" 2>/dev/null` in bash; `-not (Get-Process -Id $pid -ErrorAction SilentlyContinue)` in PowerShell), OR
       - `(current_epoch - start_time) > DOTFILES_LOCK_TIMEOUT`.
     - If stale: emit `log_warn "Removing stale lock '${DOTFILES_LOCK_FILE}' (pid=${lock_pid}, script=${lock_script})"` and remove the file before retrying atomic creation.
     - If live-held: emit `log_error "Another instance (${lock_script}, pid=${lock_pid}) holds lock '${DOTFILES_LOCK_FILE}'."`, print error to stderr, and exit `1`.
  4. **Lifecycle (Acquire / Release):**
     - Acquired in `main` immediately after `argparse` (so `--help`, `--version`, `--list` which exit inside `argparse` do not leave or block on locks, or `--list` reads cleanly) and before any action runs.
     - Released in bash via `trap 'release_lock' EXIT INT TERM` and in PowerShell via `try { ... } finally { release_lock }`, checking that the lock file's `pid` matches the current process (`$$` / `$PID`) before deletion.
- **Rationale:**
  Prevents race conditions when `dotfiles.sh` and `dotfiles.ps1` (or two instances of either) run simultaneously against the same `manifest.tsv`, backup directories, and target dotfiles.
- **Implementing Files:**
  - `dotfiles.sh` (`DOTFILES_LOCK_FILE`, `acquire_lock`, `release_lock`, `main`)
  - `dotfiles.ps1` (`DOTFILES_LOCK_FILE`, `acquire_lock`, `release_lock`, `main`)
- **Existing Behaviour Preserved / Changed:**
  - Adds concurrency protection to `dotfiles.sh:762-888` (`main`) which previously had no lock (`T4`), and mirrors it identically in `dotfiles.ps1`.

---

### D6 — Post-Install Command Policy for `dotfiles.ps1`

- **Decision:**
  1. **Affected `DF_MANIFEST` Rows (`dotfiles.sh:391,393,394,396`):**
     - Line 391: `symlink|git/diff-so-fancy|${HOME}/.local/bin/diff-so-fancy|chmod +x ${HOME}/.local/bin/diff-so-fancy`
     - Line 393: `symlink|ssh/config|${HOME}/.ssh/config|chmod 600 ${HOME}/.ssh/config`
     - Line 394: `generate|ssh/allowed_signers.gen|${HOME}/.ssh/allowed_signers|chmod 600 ${HOME}/.ssh/allowed_signers`
     - Line 396: `symlink|dev/cmakepreset.py|${HOME}/.local/bin/cmakepreset.py|chmod 600 ${HOME}/.local/bin/cmakepreset.py`
  2. **Execution Policy in `dotfiles.ps1`:**
     - During `--dry-run`, `attempt_cmd_quiet` logs `[dry-run] <cmd>` verbatim so dry-run output matches bash.
     - During real execution (`_exec_post_cmd` in `src/action.ps1`):
       - On POSIX (`$IsLinux` or `$IsMacOS`): executes `chmod <mode> <target>` directly via `/bin/chmod` / `chmod`.
       - On Windows (`$IsWindows`):
         - `chmod 600 <path>` is translated to restricting Windows NTFS ACLs (`icacls.exe "<native_path>" /inheritance:r /grant:r "$($env:USERNAME):(R,W)"`), because Windows OpenSSH enforces strict owner-only permissions on `~/.ssh/config` and `~/.ssh/allowed_signers`.
         - `chmod +x <path>` logs `log_notice "Skipping '${cmd}' on Windows (POSIX execute bit not applicable)"` and returns `0`.
- **Rationale:**
  Preserves dry-run log parity across platforms, applies real POSIX permissions when running `pwsh` on Linux/macOS, satisfies Windows OpenSSH's ACL check on `.ssh/` files for `chmod 600`, and avoids false failures on `chmod +x` on Windows NTFS.
- **Implementing Files:**
  - `src/action.ps1` (`_install_entry`, `_exec_post_cmd`)
  - `src/utility.ps1` (`_exec_cmd`)
- **Existing Behaviour Preserved / Changed:**
  - Mirrors `src/action.sh:463-470` (`install_all` post-install execution) while translating `chmod` safely on Windows.

---

### D7 — PowerShell Module Layout, State Namespace & Function Naming

- **Decision:**
  1. **File Layout (mirroring `dotfiles.sh` + `src/*.sh` 1-to-1):**
     - `dotfiles.ps1` — bootstrap, global `DF_*` / `DOTFILES_*` state initialization, environment/OS detection, `_set_dotfiles_manifest`, `_populate_arrays`, concurrency lock (`acquire_lock` / `release_lock`), `initialise`, `main`.
     - `src/logging.ps1` — logger initialization (`init_logger`), log formatting (`[%l] %d %z [%s] %m`), levels `TRACE`..`EMERGENCY`, `log_trace`..`log_error`, `_enter` / `_exit` trace markers.
     - `src/utility.ps1` — `die`, `prompt_continue`, `is_windows_bash`, `parse_module_list`, `_exec_cmd`, `attempt_cmd`, `attempt_cmd_quiet`, `_canonical_path`, `_native_path`.
     - `src/print.ps1` — `print_help`, `git_or_unknown`, `print_version`, `list_modules`, `print_banner`, `print_end`.
     - `src/argparse.ps1` — `_assert_string_unset`, `_assert_flag_unset`, `assert_*_unset`, `assert_days`, `require_arg`, `argparse`.
     - `src/action.ps1` — `set_user_modules`, `set_dotfiles_ref`, `_prepare_file`, `_guard_dest`, `_install_entry` (shared single per-file install pipeline for install/update/repair), `manifest_write`, `manifest_remove`, `manifest_remove_prefix`, `manifest_clear`, `manifest_read`, `_read_manifest_entries`, `install_all`, `do_install`, `do_update`, `remove_file`, `do_uninstall`, `_maintenance_confirm`, `_clean_backups`, `_clean_logs`, `do_clean_backups`, `do_clean_logs`, `do_reset`, `do_repair`, `do_remove`.
  2. **Single Shared Per-File Install Pipeline (`1-B.2`):**
     Both `src/action.sh` and `src/action.ps1` extract `_install_entry` (`prepare -> guard -> link/copy/generate -> post-step -> manifest write`) and call it from `install_all` (used by `do_install` and `do_update`) and `do_repair`.
  3. **No Profile Dependency (`3.8` / `T5`):**
     `dotfiles.ps1` resolves all dot-sourced files and `modules/` strictly relative to `$PSScriptRoot` (`_set_src_path`), never `$PWD` or `$PROFILE`.
- **Rationale:**
  Enforces 1-B.2 (no copy-pasted install pipeline), 1-B.3 (modular layering matching `src/*.sh`), and 1-B.4 (line-by-line reviewability between bash and PowerShell).
- **Implementing Files:**
  - `dotfiles.ps1`, `src/logging.ps1`, `src/utility.ps1`, `src/print.ps1`, `src/argparse.ps1`, `src/action.ps1`
  - `src/action.sh` (`_install_entry` extraction shared by `install_all` and `do_repair`)
- **Existing Behaviour Preserved / Changed:**
  - Replaces the 1-line stub `dotfiles.ps1:1` (`Write-Host "Hello"`) with the full modular installer.
  - Refactors `src/action.sh:401-480` and `src/action.sh:1198-1247` to share `_install_entry`.

---

### D8 — `oh-my-posh` Theme Availability & Manifest Data Corrections

- **Decision:**
  1. **Choice for `oh-my-posh` rows (`dotfiles.sh:422-427`):** Retain all 6 `oh-my-posh.${DF_TARGET_OS}/themes/*.omp.json` rows in `DF_MANIFEST` and rely on **D4** resolution:
     - On Windows (`DF_TARGET_OS=windows`), `modules/oh-my-posh.windows/themes/*.omp.json` resolves directly and is available (`✓` / `✗` / `!`).
     - On non-Windows OSes (`macos`, `cachyos`, `debian`), where `modules/oh-my-posh.<os>/` is absent on disk, D4 logs a `log_warn` during `_populate_arrays` and records all 6 rows in `DF_UNAVAILABLE_MODULES`, so `--list` displays them under the `oh-my-posh` category with the `?` status marker (`? tiger.omp.json`, etc.) rather than silently dropping them.
  2. **Shifted Row Fix (`T2`, `dotfiles.sh:385`):** Fix the 5-field malformed row `"symlink|.bashrc|bash/bashrc|${HOME}/.bashrc"` in `dotfiles.sh:385` to the canonical 4-field format `"symlink|bash/bashrc|${HOME}/.bashrc"`, matching `modules/bash/bashrc` on disk.
- **Rationale:**
  Keeping the rows in `DF_MANIFEST` and resolving via D4 honors Section 7 ("No module content changes outside the Phase 4 pwsh parity work"), avoids special-casing `list_modules` (1-B.1), and satisfies Phase 1 Gate G1 (`--list` shows previously-invisible modules with their new status) and Phase 5.3 (`no module row in DF_MANIFEST may be absent from --list output`).
- **Implementing Files:**
  - `dotfiles.sh` (`_set_dotfiles_manifest` line 385, `_populate_arrays` lines 435-486)
  - `dotfiles.ps1` (`_set_dotfiles_manifest`, `_populate_arrays`)
- **Existing Behaviour Preserved / Changed:**
  - Fixes `dotfiles.sh:385` so `bash/bashrc` resolves and installs to `${HOME}/.bashrc`.
  - Makes all 6 `oh-my-posh` rows (and `pwsh`, `tmux`, `git/gitconfig.local`) visible in `--list` on every OS.

---

## T1 — Complete `DF_MANIFEST` Variant Audit Table (`dotfiles.sh:373-429`)

Supported `(OS, runtime)` environments:
- **macOS:** `DF_TARGET_OS=macos`, `DF_TARGET_RUNTIME=native`
- **CachyOS:** `DF_TARGET_OS=cachyos`, `DF_TARGET_RUNTIME=native`
- **Debian:** `DF_TARGET_OS=debian`, `DF_TARGET_RUNTIME=native`
- **WSL (CachyOS / Debian):** `DF_TARGET_OS=cachyos|debian`, `DF_TARGET_RUNTIME=wsl`
- **Windows:** `DF_TARGET_OS=windows`, `DF_TARGET_RUNTIME=gitbash|native`

| # | Line | Action | `DF_MANIFEST` `src` Pattern | `dest` | macOS (`native`) | CachyOS (`native`) | Debian (`native`) | WSL (`cachyos`/`debian`) | Windows (`gitbash`/`native`) | D4 Resolution & `--list` Status When Missing |
|---|------|--------|-----------------------------|--------|------------------|--------------------|-------------------|--------------------------|------------------------------|---------------------------------------------|
| 1 | 374 | `symlink` | `zsh/zshrc` | `${HOME}/.zshrc` | Exact | Exact | Exact | Exact | Exact | Direct match (`modules/zsh/zshrc`) |
| 2 | 375 | `symlink` | `zsh/zsh_options` | `${HOME}/.zsh_options` | Exact | Exact | Exact | Exact | Exact | Direct match (`modules/zsh/zsh_options`) |
| 3 | 376 | `symlink` | `zsh/zstyles` | `${HOME}/.zstyles` | Exact | Exact | Exact | Exact | Exact | Direct match (`modules/zsh/zstyles`) |
| 4 | 377 | `symlink` | `zsh/zimrc` | `${HOME}/.zimrc` | Exact | Exact | Exact | Exact | Exact | Direct match (`modules/zsh/zimrc`) |
| 5 | 378 | `symlink` | `zsh/p10k.zsh` | `${HOME}/.p10k.zsh` | Exact | Exact | Exact | Exact | Exact | Direct match (`modules/zsh/p10k.zsh`) |
| 6 | 379 | `symlink` | `zsh/exports` | `${HOME}/.exports` | Exact | Exact | Exact | Exact | Exact | Direct match (`modules/zsh/exports`) |
| 7 | 380 | `symlink` | `zsh/paths` | `${HOME}/.paths` | Exact | Exact | Exact | Exact | Exact | Direct match (`modules/zsh/paths`) |
| 8 | 381 | `symlink` | `zsh/aliases` | `${HOME}/.aliases` | Exact | Exact | Exact | Exact | Exact | Direct match (`modules/zsh/aliases`) |
| 9 | 382 | `symlink` | `zsh/functions` | `${HOME}/.functions` | Exact | Exact | Exact | Exact | Exact | Direct match (`modules/zsh/functions`) |
| 10 | 383 | `symlink` | `zsh/zshrc.toggles` | `${HOME}/.zshrc.toggles` | Exact | Exact | Exact | Exact | Exact | Direct match (`modules/zsh/zshrc.toggles`) |
| 11 | 385 | `symlink` | `bash/bashrc` *(fixed from `.bashrc\|bash/bashrc`)* | `${HOME}/.bashrc` | Exact | Exact | Exact | Exact | Exact | Fixed T2 shifted row -> Direct match (`modules/bash/bashrc`) |
| 12 | 387 | `symlink` | `git/gitconfig` | `${HOME}/.gitconfig` | Exact | Exact | Exact | Exact | Exact | Direct match (`modules/git/gitconfig`) |
| 13 | 388 | `copy` | `git/gitconfig.local.${DF_TARGET_OS}` | `${HOME}/.gitconfig.local` | Exact (`.macos`) | Exact (`.cachyos`) | **Missing** (`.debian`) | Fallback 3a (`.wsl`) | Exact (`.windows`) | WSL resolves `gitconfig.local.wsl` (D4-3a); native Debian logs `log_warn` & shows `?` in `--list` (D4-4) |
| 14 | 389 | `symlink` | `git/gitignore` | `${HOME}/.gitignore` | Exact | Exact | Exact | Exact | Exact | Direct match (`modules/git/gitignore`) |
| 15 | 390 | `symlink` | `git/gitattributes` | `${HOME}/.gitattributes` | Exact | Exact | Exact | Exact | Exact | Direct match (`modules/git/gitattributes`) |
| 16 | 391 | `symlink` | `git/diff-so-fancy` | `${HOME}/.local/bin/diff-so-fancy` | Exact | Exact | Exact | Exact | Exact | Direct match (`chmod +x` handled per D6) |
| 17 | 393 | `symlink` | `ssh/config` | `${HOME}/.ssh/config` | Exact | Exact | Exact | Exact | Exact | Direct match (`chmod 600` handled per D6) |
| 18 | 394 | `generate` | `ssh/allowed_signers.gen` | `${HOME}/.ssh/allowed_signers` | Exact | Exact | Exact | Exact | Exact | Direct match (`chmod 600` handled per D6) |
| 19 | 396 | `symlink` | `dev/cmakepreset.py` | `${HOME}/.local/bin/cmakepreset.py` | Exact | Exact | Exact | Exact | Exact | Direct match (`chmod 600` handled per D6) |
| 20 | 397 | `symlink` | `dev/internal-flags.cmake` | `${HOME}/dev/internal-flags.cmake` | Exact | Exact | Exact | Exact | Exact | Direct match |
| 21 | 398 | `symlink` | `dev/cmake-format.py` | `${HOME}/dev/.cmake-format.py` | Exact | Exact | Exact | Exact | Exact | Direct match |
| 22 | 399 | `symlink` | `dev/clang-format` | `${HOME}/dev/.clang-format` | Exact | Exact | Exact | Exact | Exact | Direct match |
| 23 | 400 | `symlink` | `dev/clang-tidy` | `${HOME}/dev/.clang-tidy` | Exact | Exact | Exact | Exact | Exact | Direct match |
| 24 | 401 | `symlink` | `dev/editorconfig` | `${HOME}/dev/.editorconfig` | Exact | Exact | Exact | Exact | Exact | Direct match |
| 25 | 403 | `symlink` | `topgrade/topgrade.toml` | `${topgrade_dest}` | Exact | Exact | Exact | Exact | **Skipped (OS rule)** | Excluded on Windows (`dotfiles.sh:461`); D4-1 logs `log_warn` & shows `?` in `--list` on Windows |
| 26 | 404 | `symlink` | `fastfetch/config.jsonc.${DF_TARGET_OS}` | `${HOME}/.config/fastfetch/config.jsonc` | Exact (`.macos`) | Fallback 3b (`config.jsonc`) | Fallback 3b (`config.jsonc`) | Fallback 3b (`config.jsonc`) | Fallback 3b (`config.jsonc`) | Resolves on all OSes: exact `.macos` on macOS, base fallback `fastfetch/config.jsonc` (D4-3b) on all others |
| 27 | 405 | `symlink` | `tmux/tmux.conf.${DF_TARGET_OS}` | `${HOME}/.tmux.conf` | Exact (`.macos`) | **Missing** | **Missing** | **Missing** | **Missing** | No base `tmux/tmux.conf` on disk; non-macOS logs `log_warn` & shows `?` in `--list` (D4-4) |
| 28 | 406 | `symlink` | `curl/curlrc` | `${HOME}/.curlrc` | Exact | Exact | Exact | Exact | Exact | Direct match |
| 29 | 407 | `symlink` | `wget/wgetrc` | `${HOME}/.wgetrc` | Exact | Exact | Exact | Exact | Exact | Direct match |
| 30 | 408 | `symlink` | `shellcheck/shellcheckrc` | `${HOME}/.shellcheckrc` | Exact | Exact | Exact | Exact | Exact | Direct match |
| 31 | 410 | `symlink` | `claude/settings.json` | `${HOME}/.claude/settings.json` | Exact | Exact | Exact | Exact | Exact | Direct match |
| 32 | 411 | `symlink` | `claude/plugin.json` | `${HOME}/.claude/plugin.json` | Exact | Exact | Exact | Exact | Exact | Direct match |
| 33 | 413 | `copy` | `pwsh.${DF_TARGET_OS}/Profile` | `${HOME}/Documents/Powershell/Microsoft.PowerShell_profile.ps1` | **Missing** | **Missing** | **Missing** | **Missing** | Exact (`pwsh.windows`) | Non-Windows logs `log_warn` & shows `?` in `--list` (D4-4) |
| 34 | 414 | `copy` | `pwsh.${DF_TARGET_OS}/Set-MSVC-Environment` | `${HOME}/Documents/Powershell/Scripts/Set-MSVC-Environment.ps1` | **Missing** | **Missing** | **Missing** | **Missing** | Exact (`pwsh.windows`) | Non-Windows logs `log_warn` & shows `?` in `--list` (D4-4) |
| 35 | 415 | `copy` | `pwsh.${DF_TARGET_OS}/Update-Modules` | `${HOME}/Documents/Powershell/Scripts/Update-Modules.ps1` | **Missing** | **Missing** | **Missing** | **Missing** | Exact (`pwsh.windows`) | Non-Windows logs `log_warn` & shows `?` in `--list` (D4-4) |
| 36 | 416 | `copy` | `pwsh.${DF_TARGET_OS}/Print-Env` | `${HOME}/Documents/Powershell/Scripts/Print-Env.ps1` | **Missing** | **Missing** | **Missing** | **Missing** | Exact (`pwsh.windows`) | Non-Windows logs `log_warn` & shows `?` in `--list` (D4-4) |
| 37 | 417 | `copy` | `pwsh.${DF_TARGET_OS}/nproc` | `${HOME}/Documents/Powershell/Scripts/nproc.ps1` | **Missing** | **Missing** | **Missing** | **Missing** | Exact (`pwsh.windows`) | Non-Windows logs `log_warn` & shows `?` in `--list` (D4-4) |
| 38 | 418 | `copy` | `pwsh.${DF_TARGET_OS}/sha256` | `${HOME}/Documents/Powershell/Scripts/sha256.ps1` | **Missing** | **Missing** | **Missing** | **Missing** | Exact (`pwsh.windows`) | Non-Windows logs `log_warn` & shows `?` in `--list` (D4-4) |
| 39 | 419 | `copy` | `pwsh.${DF_TARGET_OS}/sha1` | `${HOME}/Documents/Powershell/Scripts/sha1.ps1` | **Missing** | **Missing** | **Missing** | **Missing** | Exact (`pwsh.windows`) | Non-Windows logs `log_warn` & shows `?` in `--list` (D4-4) |
| 40 | 420 | `copy` | `pwsh.${DF_TARGET_OS}/md5` | `${HOME}/Documents/Powershell/Scripts/md5.ps1` | **Missing** | **Missing** | **Missing** | **Missing** | Exact (`pwsh.windows`) | Non-Windows logs `log_warn` & shows `?` in `--list` (D4-4) |
| 40a | 421 | `copy` | `pwsh.${DF_TARGET_OS}/Exports` | `${HOME}/Documents/Powershell/Scripts/Exports.ps1` | **Missing** | **Missing** | **Missing** | **Missing** | Exact (`pwsh.windows`) | Added in Phase 4; non-Windows logs `log_warn` & shows `?` in `--list` (D4-4) |
| 40b | 422 | `copy` | `pwsh.${DF_TARGET_OS}/Paths` | `${HOME}/Documents/Powershell/Scripts/Paths.ps1` | **Missing** | **Missing** | **Missing** | **Missing** | Exact (`pwsh.windows`) | Added in Phase 4; non-Windows logs `log_warn` & shows `?` in `--list` (D4-4) |
| 40c | 423 | `copy` | `pwsh.${DF_TARGET_OS}/Aliases` | `${HOME}/Documents/Powershell/Scripts/Aliases.ps1` | **Missing** | **Missing** | **Missing** | **Missing** | Exact (`pwsh.windows`) | Added in Phase 4; non-Windows logs `log_warn` & shows `?` in `--list` (D4-4) |
| 40d | 424 | `copy` | `pwsh.${DF_TARGET_OS}/Functions` | `${HOME}/Documents/Powershell/Scripts/Functions.ps1` | **Missing** | **Missing** | **Missing** | **Missing** | Exact (`pwsh.windows`) | Added in Phase 4; non-Windows logs `log_warn` & shows `?` in `--list` (D4-4) |
| 41 | 426 | `symlink` | `oh-my-posh.${DF_TARGET_OS}/themes/tiger.omp.json` | `${HOME}/.oh-my-posh/themes/tiger.omp.json` | **Missing** | **Missing** | **Missing** | **Missing** | Exact (`oh-my-posh.windows`) | Non-Windows logs `log_warn` & shows `?` in `--list` (D4-4, D8) |
| 42 | 423 | `symlink` | `oh-my-posh.${DF_TARGET_OS}/themes/agnoster.omp.json` | `${HOME}/.oh-my-posh/themes/agnoster.omp.json` | **Missing** | **Missing** | **Missing** | **Missing** | Exact (`oh-my-posh.windows`) | Non-Windows logs `log_warn` & shows `?` in `--list` (D4-4, D8) |
| 43 | 424 | `symlink` | `oh-my-posh.${DF_TARGET_OS}/themes/kushal.omp.json` | `${HOME}/.oh-my-posh/themes/kushal.omp.json` | **Missing** | **Missing** | **Missing** | **Missing** | Exact (`oh-my-posh.windows`) | Non-Windows logs `log_warn` & shows `?` in `--list` (D4-4, D8) |
| 44 | 425 | `symlink` | `oh-my-posh.${DF_TARGET_OS}/themes/powerlevel10k_classic.omp.json` | `${HOME}/.oh-my-posh/themes/powerlevel10k_classic.omp.json` | **Missing** | **Missing** | **Missing** | **Missing** | Exact (`oh-my-posh.windows`) | Non-Windows logs `log_warn` & shows `?` in `--list` (D4-4, D8) |
| 45 | 426 | `symlink` | `oh-my-posh.${DF_TARGET_OS}/themes/powerlevel10k_lean.omp.json` | `${HOME}/.oh-my-posh/themes/powerlevel10k_lean.omp.json` | **Missing** | **Missing** | **Missing** | **Missing** | Exact (`oh-my-posh.windows`) | Non-Windows logs `log_warn` & shows `?` in `--list` (D4-4, D8) |
| 46 | 427 | `symlink` | `oh-my-posh.${DF_TARGET_OS}/themes/powerlevel10k_modern.omp.json` | `${HOME}/.oh-my-posh/themes/powerlevel10k_modern.omp.json` | **Missing** | **Missing** | **Missing** | **Missing** | Exact (`oh-my-posh.windows`) | Non-Windows logs `log_warn` & shows `?` in `--list` (D4-4, D8) |

---

## Phase 4 — Zsh-to-PowerShell Module Parity Mapping

| `modules/zsh/` File | PowerShell Counterpart (`modules/pwsh.windows/`) | Notes / Rationale |
|---------------------|--------------------------------------------------|-------------------|
| `zsh/zshrc` | `pwsh.windows/Profile` (`Microsoft.PowerShell_profile.ps1`) | Initializes `$env:HOME`/`$env:USERPROFILE`, dot-sources `Documents/Powershell/Scripts/*.ps1` with `Test-Path` guards, imports available PS modules with `-ErrorAction SilentlyContinue`, initializes `zoxide` and `oh-my-posh` when installed, and sources `.local` overrides. |
| `zsh/exports` | `pwsh.windows/Exports` (`Scripts/Exports.ps1`) | Sets `$env:EDITOR`, `$env:VISUAL`, `$env:LANG`, `$env:LC_ALL`, `$env:ANTHROPIC_*`, `$env:CLAUDE_CODE_*`, `$env:DISABLE_TELEMETRY`, `$env:GITHUB_PUBLIC_EMAIL`; MSVC env setup is handled by `Set-MSVC-Environment.ps1`. |
| `zsh/paths` | `pwsh.windows/Paths` (`Scripts/Paths.ps1`) | Defines `Prepend-Path` and prepends `~/.local/bin`, `~/opt/clang-p2996/bin`, `~/opt/clang-trunk/bin`, `~/opt/gcc-trunk/bin`, `~/opt/llamacpp/bin` to `$env:PATH` without duplicates. |
| `zsh/aliases` | `pwsh.windows/Aliases` (`Scripts/Aliases.ps1`) | Converts argument-passing zsh aliases (`..`, `...`, `....`, `.....`, `H`, `dots`, `opts`, `stars`, `fmt`, `tidy`, `shellcheck`, `eza` wrappers `ll`/`l`/`lr`/`ld`/`lh`/`lx`/`lk`/`lt`/`lc`, VSCodium wrappers `c.`/`cdiff`/`cr`/`cr.`, `ez`) into PowerShell functions and aliases (`c` -> `Clear-Host`, `G` -> `git`). |
| `zsh/functions` | `pwsh.windows/Functions` (`Scripts/Functions.ps1`) | Implements PowerShell function equivalents for `mkcd`, `cpv`, `fs`, `_generate_github_ssh_key`, `github_ssh_key`, `github_ssh_sk`, `gac`, `gacp`, `gaac`, `gaacp`, `git_init`, and `docker` auto-start wrapper. |
| `zsh/zsh_options` | No standalone pwsh file (`Profile` + `AutoCd`) | `setopt` options (`EXTENDED_HISTORY`, `HIST_IGNORE_DUPS`, `AUTO_MENU`) are zsh-specific builtins; PowerShell equivalents are configured via `Set-PSReadLineOption` in `Profile` and `AutoCd`. |
| `zsh/zstyles` | No pwsh equivalent | `zstyle ':completion:*'` and `:vcs_info:*` configure zsh's `compsys` and `vcs_info` subsystems, which do not exist in PowerShell (PSReadLine handles completion UI and `oh-my-posh` renders VCS prompt state). |
| `zsh/zimrc` | No pwsh equivalent | `zimfw` (`zmodule`) is a zsh-only plugin manager; PowerShell modules are managed by `PSResourceGet` (`Update-Modules.ps1`). |
| `zsh/p10k.zsh` | No pwsh script equivalent (`oh-my-posh.windows/themes/*.omp.json`) | `p10k.zsh` is a zsh script for `powerlevel10k`; in PowerShell, prompt themes are provided by `oh-my-posh` (`tiger.omp.json` and `powerlevel10k_*.omp.json`). |
| `zsh/zshrc.toggles` | No standalone pwsh file (`Profile` `.local` overrides) | `DEBUG_MODE` and `ENABLE_PROFILING` are environment/local overrides read by `Profile` if set in `~/.profile.local.ps1`. |

---

## Error & Gate Log (Append-Only)

- **Gate G0 Verification (Phase 0):** `DECISIONS.md` created with D1–D8, complete `DF_MANIFEST` variant audit table (T1), and Phase 4 zsh-to-pwsh mapping table. All implementing files and `file:line` citations recorded prior to writing any implementation code.
- **Error E1 (Phase 1 — `shellcheck` baseline check on `dotfiles.sh src/*.sh`):**
  - **Symptom:** `shellcheck dotfiles.sh src/*.sh` failed with `SC1090`, `SC2034`, `SC2154`, `SC2155`, `SC2016`, `SC2181`, `SC2295`, and `SC2059` across `dotfiles.sh`, `src/action.sh`, `src/argparse.sh`, `src/print.sh`, and `src/utility.sh`.
  - **Root Cause:** `.shellcheckrc` enables `check-unassigned-uppercase` (`SC2154`) and `quote-safe-variables`, while `dotfiles.sh:551` sources `SOURCE_FILES` dynamically (`source "${file}"`), preventing ShellCheck from linking cross-file `DF_*` / `DOTFILES_*` globals between `dotfiles.sh` and `src/*.sh`. Additionally, `dotfiles.sh:10` combined `readonly` and `$(date ...)` (`SC2155`), `src/print.sh:144,146` had unquoted parameter expansions inside `${filename%...}` (`SC2295`), and `src/action.sh:1218,1236` checked `$?` indirectly (`SC2181`).
  - **Fix:** Separate `DOTFILES_START_TIME` assignment from `readonly` (`dotfiles.sh:10`); quote `${_env_sfx}` / `${_os_sfx}` in `src/print.sh`; replace `do_repair` duplicate install block with `_install_entry` (fixing `SC2181` and satisfying `1-B.2`); and add file-level ShellCheck directives (`# shellcheck disable=SC2034,SC2154,SC1090,SC2016,SC2059`) in `dotfiles.sh` and `src/*.sh` for intentional cross-file globals and format strings.
  - **Files:** `dotfiles.sh`, `src/action.sh`, `src/argparse.sh`, `src/print.sh`, `src/utility.sh`.
- **Error E2 (Phase 1 — `--dry-run` contract inspection in `do_update` and `do_uninstall`):**
  - **Symptom:** In `src/action.sh:561-604`, `do_update` executed live `git fetch`, mutated `${DOTFILES_MANIFEST_FILE}`, and executed `git rebase` / `git branch -f` even when `DF_DRY_RUN=1`. In `src/action.sh:660-695,729-741`, `do_uninstall` blocked on interactive `read -r` prompts even when `DF_DRY_RUN=1` (and at line 666 even when `DF_NOCONFIRM=1`).
  - **Root Cause:** Missing `((DF_DRY_RUN))` and `((DF_NOCONFIRM))` guards in `do_update` and `do_uninstall`, violating Contract 3.7 ("`--dry-run` prints the planned operation (`[dry-run] ` prefix) and touches nothing, including no prompt").
  - **Fix:** Guard `do_update` fetch/rebase/manifest-header/branch-f steps with `if ((DF_DRY_RUN))` (logging `[dry-run] ...` and skipping disk/git mutations) and guard all `do_uninstall` confirmation prompts with `if ! ((DF_DRY_RUN)) && ! ((DF_NOCONFIRM))`. Mirror identical logic in `src/action.ps1`.
  - **Files:** `src/action.sh`, `src/action.ps1`.
- **Error E3 (Phase 1 — `shellcheck` SC2317 on `release_lock`):**
  - **Symptom:** `shellcheck dotfiles.sh src/*.sh` reported `SC2317 (info): Command appears to be unreachable` inside `release_lock()` (`dotfiles.sh:832-846`).
  - **Root Cause:** `release_lock` was only invoked indirectly via `trap 'release_lock' EXIT INT TERM`, which ShellCheck flags as `SC2317`.
  - **Fix:** Add `# shellcheck disable=SC2317` on `release_lock()` and also call `release_lock` explicitly before `exit "${ec}"` in `main()`.
  - **Files:** `dotfiles.sh`.
- **Error E4 (Phase 1 — `src/logging.sh` `_strip_ansi_codes` and `_format_log_message` subshell overhead under TRACE level):**
  - **Symptom:** Sequential dry-run execution of `dotfiles.sh` commands spawned hundreds of `sed` and `date` child processes per invocation during `initialise` (which logs at `TRACE` level).
  - **Root Cause:** `_strip_ansi_codes` (`src/logging.sh:995-1054`) piped `$input` through 7 `sed` invocations even when `$input` contained no ESC (`\033`) character, and `_format_log_message` forked `date` on every log line even when `${EPOCHREALTIME}` and `printf '%(...)T'` were available.
  - **Fix:** Add fast-path `if [[ $LOG_UNSAFE_ALLOW_ANSI_CODES == "true" || $input != *$'\033'* ]]` in `_strip_ansi_codes` and use `printf -v current_date '%(%Y-%m-%d %H:%M:%S)T.%s' -1 "${frac:0:3}"` when `EPOCHREALTIME` is present in `_format_log_message`.
  - **Files:** `src/logging.sh`.
- **Error E5 (Phase 1 — Category header suffix in `list_modules`):**
  - **Symptom:** `bash dotfiles.sh --list` displayed category headers `pwsh.debian` and `oh-my-posh.debian` instead of `pwsh` and `oh-my-posh`.
  - **Root Cause:** `DF_CATEGORY_MAP` maps `display_cat -> raw_cat` (for `parse_module_list`), so `DF_CATEGORY_MAP["${raw_cat}"]` in `src/print.sh:141` missed and fell back to `raw_cat` (`pwsh.debian`).
  - **Fix:** Strip `.${DF_TARGET_ENV}`, `.${DF_TARGET_OS}`, and `.${DF_TARGET_RUNTIME}` from `category` in `list_modules` (`src/print.sh` and `src/print.ps1`), matching the suffix stripping already performed on `filename`.
  - **Files:** `src/print.sh`, `src/print.ps1`.
- **Error E6 (Phase 1 — `manifest_write` mutating `manifest.tsv` during `--dry-run`):**
  - **Symptom:** Running `bash dotfiles.sh --install --dry-run` created and populated `${DOTFILES_MANIFEST_FILE}` on disk because `attempt_cmd_quiet` returns `0` under `DF_DRY_RUN=1` and `_install_entry` (`src/action.sh:474`) called `manifest_write` unconditionally.
  - **Root Cause:** `manifest_write`, `manifest_remove`, `manifest_remove_prefix`, and `manifest_clear` lacked a `((DF_DRY_RUN))` guard, violating Contract 3.7 ("`--dry-run` prints the planned operation and touches nothing").
  - **Fix:** Guard `manifest_write`, `manifest_remove`, `manifest_remove_prefix`, and `manifest_clear` in both `src/action.sh` and `src/action.ps1` with `if ((DF_DRY_RUN)); then return 0; fi`.
  - **Files:** `src/action.sh`, `src/action.ps1`.
- **Gate G1 Verification (Phase 1):** `bash -n dotfiles.sh src/*.sh` passed; `shellcheck dotfiles.sh src/*.sh` passed with 0 warnings; `bash dotfiles.sh --list` rendered all manifest entries with `✗`/`?` statuses; and all 9 actions (`install`, `update`, `remove zsh`, `repair`, `reset`, `uninstall`, `clean`, `clean-logs`, `clean-backups`) passed with `--dry-run` and exit code `0`.
- **Error E7 (Phase 2 — PowerShell function scope when dot-sourcing `src/*.ps1` inside `initialise`):**
  - **Symptom:** Running `pwsh -NoProfile -File dotfiles.ps1 --help` failed at `dotfiles.ps1:630` with `The term 'argparse' is not recognized as a name of a cmdlet, function, script file, or executable program`.
  - **Root Cause:** In PowerShell, dot-sourcing `. $fullSf` inside a normal function (`initialise`) defines the sourced functions in `initialise`'s local scope rather than the script scope, so they vanish when `initialise` returns to `main`.
  - **Fix:** Invoke `. initialise` (dot-sourced) inside `main` in `dotfiles.ps1` so that `initialise` and all `. $fullSf` modules execute in the script scope.
  - **Files:** `dotfiles.ps1`.
- **Error E8 (Phase 2 — Uncaptured `0` return value from `manifest_read` in `list_modules`):**
  - **Symptom:** `diff -u` between `bash dotfiles.sh --list` and `pwsh -NoProfile -File dotfiles.ps1 --list` showed a leading `0` line in `ps1-list.txt` (`+0` before `AVAILABLE MODULES`), with all remaining lines 100% identical.
  - **Root Cause:** `list_modules` in `src/print.ps1:137` called `manifest_read ([ref]$installed_src)` without `[void](...)`, causing PowerShell's pipeline to write `manifest_read`'s `return 0` to stdout.
  - **Fix:** Suppress the return value via `[void](manifest_read ([ref]$installed_src))` in `src/print.ps1`.
  - **Files:** `src/print.ps1`.
- **Error E9 (Phase 2.5 — PowerShell array splatting syntax `@($log_cmd.ToArray())` in `dotfiles.ps1:main`):**
  - **Symptom:** `pwsh -NoProfile -File dotfiles.ps1 --install --dry-run` failed with `Unknown parameter for logger: --level INFO --format [%l] %d %z [%s] %m --log ...`.
  - **Root Cause:** In PowerShell, `@(...)` is the array subexpression operator rather than argument splatting (`@varName`), so `@($log_cmd.ToArray())` passed the entire array as `$args[0]` to `init_logger`.
  - **Fix:** Assign `$log_cmd_arr = $log_cmd.ToArray()` and splat via `init_logger @log_cmd_arr` in `dotfiles.ps1`.
  - **Files:** `dotfiles.ps1`.
- **Gate G2 & Gate G3 Verification (Phases 2 & 2.5):**
  - PowerShell AST parser validated `dotfiles.ps1` and all `src/*.ps1` (`src/logging.ps1`, `src/utility.ps1`, `src/print.ps1`, `src/argparse.ps1`, `src/action.ps1`) with 0 parse errors.
  - `diff -u` between `bash dotfiles.sh --list` and `pwsh -NoProfile -File dotfiles.ps1 --list` is 0 bytes (100% identical).
  - Manifest round-trip verified for CRLF and LF inputs, `# ref=` headers, and destination paths containing spaces; output confirmed UTF-8 no-BOM with LF (`0x0A`) only.
  - All actions (`list`, `install`, `update`, `remove zsh`, `repair`, `reset`, `uninstall`, `clean`, `clean-logs`, `clean-backups`) passed `--dry-run` with exit code `0`, and exit-code checks passed (`2` for bad flag, `2` for conflicting flags, `130` for prompt decline).
- **Error E10 (Phase 4 — Missing `modules/pwsh.windows/Paths` file):**
  - **Symptom:** Gate G4 script test printed `cp: cannot stat 'modules/pwsh.windows/Paths': No such file or directory`.
  - **Root Cause:** The `Paths` content was accidentally written to `modules/pwsh.windows/Aliases` before `Aliases` overwrote it.
  - **Fix:** Write `modules/pwsh.windows/Paths` to `/app/modules/pwsh.windows/Paths` and re-verify `Paths.ps1` loading in `Profile`.
  - **Files:** `modules/pwsh.windows/Paths`.
- **Gate G4 Verification (Phase 4):** All 19 PowerShell files (`dotfiles.ps1`, `src/*.ps1`, and `modules/pwsh.windows/*`) passed AST parse checks with 0 errors. `Profile` and all dot-sourced scripts in `Documents/Powershell/Scripts/` loaded cleanly under `pwsh -NoProfile` against a throwaway `USERPROFILE`/`HOME`, setting `$env:EDITOR`, prepending `~/.local/bin` to `$env:PATH`, and providing `nproc`, `mkcd`, `..`, `sha256`, `sha1`, `md5`, `gac`, `gacp`, `gaac`, and `gaacp`.
- **Error E11 (Phase 5 — `pwsh -Command` string argument binding in `scripts/verify.sh`):**
  - **Symptom:** `pwsh -NoProfile -Command '...' -Args "${REPO_ROOT}"` left `$Root` empty inside `scripts/verify.sh`.
  - **Root Cause:** When `pwsh -Command` is invoked from an external shell (bash), `-Command` receives a string rather than a PowerShell scriptblock literal, so `-Args` does not bind `param($Root)`.
  - **Fix:** Pass `REPO_ROOT="${REPO_ROOT}"` as an environment variable (`$env:REPO_ROOT`) to `pwsh -NoProfile -Command` in `scripts/verify.sh`.
  - **Files:** `scripts/verify.sh`.
- **Error E12 (Phase 5 — Multibyte UTF-8 bracket expression `[✓✗!?]` in `grep -E` inside `scripts/verify.sh`):**
  - **Symptom:** `grep -qE "^  [✓✗!?] ${item_name}\$"` in `scripts/verify.sh` did not match `  ✗ zshrc` even though `diff -u` passed.
  - **Root Cause:** Multi-byte UTF-8 glyphs (`✓`, `✗`) inside a regex bracket class `[...]` are not matched reliably across locales by `grep -E`; alternation `(✓|✗|!|\?)` is required.
  - **Fix:** Replace `[✓✗!?]` with `(✓|✗|!|\?)` in `scripts/verify.sh`.
  - **Files:** `scripts/verify.sh`.
- **Error E13 (Phase 5 — PowerShell `switch -Regex` default case-insensitivity on `-i`/`-I` and `-r`/`-R` in `src/argparse.ps1`):**
  - **Symptom:** Running `pwsh -NoProfile -File dotfiles.ps1 --install -i "curl;wget;bash" --noconfirm` triggered interactive `Continue? [Y/n]` prompts on stderr.
  - **Root Cause:** PowerShell's `switch -Regex` is case-insensitive unless `-CaseSensitive` is specified, so `-i` (`--include`) also matched `^(-I|--interactive)$` (and `-r` vs `-R` would collide).
  - **Fix:** Add `-CaseSensitive` to `switch -Regex -CaseSensitive` in `src/argparse.ps1` and `src/logging.ps1` so short flags (`-i` vs `-I`, `-r` vs `-R`) are matched case-sensitively, identical to bash `case "$1"`.
  - **Files:** `src/argparse.ps1`, `src/logging.ps1`.
- **Error E14 (Phase 5 — `windows_handoff` argument forwarding in `dotfiles.sh:689,772`):**
  - **Symptom:** `windows_handoff` in `dotfiles.sh:689` invoked `dotfiles.ps1` without forwarding `"$@"`, which would cause `dotfiles.ps1` to fail with `Error: no action specified` (exit code `2`) after handoff from `bash dotfiles.sh --install`.
  - **Root Cause:** `main()` called `windows_handoff` without `"$@"` (`dotfiles.sh:772`) and `ps_args` omitted `"$@"`.
  - **Fix:** Pass `"$@"` from `main()` to `windows_handoff "$@"` and append `"$@"` to `ps_args`.
  - **Files:** `dotfiles.sh`.
- **Gate G5 Verification (Phase 5):** `scripts/verify.sh` executed all 6 verification suites (`bash -n` + `shellcheck` + PowerShell AST parse; dry-runs of all bash & ps1 actions; `--list` 50-row regression guard & byte-equivalence; `manifest.tsv` parity & cross-read `--list`/`--repair`; `.bak`/`.1.bak` backup path equivalence; exit codes `0`/`1`/`2`/`130` & D5 concurrency lock) and exited `0`.
















