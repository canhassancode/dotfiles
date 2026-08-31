export PATH="$HOME/.local/bin:$PATH"

# Path to your Oh My Zsh installation.
export ZSH="$HOME/.oh-my-zsh"

plugins=(git 
    zsh-autosuggestions 
    zsh-syntax-highlighting)

###############
##--ALIASES--##
###############
if [ -f ~/.zsh_aliases ]; then
    source ~/.zsh_aliases
fi 

#################
##--FUNCTIONS--##
#################
if [ -f ~/.zsh_functions ]; then
    source ~/.zsh_functions
fi

# Work Claude Code profile: separate login/history/agents, shared config+skills
claude-work() { CLAUDE_CONFIG_DIR="$HOME/.claude-work" command claude "$@"; }

##############
#--EXPORTS--##
##############
if [ -f ~/.zsh_exports ]; then
    source ~/.zsh_exports
fi

#######################
#--FASTFETCH SCREEN--##
#######################
fastfetch

source $ZSH/oh-my-zsh.sh

####################
#--COCKPIT TOOLS--##
####################
export EDITOR="helix"
export VISUAL="helix"

if command -v fzf >/dev/null; then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --strip-cwd-prefix --exclude .git'
    export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
    export FZF_CTRL_T_OPTS="--preview 'bat --color=always --style=numbers {}'"
    source <(fzf --zsh)
fi

if command -v zoxide >/dev/null; then
    eval "$(zoxide init zsh)"
fi

rgf() {
    local file line
    IFS=: read -r file line _ < <(
        rg --line-number --no-heading --color=always --smart-case "${1:-}" |
            fzf --ansi --delimiter : \
                --preview 'bat --color=always --highlight-line {2} {1}' \
                --preview-window 'up,60%,+{2}/3'
    )
    [ -n "$file" ] && helix "$file:$line"
}

eval "$(starship init zsh)"
