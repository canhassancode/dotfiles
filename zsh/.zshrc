# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"

plugins=(git 
    zsh-autosuggestions 
    zsh-syntax-highlighting)

###############
##--ALIASES--##
###############
alias 'dev'='pnpm run dev'
alias 'sso-oneforge-dev'='aws sso login --profile oneforge-dev && export AWS_PROFILE=oneforge-dev'
alias 'sso-oneforge-prod'='aws sso login --profile oneforge-production && export AWS_PROFILE=oneforge-production'
alias 'sso-hassan-dev'='aws sso login --profile hassan-dev && export AWS_PROFILE=hassan-dev'
alias 'sso-hassan-prod'='aws sso login --profile hassan-production && export AWS_PROFILE=hassan-production'

#######################
#--FASTFETCH SCREEN--##
#######################
fastfetch

source $ZSH/oh-my-zsh.sh
eval "$(starship init zsh)"
