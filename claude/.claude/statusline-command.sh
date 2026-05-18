#!/usr/bin/env bash

# Catppuccin Mocha palette (ANSI 24-bit colours)
RED="\033[38;2;243;139;168m"
YELLOW="\033[38;2;249;226;175m"
SAPPHIRE="\033[38;2;116;199;236m"
OVERLAY0="\033[38;2;108;112;134m"
RESET="\033[0m"

input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name // empty')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // 0')
total_in=$(echo "$input" | jq -r '.context_window.total_input_tokens // 0')

fmt_tokens() {
  local n="$1"
  if [ "$n" -ge 1000 ] 2>/dev/null; then
    printf "%.1fk" "$(echo "$n / 1000" | bc -l)"
  else
    echo "$n"
  fi
}

used_int=$(printf "%.0f" "$used_pct")
if [ "$used_int" -gt 10 ]; then
  colour="$RED"
else
  colour="$YELLOW"
fi
printf "${colour}$(fmt_tokens "$total_in")${RESET} ${OVERLAY0}(${used_int}%%)${RESET}"

if [ -n "$model" ]; then
  printf " ${OVERLAY0}•${RESET} ${SAPPHIRE}[ ${model} ]${RESET}"
fi
