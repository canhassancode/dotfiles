#!/bin/bash
# PreToolUse guard — the real enforcement layer behind the permission rules.
# Runs on Bash | Read | Edit | Write. Blocks (a) any access to secret-bearing
# paths and (b) destructive shell commands, matched by anchored regex anywhere
# in the command string (robust against rm -fr, mid-pipeline rm -rf, etc.).
#
# Contract: exit 2 blocks the tool call and surfaces stderr to Claude; exit 0
# allows it. Parse failures fail OPEN (exit 0) — a guard that bricks every tool
# call on a malformed payload is worse than one that occasionally misses; the
# static deny rules in settings.json remain as a second layer.

INPUT=$(cat)

cmd=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
path=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // empty' 2>/dev/null)

block() {
  echo "guard.sh: blocked — $1" >&2
  exit 2
}

# Secret-bearing paths: .env files, ssh/aws/gnupg dirs, private keys, credentials.
# Leading/trailing classes include whitespace so it matches both file_path
# arguments (/proj/.env) and shell tokens (cat .env.production).
secret_re='(^|[[:space:]/])\.env($|[[:space:]./])|(^|[[:space:]/])\.netrc($|[[:space:]/])|(^|[[:space:]/])\.(ssh|aws|gnupg)/|\.pem($|[[:space:]])|\.p12($|[[:space:]])|\bid_rsa\b|\bid_ed25519\b|(^|[[:space:]/])credentials($|[[:space:]/.])'

# Lockfiles — mutate via the package manager, never hand-edit.
lock_re='(pnpm-lock\.yaml|package-lock\.json|yarn\.lock)$'

# Destructive shell, matched within a single command segment ([^;&|]* stops the
# match leaking across separators into an unrelated command).
destructive_re='\brm[[:space:]][^;&|]*(-[a-zA-Z]*[rR]|--recursive)|\bgit[[:space:]]+push[^;&|]*(--force|[[:space:]]-f([[:space:]]|$))|\bgit[[:space:]]+reset[[:space:]]+--hard|\bgit[[:space:]]+clean[[:space:]]+(-[a-zA-Z]*f|--force)|\bgit[[:space:]]+filter-branch|\bmkfs\b|\bdd[[:space:]]+if=|>[[:space:]]*/dev/sd|\bchmod[[:space:]]+-R[[:space:]]+777'

if [ -n "$path" ]; then
  printf '%s' "$path" | grep -Eq "$secret_re" && block "secret-bearing path: $path"
  printf '%s' "$path" | grep -Eq "$lock_re" && block "lockfile — edit via the package manager: $path"
fi

if [ -n "$cmd" ]; then
  printf '%s' "$cmd" | grep -Eq "$secret_re" && block "command touches a secret-bearing path"
  printf '%s' "$cmd" | grep -Eq "$destructive_re" && block "destructive command pattern"
fi

exit 0
