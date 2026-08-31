#!/bin/bash
# PreToolUse deny — the gauntlet QA stage must prove the ticket's criteria against the
# running system without seeing the tests the pipeline wrote, so it cannot inherit the
# specify stage's assumptions. Denies Read/Grep/Glob/Bash access to test files for
# agent_type gauntlet-qa only; every other agent, and the human, is untouched.

INPUT=$(cat)

agent=$(printf '%s' "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null)
[ "$agent" = "gauntlet-qa" ] || exit 0

tool=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
case "$tool" in
  Read | Grep | Glob) target=$(printf '%s' "$INPUT" | jq -r '.tool_input | [.file_path, .path, .pattern] | map(select(. != null)) | join(" ")' 2>/dev/null) ;;
  Bash) target=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null) ;;
  *) exit 0 ;;
esac

TEST_FILE='(\.(spec|test)\.[a-z]+|(^|/)test_[^/ ]*\.py|(^|/)tests?/|\*\*/\*\.(spec|test))'
printf '%s' "$target" | grep -Eq "$TEST_FILE" || exit 0

reason="gauntlet-qa works from the ticket's acceptance criteria and the served system only — test files are off limits so QA cannot inherit the specify stage's assumptions."
jq -n --arg r "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
exit 0
