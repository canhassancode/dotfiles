#!/bin/bash
# SessionStart nudge: if the Obsidian vault exists and today has no Morning Brief,
# surface a one-line reminder. Silent (no-op) otherwise — non-nag rule.
# Emits JSON: systemMessage (shown to the user) + additionalContext (so the model offers /morning-brief).

JOURNAL="$HOME/Obsidian/Journal"

# Guard: no vault on this machine -> stay silent.
[ -d "$JOURNAL" ] || exit 0

TODAY=$(date +%F)
BRIEF="$JOURNAL/$TODAY-brief.md"

if [ ! -f "$BRIEF" ]; then
  MSG="No Morning Brief for $TODAY yet — run /morning-brief to compile today (it also closes any unclosed prior day)."
  jq -n --arg m "$MSG" '{
    systemMessage: $m,
    hookSpecificOutput: { hookEventName: "SessionStart", additionalContext: $m }
  }'
fi

exit 0
