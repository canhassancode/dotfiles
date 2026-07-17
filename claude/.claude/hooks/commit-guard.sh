#!/bin/bash
INPUT=$(cat)
cmd=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[ -z "$cmd" ] && exit 0
printf '%s' "$cmd" | grep -Eq '\bgit[[:space:]]+commit\b' || exit 0

redirect() {
  echo "commit-guard: blocked — $1 Invoke the /commit skill and retry; it produces the required single-line conventional-commit format." >&2
  exit 2
}

printf '%s' "$cmd" | grep -qi 'co-authored-by' \
  && redirect "commit message contains a Co-Authored-By trailer."

printf '%s' "$cmd" | grep -Eq '<<|\$\(cat' \
  && redirect "commit message spans multiple lines (heredoc body)."

printf '%s' "$cmd" | grep -Eq -- '-m\b.*-m\b' \
  && redirect "commit uses multiple -m flags (multi-paragraph body)."

exit 0
