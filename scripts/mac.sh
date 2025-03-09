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
brew install pyenv
brew install node
brew install nvm
brew install git
brew install stow
brew install tmux

# Cask installs
# Disable strict mode before installing casks
set +e

# Cask installs (will continue even if there's an error)
brew install --cask visual-studio-code
brew install --cask cursor
brew install --cask bruno
brew install --cask apidog
brew install --cask slack
brew install --cask chatgpt
brew install --cask ghostty

# Re-enable strict mode
set -euo pipefail
