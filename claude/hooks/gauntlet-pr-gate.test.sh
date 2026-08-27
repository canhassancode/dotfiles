#!/bin/bash
# Run: ./gauntlet-pr-gate.test.sh   Exit 0 when every case passes.
# The gate resolves the target repo from the payload cwd (as Claude sends it) plus
# any inline `cd`/`pushd` in the command — not from the hook's own PWD. Each case
# builds a throwaway repo and passes an explicit cwd, so the suite is independent of
# where it is invoked.

GATE="$(cd "$(dirname "$0")" && pwd)/gauntlet-pr-gate.sh"
failures=0

# desc, expected-exit, payload-cwd, command.
check() {
  local desc="$1" expect="$2" cwd="$3" cmd="$4" out code
  out=$(jq -n --arg c "$cmd" --arg d "$cwd" '{cwd:$d, tool_input:{command:$c}}' | "$GATE" 2>&1)
  code=$?
  if [ "$code" = "$expect" ]; then
    echo "PASS ($code) $desc"
  else
    echo "FAIL (got $code want $expect) $desc :: $out"
    failures=$((failures + 1))
  fi
}

new_repo() {
  local dir="$1"
  (
    cd "$dir" || exit 1
    git init -q
    git config user.email t@t.test && git config user.name test
    git config commit.gpgsign false
    git commit -q --allow-empty -m init
  ) >/dev/null 2>&1
}

write_verdict() {
  local dir="$1" sha="$2" clean="$3"
  mkdir -p "$dir/.gauntlet"
  jq -n --arg sha "$sha" --argjson clean "$clean" '{sha:$sha, clean:$clean}' \
    > "$dir/.gauntlet/verdict-$sha.json"
}

PR='gh pr create --fill'

# --- cwd IS the repo (session launched inside it) ---
repo=$(mktemp -d); new_repo "$repo"; sha=$(git -C "$repo" rev-parse HEAD)
check "no verdict blocks the PR" 2 "$repo" "$PR"

repo=$(mktemp -d); new_repo "$repo"; sha=$(git -C "$repo" rev-parse HEAD)
write_verdict "$repo" "$sha" true
check "clean verdict for HEAD allows the PR" 0 "$repo" "$PR"

repo=$(mktemp -d); new_repo "$repo"; sha=$(git -C "$repo" rev-parse HEAD)
write_verdict "$repo" "$sha" false
check "an unclean verdict blocks" 2 "$repo" "$PR"

repo=$(mktemp -d); new_repo "$repo"; sha=$(git -C "$repo" rev-parse HEAD)
write_verdict "$repo" "0000000000000000000000000000000000000000" true
check "a verdict for another commit blocks" 2 "$repo" "$PR"

repo=$(mktemp -d); new_repo "$repo"; sha=$(git -C "$repo" rev-parse HEAD)
mkdir -p "$repo/.gauntlet"
jq -n '{sha:"deadbeef", clean:true}' > "$repo/.gauntlet/verdict-$sha.json"
check "verdict whose inner sha mismatches blocks" 2 "$repo" "$PR"

repo=$(mktemp -d); new_repo "$repo"
check "an unrelated command passes" 0 "$repo" 'gh pr list'
check "the phrase quoted in prose passes" 0 "$repo" 'echo "then run gh pr create"'
check "gh pr create chained after && still gates" 2 "$repo" 'git push -u origin HEAD && gh pr create --fill'

# --- cwd is a PARENT above the repo (launched from ~/repos/personal, editing a subrepo) ---
parent=$(mktemp -d)                       # not itself a repo
mkdir -p "$parent/app"; new_repo "$parent/app"; sha=$(git -C "$parent/app" rev-parse HEAD)

check "bare gh pr create from a non-repo parent fails closed" 2 "$parent" "$PR"

check "inline cd into the subrepo, no verdict, still gates" 2 "$parent" 'cd app && gh pr create --fill'

write_verdict "$parent/app" "$sha" true
check "inline cd into the subrepo with a clean verdict allows" 0 "$parent" 'cd app && gh pr create --fill'

# Absolute-path cd resolves too.
check "inline cd with an absolute path resolves" 0 "$parent" "cd $parent/app && gh pr create --fill"

echo
[ "$failures" = 0 ] && echo "all passed" || echo "$failures failed"
exit "$failures"
