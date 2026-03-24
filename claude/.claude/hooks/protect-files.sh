#!/bin/bash
# Block edits to sensitive files
INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // empty')

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

PROTECTED_PATTERNS=(
  ".env"
  ".env.local"
  ".env.production"
  "pnpm-lock.yaml"
  "package-lock.json"
  "yarn.lock"
)

for pattern in "${PROTECTED_PATTERNS[@]}"; do
  case "$FILE_PATH" in
    *"$pattern"*)
      echo "Blocked: cannot edit protected file matching '$pattern' — $FILE_PATH" >&2
      exit 2
      ;;
  esac
done

exit 0
