#!/bin/bash
# SessionStart nudge: if the Obsidian vault exists and today has no Morning Brief,
# inject a one-line reminder into context. Silent (no-op) otherwise — non-nag rule.

JOURNAL="$HOME/Obsidian/Journal"

# Guard: no vault on this machine -> stay silent.
[ -d "$JOURNAL" ] || exit 0

TODAY=$(date +%F)
BRIEF="$JOURNAL/$TODAY-brief.md"

if [ ! -f "$BRIEF" ]; then
  echo "No Morning Brief for $TODAY yet — run /morning-brief to compile today (it will also close any unclosed prior day)."
fi

exit 0
