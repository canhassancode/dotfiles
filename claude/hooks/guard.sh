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

# Some commands are wrong by default but right often enough that a hard block
# would be a lie. Hand those to the human rather than refusing them, the same
# way main-push-guard does for a push at main.
ask() {
  jq -cn --arg reason "guard.sh: $1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "ask",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

# Secret-bearing paths: .env files, ssh/aws/gnupg dirs, GitHub PATs, private
# keys, credentials.
# Leading/trailing classes include whitespace so it matches both file_path
# arguments (/proj/.env) and shell tokens (cat .env.production). The credentials
# alternative requires an adjacent / . or - so it names a file (.aws/credentials,
# .git-credentials) rather than matching the bare English noun in prose the
# command happens to carry. The gh tokens directory ends in ($|[[:space:]/])
# rather than / so that naming the directory itself blocks too — grep -r and
# find against the bare directory read the tokens just as surely as cat does.
secret_re='(^|[[:space:]/])\.env($|[[:space:]./])|(^|[[:space:]/])\.netrc($|[[:space:]/])|(^|[[:space:]/])\.(ssh|aws|gnupg)/|(^|[[:space:]/])\.config/gh/tokens($|[[:space:]/])|\.pem($|[[:space:]])|\.p12($|[[:space:]])|\bid_rsa\b|\bid_ed25519\b|[/.-]credentials($|[[:space:]/.])'

# .env.example and friends are committed placeholders naming variables and
# holding no values. Stripping the occurrences rather than exempting the whole
# string keeps `cat .env.example .env.production` blocking on the second file.
scrub_placeholders() { sed 's/\.env\.\(example\|sample\|template\)//g'; }

# Lockfiles — mutate via the package manager, never hand-edit.
lock_re='(pnpm-lock\.yaml|package-lock\.json|yarn\.lock)$'

# Destructive shell, matched within a single command segment ([^;&|]* stops the
# match leaking across separators into an unrelated command).
# The rm clause anchors to command position (^, a separator, or a sudo/xargs/-exec
# wrapper) so a quoted `rm -rf` inside prose passes while a real invocation blocks.
# Accepted trade-off: an unlisted wrapper (time rm -rf) slips.
destructive_re='((^|[;&|(]|&&|\|\|)[[:space:]]*((sudo|xargs)[[:space:]]+)*|-exec[[:space:]]+)rm[[:space:]][^;&|]*(-[a-zA-Z]*[rR]|--recursive)|\bgit[[:space:]]+push[^;&|]*(--force|[[:space:]]-f([[:space:]]|$))|\bgit[[:space:]]+reset[[:space:]]+--hard|\bgit[[:space:]]+clean[[:space:]]+(-[a-zA-Z]*f|--force)|\bgit[[:space:]]+filter-branch|\bmkfs\b|\bdd[[:space:]]+if=|>[[:space:]]*/dev/sd|\bchmod[[:space:]]+-R[[:space:]]+777'

# curl that writes rather than reads. A permission rule cannot express this:
# the flags arrive in any order, so any prefix broad enough to match curl -s,
# -sL, -sS and -sI also matches curl -s -X POST. The hook sees the whole
# command, so the distinction lives here and curl itself can be allowed.
curl_write_re='\bcurl\b[^;&|]*([[:space:]]-X[[:space:]]*(POST|PUT|DELETE|PATCH)|[[:space:]]--data|[[:space:]]-d[[:space:]]|[[:space:]]-F[[:space:]]|[[:space:]]-T[[:space:]]|--upload-file)'

# A push landing on main/master. This lives in the Claude-Code guard layer, not a
# git pre-push hook, deliberately: it fires on tool calls only, so it denies the
# agent while leaving Hassan's own terminal free to push when he means to. Two
# independent triggers: (a) the command names main/master as its destination ref;
# (b) the current branch's resolved push target is */main or */master — the CAR-888
# case where an innocent-looking `git push -u origin <branch>` resolves to main via
# push.default=upstream. Resolution failure fails OPEN (the ref check still stands).
push_hits_protected_branch() {
  local cmd="$1" target
  printf '%s' "$cmd" | grep -Eq '\bgit[[:space:]]+push\b[^;&|]*([[:space:]]|:)(main|master)([[:space:]]|:|$)' && return 0
  target=$(git rev-parse --abbrev-ref --symbolic-full-name '@{push}' 2>/dev/null)
  [ -n "$target" ] && printf '%s' "$target" | grep -Eq '(^|/)(main|master)$' && return 0
  return 1
}

if [ -n "$path" ]; then
  printf '%s' "$path" | scrub_placeholders | grep -Eq "$secret_re" && block "secret-bearing path: $path"
  printf '%s' "$path" | grep -Eq "$lock_re" && block "lockfile — edit via the package manager: $path"
fi

if [ -n "$cmd" ]; then
  printf '%s' "$cmd" | scrub_placeholders | grep -Eq "$secret_re" && block "command touches a secret-bearing path"
  printf '%s' "$cmd" | grep -Eq "$destructive_re" && block "destructive command pattern"
  printf '%s' "$cmd" | grep -Eq '(^|[;&|(]|&&|\|\|)[[:space:]]*(sudo[[:space:]]+)?git[[:space:]]+push\b' && push_hits_protected_branch "$cmd" \
    && block "git push landing on main/master — open a PR. Run it yourself if you truly mean to; this guard denies the agent only."
  printf '%s' "$cmd" | grep -Eq "$curl_write_re" && ask "this curl sends a request body rather than reading. Read-only curl runs unprompted; approve only if the write is intended."
fi

exit 0
