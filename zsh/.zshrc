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
export PNPM_HOME="/home/hssn/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac

# brew and deno
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
. "/home/hssn/.deno/env"

# Keep this at the bottom
plugins=(git)
source $ZSH/oh-my-zsh.sh

# Theme customisation below Source
prompt_context() {
  if [[ "$USER" != "$DEFAULT_USER" || -n "$SSH_CLIENT" ]]; then
    # prompt_segment yellow default "⚔️ %F{black}$USER%f"
    prompt_segment "#1e1e2e" "#cdd6f4" "⚔️ $USER" 
    prompt_segment white default "%F{black}%*%f"
    # prompt_segment "#1e1e2e" "#cdd6f4" "%*"
  fi
}
