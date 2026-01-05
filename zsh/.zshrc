# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"

plugins=(git 
    zsh-autosuggestions 
    zsh-syntax-highlighting)

###############
##--ALIASES--##
###############
alias 'dev'='pnpm run dev'
if [ -f ~/.zsh_aliases ]; then
    source ~/.zsh_aliases
fi 

#################
##--FUNCTIONS--##
#################
if [ -f ~/.zsh_functions ]; then
    source ~/.zsh_functions
fi

#######################
#--FASTFETCH SCREEN--##
#######################
fastfetch

source $ZSH/oh-my-zsh.sh
eval "$(starship init zsh)"
