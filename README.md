# dotfiles

GNU Stow-managed configuration. Each top-level directory is an independent stowable package.

## Prerequisites

`stow`, `git`, `gh`. Optional per package: `oh-my-zsh` (for `zsh`).

## Installation

```sh
cd ~/dotfiles && stow <package>
```

Stow is idempotent: re-run after a pull to pick up new files.

## Packages

| Package | Stows to | Depends on | Notes |
|---|---|---|---|
| [`claude`](claude/) | `~/.claude/` | Claude Code | Global skills, agents, hooks, CLAUDE.md |
| [`pi`](pi/) | `~/.pi/agent/` | pi coding agent | Guardrail extension for interactive pi |
| [`zsh`](zsh/) | `~/.zshrc` | `oh-my-zsh`, `starship`, `fastfetch` | Adds `~/.local/bin` to `$PATH` |
| `git` | `~/.gitconfig` | — | |
| `tmux` | `~/.tmux.conf` | `tmux` | |
| `kitty` | `~/.config/kitty/` | terminal of choice | |
| [`herdr`](herdr/) | `~/.config/herdr/` | `herdr` | `ctrl+s` prefix; runtime sockets/logs stay local. Reload live: `herdr server reload-config` |
| `starship` | `~/.config/starship.toml` | `starship` | |
| `hyprland`, `quickshell`, `waybar` | `~/.config/<tool>/` | Linux only | |
| `yazi` | `~/.config/yazi/` | `yazi` | |

Archived packages live in [`archived/`](archived/) and are no longer stowed: `ghostty`, `nvim`, `ralph`.

## Bootstrap on a new machine

```sh
brew install stow gh                          # macOS; pacman/apt equivalents on Linux
git clone <this-repo> ~/dotfiles
cd ~/dotfiles
stow zsh git tmux                             # baseline shell
stow claude                                   # Claude tooling
```
