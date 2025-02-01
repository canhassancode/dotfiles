#!/bin/bash

# ------------------------------------------
# Run this from within the dotfiles root dir
# ------------------------------------------

# Update and upgrade
sudo apt update && sudo apt upgrade

# Setup zsh
sudo apt install zsh -y
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
rm ~/.zshrc
cp zsh/.zshrc ~/
source ~/.zshrc

# Setup node
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash
nvm install v20.18.0
source ~/.zshrc
node -v # Verify

# Setup pnpm
sudo npm installl -g pnpm
source ~/.zshrc
pnpm -v # Verify

# Setup brew
test -d ~/.linuxbrew && eval "$(~/.linuxbrew/bin/brew shellenv)"
test -d /home/linuxbrew/.linuxbrew && eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
sudo apt-get install build-essential procps curl file git
source ~/.zshrc

# Setup neovim
brew install neovim -y
mkdir ~/.config
git clone https://github.com/canhassancode/neovim "${XDG_CONFIG_HOME:-$HOME/.config}"/nvim
source ~/.zshrc

# Setup tmux
sudo apt install tmux
source ~/.zshrc
