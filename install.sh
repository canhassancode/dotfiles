#!/usr/bin/env bash
set -euo pipefail # Strict mode

export DOTFILES
DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && git rev-parse --show-toplevel)"

echo "🚀 Starting dotfiles installation..."

# Step 1: Install Homebrew & Essentials (only if on macOS)
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "🍏 Detected macOS, running mac.sh..."
    chmod +x "$DOTFILES/scripts/mac.sh"
    source "$DOTFILES/scripts/mac.sh"
fi

# Step 2: Install sensible defaults
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo "🍏 Detected macOS, running defaults.sh..."
    chmod +x "$DOTFILES/scripts/defaults.sh"
    source "$DOTFILES/scripts/defaults.sh"
fi

# Step 3: Stow dotfiles
echo "🔗 Stowing dotfiles..."
cd "$DOTFILES/home"

for dir in *; do
    if [[ -d "$dir" ]]; then
        echo "📂 Stowing $dir..."
        stow --restow --adopt --target="$HOME" "$dir"
    fi
done

echo "✅ Dotfiles installation complete!"
echo "✅ Please ensure you restart your terminal! Or launch Ghostty if installed 🚀."

