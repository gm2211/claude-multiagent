#!/usr/bin/env bash
# Close Zellij dashboard panes (beads, agents, deploys) by killing the
# processes that run inside them.  When a process exits, Zellij automatically
# closes the pane.
#
# Called by the Stop hook when a Claude Code session ends.
# Fails silently when not running inside Zellij.

set -euo pipefail

# ---------------------------------------------------------------------------
# Debug logging
# ---------------------------------------------------------------------------
LOG="/tmp/close-dashboard-debug.log"

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"
}

log "close-dashboard.sh invoked (PID=$$, ZELLIJ=${ZELLIJ:-unset}, PWD=${PWD})"

# If not inside Zellij, bail silently
if [[ -z "${ZELLIJ:-}" ]]; then
  log "Not inside Zellij — exiting."
  exit 0
fi

# ---------------------------------------------------------------------------
# Determine the project directory to scope process matching.
# This prevents killing dashboard panes belonging to other sessions.
# ---------------------------------------------------------------------------
PROJECT_DIR="${PWD}"
if git rev-parse --show-toplevel &>/dev/null; then
  PROJECT_DIR="$(git rev-parse --show-toplevel)"
fi

log "Project directory: $PROJECT_DIR"

# ---------------------------------------------------------------------------
# Kill processes running the dashboard watch scripts for THIS project.
#
# open-dashboard.sh creates panes with:
#   bash -c "cd '${PROJECT_DIR}' && '${SCRIPT_DIR}/watch-*.sh'"
# so the full command line of each process contains the project directory.
#
# Each watch script traps SIGTERM and exits cleanly; Zellij then removes the
# pane automatically.  This avoids the fragile move-focus navigation strategy.
# ---------------------------------------------------------------------------

WATCH_SCRIPTS=("watch-beads.sh" "watch-agents.sh" "watch-deploys.sh")

killed=0
for script in "${WATCH_SCRIPTS[@]}"; do
  # Find PIDs whose command line contains the script name.
  pids=$(pgrep -f "$script" 2>/dev/null || true)

  if [[ -z "$pids" ]]; then
    log "No process found for $script"
    continue
  fi

  for pid in $pids; do
    # Skip our own PID to avoid self-kill
    if [[ "$pid" == "$$" ]]; then
      continue
    fi

    # Read the full command line to check project scope.
    cmdline=$(ps -p "$pid" -o args= 2>/dev/null || true)

    if [[ -z "$cmdline" ]]; then
      log "Cannot read cmdline for PID $pid ($script) — skipping"
      continue
    fi

    # Only kill processes that belong to THIS project directory.
    if [[ "$cmdline" != *"$PROJECT_DIR"* ]]; then
      log "Skipping PID $pid ($script) — belongs to different project"
      log "  cmdline: $cmdline"
      continue
    fi

    log "Sending SIGTERM to PID $pid ($script)"
    kill "$pid" 2>/dev/null || true
    (( killed++ )) || true
  done
done

log "Done — sent SIGTERM to $killed process(es)."
exit 0
