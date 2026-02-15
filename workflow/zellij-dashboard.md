# Zellij Dashboard

A dashboard tab shows bd tickets and agent status side by side. It uses two watcher scripts that auto-refresh.

## Opening the Dashboard

From inside Claude, open the dashboard tab with:

```bash
zellij -s <session> action new-tab --name "Dashboard" --cwd "$(pwd)" --layout "$HOME/.claude/layouts/dashboard.kdl"
```

Replace `<session>` with your current Zellij session name.

## Critical Warning

**NEVER close or switch zellij tabs from inside Claude** -- it kills your own pane. Only create new tabs. Tell the user to close stale tabs manually.

## Layout

The dashboard layout (`layouts/dashboard.kdl`) creates two side-by-side panels:

- **Left panel**: Runs `watch-beads.sh` -- shows open bd tickets, refreshes every 10 seconds
- **Right panel**: Runs `watch-agents.sh` -- shows agent status table, refreshes every 5 seconds

## Scripts

### `watch-beads.sh`

Displays `bd list` output in a loop. Handles missing bd command or uninitialized repos gracefully.

### `watch-agents.sh`

Displays `.agent-status.md` contents in a loop. Looks for the file in the current working directory first, then falls back to `$HOME/.claude/agent-status.md`.

## Setup

The `install.sh` script copies these files to the right locations. After installation, make sure:

1. Scripts are at `~/.claude/scripts/watch-beads.sh` and `~/.claude/scripts/watch-agents.sh`
2. Layout is at `~/.claude/layouts/dashboard.kdl`
3. All scripts are executable (`chmod +x`)
