#!/bin/bash
# PreToolUse guard for MCP SQL tools — server-agnostic (matches any
# mcp__<server>__{execute_sql,execute_query,query,explain_query} via the
# regex matcher in settings.json, so no server name is hardcoded).
#
# Policy: auto-approve read-only statements (SELECT / EXPLAIN / SHOW / VALUES,
# and read-only CTEs), prompt for anything that could mutate. EXPLAIN ANALYZE of
# a write still executes the write, so the keyword scan runs regardless of the
# leading verb.
#
# Decision is emitted as PreToolUse permissionDecision JSON: "allow" suppresses
# the prompt, "ask" forces one. Fail-open: when no SQL is found or jq is
# unavailable, exit 0 silently and let the normal permission flow prompt — a
# write is never auto-approved by omission.

INPUT=$(cat)
sql=$(printf '%s' "$INPUT" | jq -r '.tool_input.sql // .tool_input.query // .tool_input.statement // empty' 2>/dev/null)

[ -z "$sql" ] && exit 0

decide() {
  jq -nc --arg d "$1" --arg r "$2" \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:$d,permissionDecisionReason:$r}}' 2>/dev/null
  exit 0
}

# Strip line (--) and block (/* */) comments, flatten to one line for scanning.
scan=$(printf '%s' "$sql" | sed -E 's/--[^\n]*//g; s#/\*[^*]*\*+([^/*][^*]*\*+)*/##g' | tr '\n' ' ')
first=$(printf '%s' "$scan" | grep -oiE '[a-zA-Z]+' | head -1 | tr '[:lower:]' '[:upper:]')

# Word-boundary, case-insensitive — \bUPDATE\b does NOT match column "updated_at".
write_re='\b(INSERT|UPDATE|DELETE|DROP|ALTER|CREATE|TRUNCATE|GRANT|REVOKE|MERGE|REPLACE|UPSERT|CALL|DO|COPY|VACUUM|REINDEX|REFRESH|COMMENT|LOCK|SET|COMMIT|ROLLBACK|SAVEPOINT|NOTIFY)\b'

case "$first" in
  SELECT|EXPLAIN|SHOW|VALUES|WITH|TABLE)
    if printf '%s' "$scan" | grep -Eiq "$write_re"; then
      decide ask "SQL contains a write/DDL keyword — confirm before running"
    fi
    decide allow "read-only query"
    ;;
  *)
    decide ask "non-SELECT statement — confirm before running"
    ;;
esac
