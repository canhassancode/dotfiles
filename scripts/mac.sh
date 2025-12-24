#!/usr/bin/env bash
set -euo pipefail # strict mode

if [[ "$OSTYPE" != "darwin"* ]]; then
  return
fi

# Setup homebrew
if [[ -n ${1:-} ]]; then # Check if homebrew is required. First install only
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

# Setup shell
brew install zsh
brew install git
brew install pyenv
brew install node
brew install stow
brew install neovim
brew install tmux
brew install awscli
brew install awsume

# Cask installs
# Disable strict mode before installing casks
set +e

# Cask installs (will continue even if there's an error)
brew install --cask visual-studio-code
brew install --cask cursor
brew install --cask slack
brew install --cask chatgpt
brew install --cask ghostty
brew install --cask google-chrome
brew install --cask claude
brew install --cask discord
brew install --cask tailscale
brew install --cask docker
brew install --cask obsidian
brew install --cask nordpass
brew install --cask localsend
brew install --cask raycast

# Setup PNPM
npm install -g pnpm

# Re-enable strict mode
set -euo pipefail
