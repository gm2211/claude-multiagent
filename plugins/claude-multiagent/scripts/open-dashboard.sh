#!/usr/bin/env bash
# Open Zellij dashboard panes for beads (tickets) and agent status.
# Called by both the SessionStart hook and the agents-dashboard skill.
# Fails silently when not running inside Zellij.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PROJECT_DIR="${1:-$PWD}"

zellij action new-pane --direction right -- bash -c "cd '${PROJECT_DIR}' && '${SCRIPT_DIR}/watch-beads.sh'" 2>/dev/null || true
zellij action move-focus right 2>/dev/null || true
zellij action new-pane --direction down -- bash -c "cd '${PROJECT_DIR}' && '${SCRIPT_DIR}/watch-agents.sh'" 2>/dev/null || true
zellij action move-focus left 2>/dev/null || true
