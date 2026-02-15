#!/bin/bash
# Refreshes bd list every 10 seconds
# Handles missing bd command or uninitialized repos gracefully

while true; do
  clear
  echo "=== Open Beads ==="
  echo ""
  if ! command -v bd &>/dev/null; then
    echo "  bd command not found."
    echo "  Install beads to use this panel."
  elif [ ! -d ".beads" ]; then
    echo "  No beads initialized in this repo."
    echo "  Run 'bd init' to get started."
  else
    bd list 2>/dev/null || echo "  (bd list failed)"
  fi
  echo ""
  echo "Last refresh: $(date '+%Y-%m-%d %H:%M:%S')"
  sleep 10
done
