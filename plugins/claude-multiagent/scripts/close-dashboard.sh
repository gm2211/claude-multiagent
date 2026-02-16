#!/usr/bin/env bash
# Close Zellij dashboard panes (beads, agents, deploys) by name.
# Called by the Stop hook when a Claude Code session ends.
# Fails silently when not running inside Zellij.

set -euo pipefail

# If not inside Zellij, bail silently
if [[ -z "${ZELLIJ:-}" ]]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Get the focused tab layout block from dump-layout output.
get_focused_tab_layout() {
  local layout
  layout=$(zellij action dump-layout 2>/dev/null) || return 1

  local in_focused=0
  local depth=0
  local result=""

  while IFS= read -r line; do
    if [[ $in_focused -eq 0 ]]; then
      if [[ "$line" =~ ^[[:space:]]*tab[[:space:]].*focus=true ]]; then
        in_focused=1
        depth=1
        result="$line"$'\n'
      fi
    else
      result+="$line"$'\n'
      local opens="${line//[^\{]/}"
      local closes="${line//[^\}]/}"
      depth=$(( depth + ${#opens} - ${#closes} ))
      if [[ $depth -le 0 ]]; then
        break
      fi
    fi
  done <<< "$layout"

  printf '%s' "$result"
}

# Check if a named dashboard pane exists in the layout.
has_dashboard_pane() {
  local layout="$1"
  local pane_name="$2"
  [[ "$layout" == *"name=\"${pane_name}\""* ]]
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

DASHBOARD_PANE_NAMES=("dashboard-deploys" "dashboard-agents" "dashboard-beads")

focused_tab=$(get_focused_tab_layout) || exit 0

# Count how many dashboard panes exist
panes_to_close=0
for name in "${DASHBOARD_PANE_NAMES[@]}"; do
  if has_dashboard_pane "$focused_tab" "$name"; then
    (( panes_to_close++ ))
  fi
done

if [[ "$panes_to_close" -eq 0 ]]; then
  exit 0
fi

# Strategy: navigate focus to the right side where dashboard panes live,
# then close them one at a time from bottom to top. After each close,
# re-check the layout to confirm and stop early if no panes remain.
#
# We close bottom-to-top (deploys, agents, beads) so that each close
# naturally moves focus upward to the next dashboard pane.

for name in "${DASHBOARD_PANE_NAMES[@]}"; do
  # Re-read layout each iteration (it changes after each close)
  focused_tab=$(get_focused_tab_layout 2>/dev/null) || break

  if ! has_dashboard_pane "$focused_tab" "$name"; then
    continue
  fi

  # Move focus to the right side where dashboard panes live.
  # Multiple move-focus calls ensure we reach the rightmost column.
  zellij action move-focus right 2>/dev/null || true

  # Navigate down to reach lower panes (deploys is at the bottom).
  # For the first pane (deploys), go all the way down.
  # For agents (middle), go down once from top.
  # For beads (top), we should already be there after closing lower ones.
  case "$name" in
    dashboard-deploys)
      zellij action move-focus down 2>/dev/null || true
      zellij action move-focus down 2>/dev/null || true
      ;;
    dashboard-agents)
      zellij action move-focus down 2>/dev/null || true
      ;;
    dashboard-beads)
      # Already at the top of the right column
      ;;
  esac

  zellij action close-pane 2>/dev/null || true

  # Brief pause to let Zellij update its layout
  sleep 0.2
done

exit 0
