#!/bin/bash

# Stop hook — sends a macOS native notification when Claude finishes or needs input

command -v jq &> /dev/null || exit 0

INPUT=$(cat)
[ -z "$INPUT" ] && exit 0

NOTIFICATION_TYPE=$(printf '%s' "$INPUT" | jq -r '.notification_type // "unknown"' 2>/dev/null)
MESSAGE=$(printf '%s' "$INPUT" | jq -r '.message // "Claude has finished"' 2>/dev/null)

case "$NOTIFICATION_TYPE" in
  "permission_prompt")
    TITLE="🔐 Claude — Permission Request"
    ;;
  "idle_prompt")
    TITLE="⏳ Claude — Waiting for Input"
    ;;
  *)
    TITLE="🤖 Claude Code — Done"
    ;;
esac

osascript - "$MESSAGE" "$TITLE" <<'EOF' 2>/dev/null || true
on run argv
  display notification (item 1 of argv) with title (item 2 of argv) sound name "Submarine"
end run
EOF
