#!/bin/bash
# Run: ./sleep-guard.test.sh   Exit 0 when every case passes.
# Each over-block and each miss this guard has ever had is a case below; add to
# it rather than re-deriving why a pattern matters.

GUARD="$(dirname "$0")/sleep-guard.sh"
failures=0

check() {
  local desc="$1" expect="$2" payload="$3" out code
  out=$(printf '%s' "$payload" | "$GUARD" 2>&1)
  code=$?
  if [ "$code" = "$expect" ]; then
    echo "PASS ($code) $desc"
  else
    echo "FAIL (got $code want $expect) $desc :: $out"
    failures=$((failures + 1))
  fi
}

run_cmd() {
  check "$1" "$2" "$(jq -n --arg c "$3" '{tool_input:{command:$c}}')"
}

run_bg() {
  check "$1" "$2" "$(jq -n --arg c "$3" '{tool_input:{command:$c,run_in_background:true}}')"
}

# The reported pathology, verbatim. The trailing echo is the whole point: it is
# what defeats a bare-sleep block, so the guard must not depend on the sleep
# being alone.
run_cmd "sleep 250; echo waited" 2 'sleep 250; echo waited'
run_cmd "sleep with && instead of ;" 2 'sleep 250 && echo waited'
run_cmd "bare long sleep" 2 'sleep 300'
run_cmd "minutes suffix" 2 'sleep 4m'
run_cmd "hours suffix" 2 'sleep 1h'
run_cmd "sleep mid-pipeline after a real command" 2 'gh run watch; sleep 60; gh run view'
run_cmd "longest sleep in the command is the one that counts" 2 'sleep 1; sleep 90'
run_cmd "sleep inside a foreground poll loop" 2 'while true; do gh pr checks; sleep 30; done'

# Short sleeps are legitimate — retry backoff, letting a server bind a port.
run_cmd "one-second sleep" 0 'sleep 1'
run_cmd "sub-second sleep" 0 'sleep 0.5'
run_cmd "sleep at exactly the threshold" 0 'sleep 15'
run_cmd "short sleep in a retry loop" 0 'until curl -sf localhost:3000; do sleep 2; done'

# Background is the alternative the block message names, so it must stay open.
run_bg "background until-loop with a long poll interval" 0 'until gh run view --json status --jq .status | grep -q completed; do sleep 30; done'
run_bg "background bare sleep" 0 'sleep 600'

# The word sleep is not the command sleep.
run_cmd "sleep as prose in a commit message" 0 'git commit -m "fix: stop the sleep 250 polling loop"'
run_cmd "sleep as part of another word" 0 'grep -r sleepless /var/log'
run_cmd "a flag that happens to end in sleep" 0 'systemctl suspend-then-hibernate --no-sleep 300'

# Malformed payloads fail open rather than bricking every Bash call.
check "empty payload" 0 ''
check "no command field" 0 '{"tool_input":{}}'

if [ "$failures" -eq 0 ]; then
  echo "all cases passed"
  exit 0
fi
echo "$failures failing case(s)"
exit 1
