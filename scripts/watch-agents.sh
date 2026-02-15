#!/bin/bash
# Refreshes agent status every 5 seconds
# Looks for .agent-status.md in CWD first, falls back to global

while true; do
  clear
  # Re-check each loop in case the file appears later
  if [ -f ".agent-status.md" ]; then
    STATUS_FILE=".agent-status.md"
  elif [ -f "$HOME/.claude/agent-status.md" ]; then
    STATUS_FILE="$HOME/.claude/agent-status.md"
  else
    STATUS_FILE=""
  fi

  echo "=== Agent Status ==="
  echo ""
  if [ -n "$STATUS_FILE" ] && [ -f "$STATUS_FILE" ]; then
    cat "$STATUS_FILE"
  else
    echo "  No agents running."
    echo "  Waiting for .agent-status.md to appear..."
  fi
  echo ""
  echo "Last refresh: $(date '+%Y-%m-%d %H:%M:%S')"
  sleep 5
done
