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
# eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
# . "/home/hssn/.deno/env"

# aliases
alias 'txn'='tmux new -s'
alias 'txa'='tmux attach -t'
alias 'txk'='tmux kill-session -t'
alias 'txl'='tmux ls'

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

# Gousto profiles
alias db-staging="AWS_PROFILE=EngineerBeta-584614786727 gousto env connect-tunnel staging"
alias artifact-login="AWS_PROFILE=EngineerCodeArtifact-472493421475 aws sso login"
alias beta-login="AWS_PROFILE=EngineerBeta-584614786727 aws sso login"
export artefacts_engineer="AWS_PROFILE=EngineerCodeArtifact-472493421475"

function ca-authenticate() {
  set -x
  export CODEARTIFACT_AUTH_TOKEN=$(aws codeartifact get-authorization-token --domain gousto --domain-owner 472493421475 --query authorizationToken --output text --profile EngineerCodeArtifact-472493421475)
  npm config set //gousto-472493421475.d.codeartifact.eu-west-1.amazonaws.com/npm/proxy-repository/:_authToken=$CODEARTIFACT_AUTH_TOKEN
}

function force-rockets {
  git push origin `git rev-parse --abbrev-ref HEAD`:env-rockets --force --no-verify
}

function getHashEmail {
  echo "$(echo -n "hassanabbas110@outlook.com" | md5)@gousto.info" | pbcopy
}

# Plugins
source $(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh
source $(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
