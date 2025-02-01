#!/bin/bash
# -----------------------------
# Run from within dotfiles root
# -----------------------------

# Update zsh config
rm zsh/.zshrc
cp ~/.zshrc zsh/

# Update tmux config
rm tmux/.tmux.conf
cp ~/.tmux.conf tmux/

