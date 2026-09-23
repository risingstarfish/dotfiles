[![Github releases](https://img.shields.io/github/release/risingstarfish/dotfiles.svg)](https://github.com/risingstarfish/dotfiles/releases)
[![License](https://img.shields.io/github/license/risingstarfish/dotfiles.svg)](LICENSE)

## dotfiles

A cross-platform dotfiles installer for macOS, Windows (native PowerShell, WSL, and Git Bash), and Linux (tested on CachyOS).

One script installs, updates, repairs, and removes shell and tool configuration. Configuration lives under `modules/` and is symlinked (or copied) into your home directory. A state manifest tracks every installed file so removals are precise, and anything the installer overwrites is backed up to `~/.cache/dotfiles/backups/` first.

## About this project

- **Bash-first.** `dotfiles.sh` is the primary installer. On native Windows it offers to hand off to `dotfiles.ps1`, the faster PowerShell installer.
- **Module-based.** Each tool's configuration lives in `modules/<tool>/`. The set of available modules depends on your platform — see `--list` below.
- **Non-destructive.** Existing files are moved to `~/.cache/dotfiles/backups/<timestamp>/` before being replaced, never deleted silently.
- **Personal config via `.local` files.** Tracked files are meant to stay untouched; per-user settings go in `.local` overrides (e.g., `~/.paths.local`, `~/.zshrc.local`), which updates never overwrite. The only exception if `.gitconfig.local` because those will never change (for me at least).

## Requirements

- **bash ≥ 4.0** — macOS ships bash 3.2, so install a modern one first: `brew install bash`
- **git**
- **zsh** — for the zsh modules (the bulk of the shell configuration)
- On Windows: Git for Windows (Git Bash) or WSL to run the bash installer, or just use `dotfiles.ps1`

## Installation

**Warning:** If you want to give these dotfiles a try, you should first fork this repository, review the code, and remove modules you don't want or need. Don't blindly use my settings unless you know what that entails. Use at your own risk!

### Using Git

You can clone the repository wherever you want. (I like to keep it in `~/dotfiles`.) The install script will symlink or copy the files to their relevant locations (mainly your home directory).

```bash
git clone https://github.com/risingstarfish/dotfiles.git && cd dotfiles && bash dotfiles.sh --install
```

To update, `cd` into your local `dotfiles` repository and then run:

```bash
bash dotfiles.sh --update
```

This pulls the latest changes from git before re-running the installation. If your repository has uncommitted changes to tracked files, the update is blocked on purpose — revert them or move them to a `.local` override file first (set `DOTFILES_LOCAL_MODS=1` to bypass the check).

### Commands

| Command       | Flag(s)                    | Description                                                                       |
| ------------- | -------------------------- | --------------------------------------------------------------------------------- |
| Install       | `--install`                | Install (or reinstall) available dotfiles.                                        |
| Update        | `-u`, `--update`           | Update from git before installing.                                                |
| Remove        | `-r`, `--remove <modules>` | Remove specific modules (semicolon-separated).                                    |
| Repair        | `-R`, `--repair`           | Remove broken/orphaned managed files, then re-link/regenerate.                    |
| Reset         | `--reset`                  | Remove all managed symlinks and generated files (copied files remain).            |
| Clean         | `--clean [N]`              | Clean backups and reset both log files (see below).                               |
| Clean logs    | `--clean-logs`             | Reset (truncate) both log files.                                                  |
| Clean backups | `--clean-backups [N]`      | Clean backups (see below).                                                        |
| Uninstall     | `--uninstall`              | Remove everything the installer recorded, plus logs, backups, and the repository. |
| List          | `-l`, `--list`             | Show all available modules and their install status.                              |
| Version       | `--version`                | Show version and git information.                                                 |
| Help          | `-h`, `--help`             | Show the full help text.                                                          |

Common options (see `--help` for the complete reference):

- `-n`, `--dry-run` — print planned actions without touching the disk.
- `-y`, `--noconfirm` — skip all confirmation prompts.
- `-I`, `--interactive` — confirm every single operation.
- `-f`, `--force` — overwrite existing files without backup.
- `-i`, `--include <modules>` / `-x`, `--exclude <modules>` — limit or narrow the install to specific modules (semicolon-separated, e.g. `-i zsh;git`).
- `-d`/`-q`, `--log-level <level>`, `--time` — logging controls.

### Maintenance

Backups accumulate one directory per run under `~/.cache/dotfiles/backups/`. To trim them down:

- `--clean-backups N` — remove backup dirs older than `N` days.
- `--clean-backups` (no `N`) — keep only the latest `DOTFILES_MAX_BACKUPS` dirs (default 10; `0` keeps all).
- `--clean [N]` — the same backup cleaning, plus a reset of both log files (`~/.config/dotfiles/logs/`).
- `--clean-logs` — reset the log files without touching backups.

Like the other destructive actions, these prompt before deleting and support `--dry-run` (preview) and `--noconfirm` (skip the prompt).

### Windows notes

The bash installer works in WSL and Git Bash. In Git Bash (or any non-WSL Windows bash) it will pause and offer to hand off to the native PowerShell installer (`dotfiles.ps1`), which is significantly faster and can create real symlinks (with Developer Mode or [Windows Sudo](https://learn.microsoft.com/en-us/windows/advanced-settings/sudo/) enabled). Answer `n` to continue with bash instead.

## Customisation

- **Fork** the repository to drop or replace whole modules — that is the intended way to change _what_ gets installed.
- **Personal values** (usernames, tokens, paths) belong in the `.local` files, not in tracked files. The update step refuses to run over local edits and will point you here.
- **Environment variables:**

| Variable                  | Default                   | Purpose                                                                      |
| ------------------------- | ------------------------- | ---------------------------------------------------------------------------- |
| `DOTFILES_LOG_DIR`        | `~/.config/dotfiles/logs` | Where log files are stored.                                                  |
| `DOTFILES_CACHE_DIR`      | `~/.cache/dotfiles`       | Where backups and the state manifest are stored.                             |
| `DOTFILES_LOG`            | `1`                       | Set to `0` to disable log file writing.                                      |
| `DOTFILES_LOCAL_MODS`     | `0`                       | Set to `1` to allow updates with uncommitted local changes (dev only).       |
| `DOTFILES_AUTORESTART`    | `0`                       | Set to `1` to restart the shell when the script finishes.                    |
| `DOTFILES_MAX_BACKUPS`    | `10`                      | Max backup dirs kept by `--clean`/`--clean-backups` (no `N`). `0` keeps all. |
| `DOTFILES_IGNORE_HANDOFF` | `0`                       | Set to `1` to skip the Windows PowerShell handoff prompt.                    |

## Available modules

Some modules are platform specific. To list available modules and their status:

```bash
bash dotfiles.sh --list
```

Typical output with all modules installed (macOS; Windows adds `pwsh` and `oh-my-posh`, other platforms differ):

```bash
AVAILABLE MODULES

zsh
  ✓ zshrc
  ✓ zsh_options
  ✓ zstyles
  ✓ zimrc
  ✓ p10k.zsh
  ✓ exports
  ✓ paths
  ✓ aliases
  ✓ functions
  ✓ zshrc.toggles
git
  ✓ gitconfig
  ✓ gitconfig.local
  ✓ gitignore
  ✓ gitattributes
  ✓ diff-so-fancy
ssh
  ✓ config
  ✓ allowed_signers
dev
  ✓ cmakepreset.py
  ✓ internal-flags.cmake
  ✓ cmake-format.py
  ✓ clang-format
  ✓ clang-tidy
  ✓ editorconfig
topgrade
  ✓ topgrade.toml
fastfetch
  ✓ config.jsonc
tmux
  ✓ tmux.conf
curl
  ✓ curlrc
wget
  ✓ wgetrc
shellcheck
  ✓ shellcheckrc
claude
  ✓ settings.json
  ✓ plugin.json

  ✓  installed & healthy
  ✗  not installed
  !  installed but broken / stale
```

Some functionality depends on tools installed via your OS package manager (e.g. `fzf`, `eza`, `tmux`, `topgrade`, `oh-my-posh`). If you don't plan to install those dependencies, look through `modules/zsh/` and the relevant module files first and install only what you actually use — missing tools degrade gracefully but the related aliases/completions won't do anything.

## Licensed under the [MIT License](LICENSE)
