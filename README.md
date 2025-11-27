# 🎨 Dotfiles

My personal cross-platform dotfiles repository.

## 📁 Structure

```
dotfiles/
├── git/              # Git configuration
│   └── .gitignore   # C++/CMake gitignore patterns
└── zshrc/            # Zsh configuration
    └── .zshrc        # Main zsh config with plugins & profiling
```

## 🚀 Quick Setup

### Linux/Unix

```zsh
# Zsh
ln -s ~/.dotfiles/zshrc/.zshrc ~/.zshrc

# Git (global)
git config --global core.excludesfile ~/.dotfiles/git/.gitignore
```

### Windows

```zsh
# Zsh
ln -s $USERPROFILE/.dotfiles/zshrc/.zshrc $USERPROFILE/.zshrc

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
