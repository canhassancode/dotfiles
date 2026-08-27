#!/bin/bash
# PreToolUse ask-gate — when a gauntlet stage subagent edits a protected "measurement
# apparatus" file (jest/vitest config, tsconfig, package.json), raise an interactive
# permission prompt so the human ratifies that single isolated change and the run
# continues — instead of a deterministic guard blocking the whole run and discarding it.
#
# Contract: prints a PreToolUse JSON decision of "ask" to pause the run on the standard
# permission prompt ("Approve to let the subagent continue"); silent exit 0 (allow)
# otherwise. An "ask" rule falls through to the prompt even in acceptEdits/bypass mode,
# which is why a workflow stage's auto-approved edit still stops here.
#
# Fires only for a GAUNTLET STAGE edit (agent_type gauntlet-*) in a gauntlet-enabled repo
# (one with .gauntlet/config.json), so a human editing config by hand — or any other
# subagent — is never nagged, and no effect at all in a repo the gauntlet does not run in. The protected set is the repo's
# tracked ruler — deliberately NOT .gauntlet/** (harness-internal, and the review stage
# legitimately writes its verdict there).

INPUT=$(cat)

tool=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
case "$tool" in Edit | Write | MultiEdit) ;; *) exit 0 ;; esac

agent=$(printf '%s' "$INPUT" | jq -r '.agent_type // empty' 2>/dev/null)
case "$agent" in gauntlet-*) ;; *) exit 0 ;; esac

file=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[ -z "$file" ] && exit 0

dir=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)
[ -z "$dir" ] && dir="$PWD"
root=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)
[ -z "$root" ] && exit 0

config="$root/.gauntlet/config.json"
[ -f "$config" ] || exit 0

hit=$(python3 - "$config" "$root" "$file" <<'PY'
import fnmatch, json, sys
from pathlib import Path

DEFAULT_PROTECTED = ["jest.config.*", "vitest.config.*", "tsconfig*.json", "package.json"]
config_path, root, target = sys.argv[1], sys.argv[2], sys.argv[3]
patterns = json.loads(Path(config_path).read_text()).get("protectedPaths", DEFAULT_PROTECTED)

candidate = Path(target)
if not candidate.is_absolute():
    candidate = Path(root) / candidate
try:
    rel = str(candidate.resolve().relative_to(Path(root).resolve()))
except ValueError:
    rel = target
name = candidate.name
print("1" if any(fnmatch.fnmatch(rel, p) or fnmatch.fnmatch(name, p) for p in patterns) else "")
PY
)
[ -z "$hit" ] && exit 0

reason="gauntlet: stage ${agent} is editing a protected measurement file ($(basename "$file")). Approve only if this is a legitimate, minimal fix to how correctness is measured — it will ride this stage's commit. Esc to deny and keep the ruler intact."
jq -n --arg r "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "ask", permissionDecisionReason: $r}}'
exit 0
