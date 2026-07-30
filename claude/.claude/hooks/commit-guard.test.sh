#!/bin/bash
# Run: ./commit-guard.test.sh   Exit 0 when every case passes.
# Each escape hatch this guard has ever missed is a case below; add to it rather
# than re-deriving why a pattern matters.

GUARD="$(dirname "$0")/commit-guard.sh"
failures=0

run() {
  local desc="$1" expect="$2" cmd="$3" out code
  out=$(jq -n --arg c "$cmd" '{tool_input:{command:$c}}' | "$GUARD" 2>&1)
  code=$?
  if [ "$code" = "$expect" ]; then
    echo "PASS ($code) $desc"
  else
    echo "FAIL (got $code want $expect) $desc :: $out"
    failures=$((failures + 1))
  fi
}

run "original bypass: quoted -c value + heredoc body" 2 'git -c user.name="Hassan Ali" -c user.email=h@x.com commit -q -F - <<EOF
feat(cross-reference): thing

Co-Authored-By: Claude <noreply@anthropic.com>
EOF'
run "false positive: prose in heredoc mentioning git -c ... commit" 0 "cat >> observations.md <<'EOF'
- my \`git -c user.name=X commit\` with a heredoc broke the loop, Co-Authored-By trailers too
EOF"
run "clean single-line commit" 0 'git commit -m "feat: add thing"'
run "multiple -m flags" 2 'git commit -m "feat: x" -m "body para"'
run "co-author trailer inline" 2 'git commit -m "feat: x

Co-Authored-By: Claude <noreply@anthropic.com>"'
run "gpgsign escape hatch + trailer" 2 'git -c commit.gpgsign=false commit -m "x
Co-authored-by: y"'
run "quoted -c value, clean message" 0 'git -c user.name="Hassan Ali" commit -m "fix: thing"'
run "non-git command" 0 'ls -la'
run "git status" 0 'git status --short'

run "two legal commits chained" 0 'git add a.txt && git commit -q -m "fix: one" && git add b.txt && git commit -q -m "docs: two"'
run "chained, second carries a trailer" 2 'git add a.txt && git commit -m "fix: one" && git commit -m "docs: two

Co-Authored-By: Claude <noreply@anthropic.com>"'
run "trailer belongs to a non-git command" 0 'echo "Co-Authored-By: someone" >> notes.md && git commit -m "docs: note"'
run "semicolon inside the message, not a separator" 0 'git commit -m "fix: handle a; then b"'
run "genuine multi-paragraph body still blocked" 2 'git add a.txt && git commit -m "feat: x" -m "why it happened"'
run "semicolon-separated commits" 0 'git commit -m "fix: one" ; git commit -m "fix: two"'
run "newline-separated commits" 0 'git commit -m "fix: one"
git commit -m "fix: two"'
run "heredoc prose ignored after splitting" 0 "cat >> observations.md <<'EOF'
- \`git -c user.name=X commit\` broke the loop; Co-Authored-By trailers too
- second line mentioning git commit -m a -m b as well
EOF"

echo
[ "$failures" = 0 ] && echo "all passed" || echo "$failures failed"
exit "$failures"
