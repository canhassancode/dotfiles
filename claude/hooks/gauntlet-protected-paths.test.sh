#!/bin/bash
# Run: ./gauntlet-protected-paths.test.sh   Exit 0 when every case passes.
# The gate asks (raises a permission prompt) only for a SUBAGENT edit of a protected
# ruler file in a gauntlet-enabled repo; everything else is allowed silently. Each case
# builds a throwaway repo and passes an explicit cwd, so the suite is location-independent.

GATE="$(cd "$(dirname "$0")" && pwd)/gauntlet-protected-paths.sh"
failures=0

# desc, expected-decision (ask|allow), payload-json.
check() {
  local desc="$1" expect="$2" payload="$3" out decision
  out=$(printf '%s' "$payload" | "$GATE" 2>/dev/null)
  decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null)
  [ -z "$decision" ] && decision="allow"
  if [ "$decision" = "$expect" ]; then
    echo "PASS ($decision) $desc"
  else
    echo "FAIL (got $decision want $expect) $desc :: $out"
    failures=$((failures + 1))
  fi
}

new_repo() {
  (
    cd "$1" || exit 1
    git init -q
    git config user.email t@t.test && git config user.name test
    git config commit.gpgsign false
    git commit -q --allow-empty -m init
  ) >/dev/null 2>&1
}

write_config() {
  mkdir -p "$1/.gauntlet"
  jq -n --argjson pp "$2" '{build: "true", coverage: [], protectedPaths: $pp}' > "$1/.gauntlet/config.json"
}

DEFAULT='["jest.config.*","vitest.config.*","tsconfig*.json","package.json"]'

payload() { # cwd, file, [agent_type], [tool]
  jq -n --arg cwd "$1" --arg f "$2" --arg a "${3:-}" --arg t "${4:-Edit}" \
    '{cwd:$cwd, tool_name:$t, tool_input:{file_path:$f}} + (if $a=="" then {} else {agent_id:"sub_1", agent_type:$a} end)'
}

# --- gauntlet-enabled repo, default protected set ---
repo=$(mktemp -d); new_repo "$repo"; write_config "$repo" "$DEFAULT"

check "subagent editing jest.config.cjs asks" ask \
  "$(payload "$repo" "$repo/jest.config.cjs" gauntlet-coder)"
check "subagent editing tsconfig.json asks" ask \
  "$(payload "$repo" "$repo/tsconfig.json" gauntlet-coder)"
check "subagent editing package.json asks" ask \
  "$(payload "$repo" "$repo/package.json" gauntlet-coder)"
check "subagent editing a nested vitest.config.ts asks" ask \
  "$(payload "$repo" "$repo/packages/api/vitest.config.ts" gauntlet-coder)"

check "subagent editing ordinary source is allowed" allow \
  "$(payload "$repo" "$repo/src/refreshCoordinator.ts" gauntlet-coder)"
check "review stage writing its verdict is allowed" allow \
  "$(payload "$repo" "$repo/.gauntlet/verdict-abc123.json" gauntlet-qa Write)"

check "a human edit of jest.config (no agent) is not nagged" allow \
  "$(payload "$repo" "$repo/jest.config.cjs")"
check "a non-gauntlet subagent editing package.json is not nagged" allow \
  "$(payload "$repo" "$repo/package.json" code-reviewer)"
check "a subagent with an id but no agent_type is not nagged" allow \
  "$(jq -n --arg cwd "$repo" --arg f "$repo/package.json" '{cwd:$cwd, tool_name:"Edit", agent_id:"sub_1", tool_input:{file_path:$f}}')"
check "a non-file tool is allowed" allow \
  "$(jq -n --arg cwd "$repo" '{cwd:$cwd, tool_name:"Bash", agent_id:"sub_1", agent_type:"gauntlet-coder", tool_input:{command:"ls"}}')"

# --- repo WITHOUT a gauntlet config: never fires ---
plain=$(mktemp -d); new_repo "$plain"
check "no .gauntlet/config.json means never ask" allow \
  "$(payload "$plain" "$plain/jest.config.cjs" gauntlet-coder)"

# --- custom protectedPaths are honoured ---
custom=$(mktemp -d); new_repo "$custom"; write_config "$custom" '["webpack.config.js"]'
check "custom protected path asks" ask \
  "$(payload "$custom" "$custom/webpack.config.js" gauntlet-coder)"
check "a path outside the custom set is allowed" allow \
  "$(payload "$custom" "$custom/jest.config.cjs" gauntlet-coder)"

echo
[ "$failures" = 0 ] && echo "all passed" || echo "$failures failed"
exit "$failures"
