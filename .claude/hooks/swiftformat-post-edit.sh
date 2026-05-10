#!/bin/bash

# PostToolUse hook — auto-formats Swift files immediately after Edit/Write

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/../logs/swiftformat.log"

mkdir -p "$(dirname "$LOG_FILE")"

EVENT_DATA=$(cat)

TOOL_NAME=$(echo "$EVENT_DATA" | jq -r '.tool // "unknown"')
FILE_PATH=""

case "$TOOL_NAME" in
  Edit|Write)
    FILE_PATH=$(echo "$EVENT_DATA" | jq -r '.parameters.file_path // empty')
    ;;
  *)
    exit 0
    ;;
esac

[[ "$FILE_PATH" =~ \.swift$ ]] || exit 0
[ -f "$FILE_PATH" ] || exit 0
command -v swiftformat &> /dev/null || exit 0

if swiftformat "$FILE_PATH" --quiet 2>/dev/null; then
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] Formatted: $FILE_PATH" >> "$LOG_FILE"
fi

exit 0
