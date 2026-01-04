# 🚀 dotfiles

## 📚 Overview
- Installs brew, git, necessary apps.
- Creates sensible defaults.
- Uses [GNU Stow](https://medium.com/quick-programming/managing-dotfiles-with-gnu-stow-9b04c155ebad) to throw necessary default configs in the correct location.

## 💻 How to install dotfiles
The setup for this should be fairly simple as the scripts automate a lot of the process:

```shell
# Step 1: 🚀 Install GNU Stow
# Step 2: Run the following
stow -t ~ hyprland git etc.
```
