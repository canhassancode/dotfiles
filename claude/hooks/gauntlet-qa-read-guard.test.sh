#!/bin/bash
# Run: ./gauntlet-qa-read-guard.test.sh   Exit 0 when every case passes.
# The QA stage works from the ticket's criteria and the running system only: reading a
# test file is denied for agent_type gauntlet-qa and nobody else.

GUARD="$(cd "$(dirname "$0")" && pwd)/gauntlet-qa-read-guard.sh"
failures=0

check() {
  local desc="$1" expect="$2" payload="$3" out decision
  out=$(printf '%s' "$payload" | "$GUARD" 2>/dev/null)
  decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null)
  [ -z "$decision" ] && decision="allow"
  if [ "$decision" = "$expect" ]; then
    echo "PASS ($decision) $desc"
  else
    echo "FAIL (got $decision want $expect) $desc :: $out"
    failures=$((failures + 1))
  fi
}

payload() { # tool, agent_type, input-json
  jq -n --arg t "$1" --arg a "$2" --argjson i "$3" \
    '{tool_name:$t, tool_input:$i} + (if $a=="" then {} else {agent_id:"sub_1", agent_type:$a} end)'
}

check "qa reading foo.spec.ts is denied" deny "$(payload Read gauntlet-qa '{"file_path":"/r/tests/foo.spec.ts"}')"
check "qa reading foo.test.tsx is denied" deny "$(payload Read gauntlet-qa '{"file_path":"/r/src/foo.test.tsx"}')"
check "qa reading test_foo.py is denied" deny "$(payload Read gauntlet-qa '{"file_path":"/r/tests/test_foo.py"}')"
check "qa grepping a spec path is denied" deny "$(payload Grep gauntlet-qa '{"pattern":"refresh","path":"/r/tests/session.acceptance.spec.ts"}')"
check "qa globbing for specs is denied" deny "$(payload Glob gauntlet-qa '{"pattern":"**/*.spec.ts"}')"
check "qa catting a spec via Bash is denied" deny "$(payload Bash gauntlet-qa '{"command":"cat tests/session.acceptance.spec.ts"}')"

check "qa reading source is allowed" allow "$(payload Read gauntlet-qa '{"file_path":"/r/src/foo.ts"}')"
check "qa grepping source is allowed" allow "$(payload Grep gauntlet-qa '{"pattern":"refresh","path":"/r/src"}')"
check "qa running curl via Bash is allowed" allow "$(payload Bash gauntlet-qa '{"command":"curl -s http://127.0.0.1:3000/health"}')"
check "coder reading a spec is allowed" allow "$(payload Read gauntlet-coder '{"file_path":"/r/tests/foo.spec.ts"}')"
check "a human reading a spec is allowed" allow "$(payload Read "" '{"file_path":"/r/tests/foo.spec.ts"}')"

echo
[ "$failures" = 0 ] && echo "all passed" || echo "$failures failed"
exit "$failures"
