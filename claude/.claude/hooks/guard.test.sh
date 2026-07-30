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

echo
[ "$failures" = 0 ] && echo "all passed" || echo "$failures failed"
exit "$failures"
