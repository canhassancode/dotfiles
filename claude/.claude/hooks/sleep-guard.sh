#!/bin/bash
# PreToolUse guard — stops agents polling by sleeping in the foreground.
#
# The harness blocks a *bare* foreground sleep and points at Monitor instead.
# Agents that need to wait therefore emit the shortest string that clears the
# block: `sleep 250; echo waited`. The trailing echo is not doing any work — it
# exists solely so the command is no longer a bare sleep. Every poll is a fresh
# Bash call and so a fresh login shell, so a handful of agents each waiting on
# something produces shells faster than they retire.
#
# This closes that hole at the command level rather than the token level: any
# sleep at a command position over the threshold is blocked however it is
# dressed up. Short sleeps stay legal — retry backoff is a real use.
#
# Background Bash is exempt. `run_in_background` with an until-loop is the
# alternative the message names, and it necessarily contains a sleep; blocking
# it would leave an agent with nowhere to go, which is what taught the workaround
# in the first place. Monitor is a different tool name and never reaches here.
#
# Contract: exit 2 blocks the tool call and surfaces stderr to Claude; exit 0
# allows it. Parse failures fail OPEN, matching guard.sh.
#
# Known limitation: a sleep written into a heredoc — a script being authored
# rather than run — sits at a command position and will be blocked. Rare enough
# to accept, and visible when it happens.

INPUT=$(cat)

cmd=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
background=$(printf '%s' "$INPUT" | jq -r '.tool_input.run_in_background // false' 2>/dev/null)

[ -z "$cmd" ] && exit 0
[ "$background" = "true" ] && exit 0

THRESHOLD_SECONDS=15

# Command position: start of string, or after a separator. Without this anchor
# the word `sleep` in prose the command happens to carry would match.
longest=$(printf '%s' "$cmd" \
  | grep -oE '(^|[;&|(]|&&|\|\||[[:space:]]do[[:space:]]|[[:space:]]then[[:space:]])[[:space:]]*sleep[[:space:]]+[0-9]+(\.[0-9]+)?[smhd]?' \
  | grep -oE '[0-9]+(\.[0-9]+)?[smhd]?$' \
  | awk '
      {
        unit = "s"
        n = $0
        if (match($0, /[smhd]$/)) {
          unit = substr($0, RSTART, 1)
          n = substr($0, 1, RSTART - 1)
        }
        mult = 1
        if (unit == "m") mult = 60
        if (unit == "h") mult = 3600
        if (unit == "d") mult = 86400
        secs = n * mult
        if (secs > max) max = secs
      }
      END { printf "%d", max }
    ')

[ -z "$longest" ] && exit 0
[ "$longest" -le "$THRESHOLD_SECONDS" ] && exit 0

cat >&2 <<EOF
sleep-guard: blocked — foreground sleep of ${longest}s (limit ${THRESHOLD_SECONDS}s).

A foreground sleep is a shell held open doing nothing, and polling this way
spawns one per wait. Wait on the condition instead of on the clock:

  Bash with run_in_background — one notification when the condition is true:
    until <condition>; do sleep 5; done

  Monitor — one notification per occurrence, for a stream of events.

If the wait is genuinely unavoidable and unconditional, say so and ask.
EOF
exit 2
