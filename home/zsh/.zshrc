# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH

# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Theme
ZSH_THEME="agnoster"

# nvm
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# pnpm
export PNPM_HOME="$HOME/.local/share/pnpm/global/bin"
export PATH="$PNPM_HOME:$PATH"

# aliases
alias 'txn'='tmux new -s'
alias 'txa'='tmux attach -t'
alias 'txk'='tmux kill-session -t'
alias 'txl'='tmux ls'
alias 'dev'='pnpm run dev'
alias 'sso-oneforge-dev'='aws sso login --profile oneforge-dev && export AWS_PROFILE=oneforge-dev'
alias 'sso-oneforge-prod'='aws sso login --profile oneforge-production && export AWS_PROFILE=oneforge-production'
alias 'sso-hassan-dev'='aws sso login --profile hassan-dev && export AWS_PROFILE=hassan-dev'
alias 'sso-hassan-prod'='aws sso login --profile hassan-production && export AWS_PROFILE=hassan-production'

# functions
function new_date() {
  local dt="${1:-now}"
  # Use gdate if available (Mac Homebrew), otherwise date (Linux)
  local date_cmd="date"
  if command -v gdate >/dev/null 2>&1; then
    date_cmd="gdate"
  fi
  GIT_COMMITTER_DATE="$($date_cmd -d "$dt")" \
  git commit --amend --date="$($date_cmd -d "$dt")" --no-edit
}

# Android SDK
if [[ "$OSTYPE" == "darwin"* ]]; then
  export ANDROID_HOME=$HOME/Library/Android/sdk
else
  export ANDROID_HOME=$HOME/Android/Sdk
fi
# Only add to PATH if Android SDK exists
if [[ -d "$ANDROID_HOME" ]]; then
  export PATH=$PATH:$ANDROID_HOME/emulator
  export PATH=$PATH:$ANDROID_HOME/platform-tools
fi

# Keep this at the bottom
plugins=(git)
source $ZSH/oh-my-zsh.sh

# Theme customisation below Source
prompt_context() {
  if [[ "$USER" != "$DEFAULT_USER" || -n "$SSH_CLIENT" ]]; then
    prompt_segment "#1e1e2e" "#cdd6f4" "⚔️ $USER" 
    prompt_segment white default "%F{black}%*%f"
  fi
}

# Enable bracketed paste in zsh
autoload -Uz bracketed-paste-magic
zle -N bracketed-paste bracketed-paste-magic
