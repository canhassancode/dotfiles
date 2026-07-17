#!/bin/bash
INPUT=$(cat)
cmd=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[ -z "$cmd" ] && exit 0
printf '%s' "$cmd" | grep -Eq '\bgh[[:space:]]+pr[[:space:]]+create\b' || exit 0

title=$(printf '%s' "$cmd" \
  | grep -oE -- "(--title|[[:space:]]-t)[ =]+('[^']*'|\"[^\"]*\"|[^ ]+)" \
  | head -1 | sed -E "s/(--title|[[:space:]]-t)[ =]+//; s/^['\"]//; s/['\"]$//")

[ -z "$title" ] && exit 0

redirect() {
  echo "pr-guard: blocked — $1 Invoke the /pr skill and retry." >&2
  exit 2
}

printf '%s' "$title" | grep -Eq '^(feat|fix|hotfix|refactor|chore|docs): ' \
  || redirect "PR title lacks a conventional prefix (feat|fix|hotfix|refactor|chore|docs)."

[ "${#title}" -gt 70 ] \
  && redirect "PR title exceeds 70 chars (was ${#title})."

exit 0
