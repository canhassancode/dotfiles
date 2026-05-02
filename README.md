# dotfiles

GNU Stow-managed configuration. Each top-level directory is an independent stowable package.

## Prerequisites

`stow`, `git`, `gh`. Optional per package: `sbx` (for [ralph](ralph/)), `oh-my-zsh` (for `zsh`).

## Installation

```sh
cd ~/dotfiles && stow <package>
```

Stow is idempotent: re-run after a pull to pick up new files.

## Packages

| Package | Stows to | Depends on | Notes |
|---|---|---|---|
| [`claude`](claude/) | `~/.claude/` | Claude Code | Global skills, agents, hooks, CLAUDE.md |
| [`ralph`](ralph/) | `~/.local/bin/ralph`, `~/.config/ralph/` | `sbx`, `gh` | AFK Claude loop |
| [`zsh`](zsh/) | `~/.zshrc` | `oh-my-zsh`, `starship`, `fastfetch` | Adds `~/.local/bin` to `$PATH` |
| `git` | `~/.gitconfig` | — | |
| `nvim` | `~/.config/nvim/` | `nvim` ≥ 0.10 | |
| `tmux` | `~/.tmux.conf` | `tmux` | |
| `kitty`, `ghostty` | `~/.config/<term>/` | terminal of choice | |
| `starship` | `~/.config/starship.toml` | `starship` | |
| `hyprland`, `quickshell`, `waybar` | `~/.config/<tool>/` | Linux only | |
| `yazi` | `~/.config/yazi/` | `yazi` | |

## Bootstrap on a new machine

```sh
brew install stow gh                          # macOS; pacman/apt equivalents on Linux
git clone <this-repo> ~/dotfiles
cd ~/dotfiles
stow zsh git tmux                             # baseline shell
stow claude ralph                             # Claude tooling
```
