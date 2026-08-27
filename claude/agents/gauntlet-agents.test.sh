#!/bin/bash
# Run: ./gauntlet-agents.test.sh   Exit 0 when every case passes.
# The agent definitions are the deterministic tool layer of the gauntlet stages: this
# pins their frontmatter contracts and the prompt rules the workflow relies on.

cd "$(dirname "$0")" || exit 1
failures=0
ok() { echo "PASS $1"; }
ko() { echo "FAIL $1"; failures=$((failures + 1)); }

frontmatter() { sed -n '/^---$/,/^---$/p' "$1"; }
has() { frontmatter "$1" | grep -Eq "^$2:.*\b$3\b" && ok "$1 $2 has $3" || ko "$1 $2 lacks $3"; }
lacks() { frontmatter "$1" | grep -Eq "^$2:.*\b$3\b" && ko "$1 $2 must not have $3" || ok "$1 $2 lacks $3"; }

for stage in specify coder cleaner qa ship; do
  f="gauntlet-$stage.md"
  [ -f "$f" ] && ok "$f exists" || { ko "$f missing"; continue; }
  frontmatter "$f" | grep -q "^name: gauntlet-$stage$" && ok "$f name" || ko "$f name"
  has "$f" disallowedTools Agent
  grep -q 'gh issue view' "$f" && ko "$f mentions gh issue view" || ok "$f never asks for the ticket itself"
  grep -q 'run\.py' "$f" && ko "$f mentions run.py" || ok "$f never sees the runner"
done

has gauntlet-specify.md tools Write;   lacks gauntlet-specify.md tools Edit
has gauntlet-coder.md tools Edit
has gauntlet-cleaner.md tools Edit
lacks gauntlet-qa.md tools Edit;       lacks gauntlet-qa.md tools Write;  has gauntlet-qa.md disallowedTools Write
frontmatter gauntlet-ship.md | grep -q '^tools: Bash$' && ok "ship is Bash only" || ko "ship is not Bash only"

for phrase in "Mysterious Name" "Speculative Generality" "Eliminable structure" "Diff-confined" "Raw values" "The first four are hard"; do
  grep -q "$phrase" gauntlet-cleaner.md && ok "cleaner carries: $phrase" || ko "cleaner lacks: $phrase"
done
grep -q "Mocked subject" gauntlet-cleaner.md && ko "cleaner carries the verification baseline (guards own it)" || ok "cleaner leaves verification to the guards"

echo
[ "$failures" = 0 ] && echo "all passed" || echo "$failures failed"
exit "$failures"
