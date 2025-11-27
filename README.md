# 🎨 Dotfiles

My personal cross-platform dotfiles repository.

## 📁 Structure

```
dotfiles/
├── git/                    # Git configuration
│   └── .gitignore         # C++/CMake gitignore patterns
└── zsh/                    # Zsh configuration
    ├── .zshrc             # Main zsh config with plugins & profiling
    ├── .colours           # Colour configuration
    ├── .commands.ignore   # Commands ignore list
    └── alias.ignore/      # Alias files (apps, coding, edit, git_, etc.)
```

> ⚠️ **Note**: Files/directories ending in `.ignore` are not yet completed for Windows.

## 🚀 Quick Setup

### Linux/Unix

```zsh
# Zsh
ln -s ~/.dotfiles/zsh/.zshrc ~/.zshrc

# Git (global)
git config --global core.excludesfile ~/.dotfiles/git/.gitignore
```

### Windows

```zsh
# Zsh
ln -s $USERPROFILE/.dotfiles/zsh/.zshrc $USERPROFILE/.zshrc

# Git (global)
git config --global core.excludesfile $USERPROFILE/.dotfiles/git/.gitignore
```

## ⚙️ Notes

- **Debug mode**: `export DEBUG_MODE=true`
- **Profiling**: `export ENABLE_PROFILING=true` (logs to `~/.cache/zsh/profiling/`)
- **Aliases**: `~/.alias/*.sh` and `~/.alias/functions/*.sh`
- **Zsh options**: `~/.zsh_options`
- **Zstyles**: `~/.zstyles`

## 🔧 Plugins

- Powerlevel10k (prompt)
- Zim (framework)
- zoxide, fzf, thefuck
- fastfetch (iTerm2 only)
