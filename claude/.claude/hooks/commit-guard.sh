#!/bin/bash
INPUT=$(cat)
cmd=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[ -z "$cmd" ] && exit 0

# A hook receives the whole Bash invocation, not one command, so every check runs
# per shell segment. Checking the raw string treated `git add a && git commit -m x
# && git add b && git commit -m y` — two legal single-line commits — as one commit
# with two -m flags, and blocked a trailer named anywhere in a compound command.
# Splitting has to respect quotes: a message body carries its own newlines, and a
# naive split would strand `Co-Authored-By:` in a segment with no git verb, which
# is the hole this guard exists to close.

strip_heredoc_bodies() {
  awk '
    skip { if ($0 ~ "^[[:space:]]*" term "[[:space:]]*$") skip = 0; next }
    {
      if (match($0, /<<-?[[:space:]]*["\047]?[A-Za-z_][A-Za-z0-9_]*/)) {
        term = substr($0, RSTART, RLENGTH)
        sub(/^<<-?[[:space:]]*["\047]?/, "", term)
        skip = 1
      }
      print
    }'
}

split_on_unquoted_separators() {
  awk '
    BEGIN { RS = "\0" }
    {
      for (i = 1; i <= length($0); i++) {
        c = substr($0, i, 1)
        if (c == "\047" && !dq) sq = !sq
        else if (c == "\"" && !sq) dq = !dq
        if (!sq && !dq) {
          pair = substr($0, i, 2)
          if (pair == "&&" || pair == "||") { printf "\037"; i++; continue }
          if (c == ";" || c == "\n") { printf "\037"; continue }
        }
        printf "%s", c
      }
    }'
}

# Every git verb that can author a message onto an object, not just `commit`.
# `git merge -m` was the original escape hatch: it creates a commit and walks
# past a `commit`-only matcher. `git -c commit.gpgsign=false commit` was the
# second: global flags sit between `git` and the subcommand, so the verb is not
# in the slot a bare matcher looks at. `git -c user.name="Hassan Ali" commit` was
# the third: a quoted flag value holds whitespace, so the flag loop stopped
# mid-match. Collapsing quoted strings first keeps their spaces out of the loop.
authors_a_message() {
  printf '%s' "$1" \
    | sed -E "s/\"[^\"]*\"/Q/g; s/'[^']*'/Q/g" \
    | grep -Eq '\bgit[[:space:]]+(((-c|-C|--git-dir|--work-tree|--namespace|--exec-path)[[:space:]]+[^[:space:]]+|-[^[:space:]]*)[[:space:]]+)*(commit|merge|revert|cherry-pick|rebase|tag)\b'
}

redirect() {
  echo "commit-guard: blocked — $1 Invoke the /commit skill and retry; it produces the required single-line conventional-commit format." >&2
  exit 2
}

# Bodies come off before splitting: prose quoting these patterns inside a heredoc
# would otherwise split into lines that each read as a command of their own.
segments=$(printf '%s' "$cmd" | strip_heredoc_bodies | split_on_unquoted_separators)

while IFS= read -r -d $'\037' segment || [ -n "$segment" ]; do
  authors_a_message "$segment" || continue

  printf '%s' "$segment" | grep -qi 'co-authored-by' \
    && redirect "commit message contains a Co-Authored-By trailer."

  printf '%s' "$segment" | grep -Eq '<<|\$\(cat' \
    && redirect "commit message spans multiple lines (heredoc body)."

  printf '%s' "$segment" | grep -Eq -- '-m\b.*-m\b' \
    && redirect "commit uses multiple -m flags (multi-paragraph body)."
done <<< "$segments"

exit 0
