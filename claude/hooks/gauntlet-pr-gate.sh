#!/bin/bash
# PreToolUse gate — blocks `gh pr create` until a clean review verdict exists for
# the exact commit being shipped. The gauntlet's first guard on the live loop: a
# PR may not open until /code-review has passed against this HEAD.
#
# Contract: exit 2 blocks the tool call and surfaces stderr to Claude; exit 0
# allows. PreToolUse hooks fire in every permission mode (including bypass) and for
# subagents, so the gate is unskippable by construction — that is why it lives here
# and not in a git pre-push hook the agent could --no-verify past.
#
# Verdict artefact (written by /code-review on a clean pass, gitignored by the repo):
#   <repo-root>/.gauntlet/verdict-<HEAD-sha>.json  =  {"sha": "<HEAD-sha>", "clean": true}
# The gate passes iff that file exists, its .sha matches the current HEAD, and .clean
# is true. Keying to the SHA means a new commit or an amend invalidates a stale pass —
# you review exactly what you ship.
#
# Fails CLOSED when a `gh pr create` is seen but no git repo resolves: the hook's own
# cwd is the session's launch dir, which is often a parent above the repo (launched
# from ~/repos/personal while editing ~/repos/personal/skills). Resolving from the
# wrong dir and failing open would be a silent bypass, so an unresolved repo blocks
# rather than passes — the opposite of guard.sh's fail-open default, on purpose.

INPUT=$(cat)
cmd=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

[ -z "$cmd" ] && exit 0

# Anchor to command position (start, or after a separator/&&/||) so a real
# invocation and a chained `git push && gh pr create` both match, while the phrase
# quoted inside an echo or a PR body passes.
printf '%s' "$cmd" \
  | grep -Eq '(^|[;&|(]|&&|\|\|)[[:space:]]*(sudo[[:space:]]+)?gh[[:space:]]+pr[[:space:]]+create\b' \
  || exit 0

# Resolve the directory the command actually runs in, not the hook's PWD: start
# from the cwd Claude passes in the payload, then honour a leading `cd`/`pushd` in
# the command (the `cd skills && gh pr create` shape) so the subdir repo wins.
dir=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$dir" ] && dir="$PWD"
cdtarget=$(printf '%s' "$cmd" \
  | grep -oE '^[[:space:]]*(cd|pushd)[[:space:]]+[^;&|]+' \
  | head -1 | sed -E 's/^[[:space:]]*(cd|pushd)[[:space:]]+//; s/[[:space:]]+$//; s/^["'\'']//; s/["'\'']$//')
if [ -n "$cdtarget" ]; then
  case "$cdtarget" in
    /*) dir="$cdtarget" ;;
    "~"*) dir="${cdtarget/#\~/$HOME}" ;;
    *) dir="$dir/$cdtarget" ;;
  esac
fi

root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)
sha=$(git -C "$dir" rev-parse HEAD 2>/dev/null)

block_unresolved() {
  echo "gauntlet-pr-gate: blocked — could not resolve a git repo for this PR (looked in $dir). Run gh pr create from inside the repo so the verdict can be checked." >&2
  exit 2
}
{ [ -z "$root" ] || [ -z "$sha" ]; } && block_unresolved

verdict="$root/.gauntlet/verdict-$sha.json"

block() {
  echo "gauntlet-pr-gate: blocked — $1 Run /code-review against HEAD ($sha); on a clean pass it writes $verdict, then retry." >&2
  exit 2
}

[ -f "$verdict" ] || block "no review verdict for the commit being shipped."

jq -e --arg sha "$sha" '.sha == $sha and .clean == true' "$verdict" >/dev/null 2>&1 \
  || block "the verdict for this commit is not a clean pass."

exit 0
