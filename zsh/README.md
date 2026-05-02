# zsh

Personal `zsh` config. Runs on top of [oh-my-zsh](https://ohmyz.sh/) with `zsh-autosuggestions` and `zsh-syntax-highlighting` plugins, [starship](https://starship.rs) prompt, and [fastfetch](https://github.com/fastfetch-cli/fastfetch) splash on shell start.

## Install

```sh
cd ~/dotfiles && stow zsh
```

## Prerequisites

```sh
brew install starship fastfetch
```

Install oh-my-zsh:

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
```

Install the two plugins (clones into the oh-my-zsh custom directory):

```sh
git clone --depth 1 https://github.com/zsh-users/zsh-autosuggestions \
  "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions"

git clone --depth 1 https://github.com/zsh-users/zsh-syntax-highlighting \
  "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting"
```

## Layout

| File | Purpose |
|---|---|
| `.zshrc` | Plugins, prompt, PATH, sources optional `~/.zsh_aliases`, `~/.zsh_functions`, `~/.zsh_exports` if present |

## Notes

- Adds `~/.local/bin` to `$PATH` — required for [ralph](../ralph/) and other XDG-installed binaries.
- Optional dotfiles `~/.zsh_aliases`, `~/.zsh_functions`, `~/.zsh_exports` are sourced if present. They are not stowed from this repo — keep them machine-local.
