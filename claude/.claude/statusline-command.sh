#!/usr/bin/env bash

# Catppuccin Mocha palette (ANSI 24-bit colours), each with a dimmed variant
YELLOW="\033[38;2;249;226;175m"
YELLOW_DIM="\033[38;2;150;138;117m"
PEACH="\033[38;2;250;179;135m"
PEACH_DIM="\033[38;2;151;112;95m"
RED="\033[38;2;243;139;168m"
RED_DIM="\033[38;2;147;90;113m"
RESET="\033[0m"

input=$(cat)

used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // 0')
total_in=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')

fmt_tokens() {
  local n="$1"
  if [ "$n" -ge 1000 ] 2>/dev/null; then
    local tenths=$((n / 100))
    printf "%d.%dk" "$((tenths / 10))" "$((tenths % 10))"
  else
    echo "$n"
  fi
}

used_int=$(printf "%.0f" "$used_pct")

if [ "$total_in" -ge 150000 ] 2>/dev/null; then
  colour="$RED"
  colour_dim="$RED_DIM"
elif [ "$total_in" -ge 110000 ] 2>/dev/null; then
  colour="$PEACH"
  colour_dim="$PEACH_DIM"
else
  colour="$YELLOW"
  colour_dim="$YELLOW_DIM"
fi

printf "${colour}$(fmt_tokens "$total_in")${RESET} ${colour_dim}(${used_int}%%)${RESET}"
