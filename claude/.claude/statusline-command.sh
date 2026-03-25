#!/usr/bin/env bash

# Catppuccin Mocha palette (ANSI 24-bit colours)
RED="\033[38;2;243;139;168m"
PEACH="\033[38;2;250;179;135m"
YELLOW="\033[38;2;249;226;175m"
GREEN="\033[38;2;166;227;161m"
TEAL="\033[38;2;148;226;213m"
SAPPHIRE="\033[38;2;116;199;236m"
MAUVE="\033[38;2;203;166;247m"
OVERLAY0="\033[38;2;108;112;134m"
OVERLAY1="\033[38;2;127;132;156m"
RESET="\033[0m"

input=$(cat)

# Shell context
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd')
dir=$(basename "$cwd")

# Git context
git_branch=""
git_status_str=""
if git -C "$cwd" rev-parse --git-dir --no-optional-locks > /dev/null 2>&1; then
  git_branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null || git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
  git_dirty=$(git -C "$cwd" --no-optional-locks status --porcelain 2>/dev/null)
  if [ -n "$git_dirty" ]; then
    git_status_str="*"
  fi
fi

# Claude context
model=$(echo "$input" | jq -r '.model.display_name // empty')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
total_in=$(echo "$input" | jq -r '.context_window.total_input_tokens // empty')
total_out=$(echo "$input" | jq -r '.context_window.total_output_tokens // empty')
vim_mode=$(echo "$input" | jq -r '.vim.mode // empty')
rate_5h=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
rate_7d=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')

build_bar() {
  local pct="$1"
  local filled=$(printf "%.0f" "$(echo "$pct * 10 / 100" | bc -l)")
  local empty=$((10 - filled))
  local bar=""
  local i
  for ((i = 0; i < filled; i++)); do bar="${bar}█"; done
  for ((i = 0; i < empty; i++)); do bar="${bar}░"; done
  echo "$bar"
}

fmt_tokens() {
  local n="$1"
  if [ "$n" -ge 1000 ] 2>/dev/null; then
    printf "%.1fk" "$(echo "$n / 1000" | bc -l)"
  else
    echo "$n"
  fi
}

# Left: model
if [ -n "$model" ]; then
  printf "${SAPPHIRE} ${model}${RESET}"
fi

if [ -n "$vim_mode" ]; then
  if [ "$vim_mode" = "INSERT" ]; then
    printf " ${GREEN}INSERT${RESET}"
  else
    printf " ${MAUVE}NORMAL${RESET}"
  fi
fi

# Centre: folder and git
printf "  ${PEACH} ${dir}${RESET}"

if [ -n "$git_branch" ]; then
  printf " ${YELLOW} ${git_branch}${git_status_str}${RESET}"
fi

# Right: context bar, tokens, rate limits
if [ -n "$used_pct" ]; then
  used_int=$(printf "%.0f" "$used_pct")
  bar=$(build_bar "$used_pct")
  if [ "$used_int" -ge 80 ]; then
    bar_colour="$RED"
  elif [ "$used_int" -ge 50 ]; then
    bar_colour="$YELLOW"
  else
    bar_colour="$TEAL"
  fi
  printf "  ${OVERLAY1}ctx ${bar_colour}${bar}${OVERLAY1} ${used_int}%%${RESET}"
fi

if [ -n "$total_in" ] && [ -n "$total_out" ]; then
  fmt_in=$(fmt_tokens "$total_in")
  fmt_out=$(fmt_tokens "$total_out")
  printf "  ${OVERLAY0}↑${fmt_in} ↓${fmt_out}${RESET}"
fi

if [ -n "$rate_5h" ] || [ -n "$rate_7d" ]; then
  printf " "
  [ -n "$rate_5h" ] && printf " ${OVERLAY1}session $(printf '%.0f' "$rate_5h")%%${RESET}"
  [ -n "$rate_7d" ] && printf " ${OVERLAY1}weekly $(printf '%.0f' "$rate_7d")%%${RESET}"
fi
