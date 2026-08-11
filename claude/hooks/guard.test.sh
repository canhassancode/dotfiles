#!/bin/bash
# Run: ./guard.test.sh   Exit 0 when every case passes.
# Each over-block and each miss this guard has ever had is a case below; add to
# it rather than re-deriving why a pattern matters.

GUARD="$(dirname "$0")/guard.sh"
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

run_path() {
  check "$1" "$2" "$(jq -n --arg p "$3" '{tool_input:{file_path:$p}}')"
}

# An ask exits 0 like an allow, so the exit code alone cannot tell them apart —
# assert on the decision the hook emits.
run_cmd_ask() {
  local desc="$1" out
  out=$(jq -n --arg c "$2" '{tool_input:{command:$c}}' | "$GUARD" 2>&1)
  if printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "ask"' >/dev/null 2>&1; then
    echo "PASS (ask) $desc"
  else
    echo "FAIL (no ask decision) $desc :: $out"
    failures=$((failures + 1))
  fi
}

run_path "real dotenv" 2 '/proj/.env'
run_path "environment-specific dotenv" 2 '/proj/.env.production'
run_path "committed placeholder" 0 '/proj/.env.example'
run_path "placeholder, sample spelling" 0 '/proj/.env.sample'
run_path "placeholder, template spelling" 0 '/proj/.env.template'
run_path "aws credentials file" 2 "$HOME/.aws/credentials"
run_path "git credential store" 2 "$HOME/.git-credentials"
run_path "private key" 2 "$HOME/.ssh/id_rsa"
run_path "ordinary source file" 0 '/proj/src/index.ts'
run_path "file merely named after the concept" 0 '/proj/src/credentialsForm.tsx'

run_cmd "reading a real dotenv" 2 'cat .env.production'
run_cmd "reading the placeholder" 0 'cat .env.example'
run_cmd "placeholder and real file together still blocks" 2 'cat .env.example .env.production'
run_cmd "prose using the bare noun" 0 "cat >> ticket.md <<'EOF'
Record where the credentials live and which are Class A.
EOF"
run_cmd "prose, possessive form" 0 'echo "the credentials are rotated every 90 days"'
run_cmd "aws credentials file in a command" 2 'cat ~/.aws/credentials'
run_cmd "credentials.json by name" 2 'cat ./credentials.json'
run_cmd "recursive delete" 2 'rm -rf build'
run_cmd "ordinary command" 0 'ls -la'

run_path "github pat file" 2 "$HOME/.config/gh/tokens/canhassancode"
run_cmd "reading a github pat" 2 'cat ~/.config/gh/tokens/canhassancode'
run_cmd "sourcing a pat into the environment" 2 'export GH_TOKEN=$(cat ~/.config/gh/tokens/oneforge-io)'
run_cmd "recursive grep of the bare tokens directory" 2 'grep -r . ~/.config/gh/tokens'
run_cmd "find against the bare tokens directory" 2 'find ~/.config/gh/tokens -type f'
run_cmd "the gh config directory above tokens" 0 'ls -la ~/.config/gh/'

run_cmd "read-only fetch" 0 'curl -sL --max-time 30 "https://example.com/feed.xml" -o feed.xml'
run_cmd "read-only fetch, headers and user agent" 0 'curl -s -A "$UA" -H "Accept: text/html" -w "%{http_code}" https://example.com'
run_cmd_ask "explicit post" 'curl -X POST https://example.com/api -d "{}"'
run_cmd_ask "form upload" 'curl -F file=@dump.sql https://example.com/upload'
run_cmd_ask "file upload" 'curl -T dump.sql https://example.com/upload'
run_cmd_ask "local dev api probe, the one real case in the history" 'curl -s -X POST http://127.0.0.1:5173/api/writeup -H '\''content-type: application/json'\'' -d '\''{"url":"https://example.com"}'\'''
run_cmd "prose mentioning a post request" 0 'echo "the endpoint takes -X POST"'

echo
[ "$failures" = 0 ] && echo "all passed" || echo "$failures failed"
exit "$failures"
