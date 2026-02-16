#!/bin/bash
# Watches bd (beads) tickets and renders status with live updates
# Uses fswatch for efficient event-driven updates, falls back to polling

# Force UTF-8 for Unicode characters
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

render_screen() {
  clear
  echo "Open Beads"
  echo ""
  if ! command -v bd &>/dev/null; then
    echo "  bd command not found."
    echo "  Install beads to use this panel."
  elif [ ! -d ".beads" ]; then
    echo "  No beads initialized in this repo."
    echo "  Run 'bd init' to get started."
  else
    bd list --pretty 2>/dev/null || echo "  (bd list failed)"
  fi
  echo ""
  echo "@ $(date '+%H:%M:%S')"
}

# Initial render
render_screen

if command -v fswatch &>/dev/null && [ -d ".beads" ]; then
  # Event-driven: watch the beads database for changes
  # --latency 0.5: debounce rapid writes
  # --one-per-batch: single event per batch of changes
  fswatch --latency 0.5 --one-per-batch \
    ".beads/issues.jsonl" ".beads/beads.db-wal" 2>/dev/null \
  | while read -r _; do
    render_screen
  done
  # fswatch exited (e.g. files don't exist yet) -- fall through to polling
fi

# Fallback: poll every 5s (also used while waiting for .beads/ to appear)
while true; do
  sleep 5
  render_screen
done
