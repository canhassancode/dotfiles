#!/usr/bin/env bash
set -euo pipefail # strict mode

if [[ "$OSTYPE" != "darwin"* ]]; then
  return
fi

# Sensible defaults
if [[ -n ${1:-} ]]; then # Checks if ohmyzsh is required
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

# Disable strict mode before installing casks
set +e

# Tmux Plugin Manager
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

# Nerd font (change if necessary)
brew install --cask font-jetbrains-mono
brew install --cask font-jetbrains-mono-nerd-font

# Re-enable strict mode
set -euo pipefail

