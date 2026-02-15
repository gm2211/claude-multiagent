# Zellij Dashboard

The dashboard shows bd tickets and agent status in separate panes alongside your Claude session. It uses two watcher scripts that auto-refresh.

## Pane-Based Approach

Instead of opening a separate tab, add dashboard panes directly to the **current tab** where Claude is running. This keeps everything visible at a glance.

On session start, if inside Zellij (check the `$ZELLIJ` env var) and in a git repo, add panes:

```bash
# Beads pane (right side)
zellij action new-pane --direction right -- bash -c "cd $(pwd) && $HOME/.claude/scripts/watch-beads.sh"
# Agent status pane (below beads)
zellij action new-pane --direction down -- bash -c "cd $(pwd) && $HOME/.claude/scripts/watch-agents.sh"
# Return focus to Claude
zellij action move-focus left
```

This creates a layout like:

```
┌──────────────────┬──────────────┐
│                  │  Open Beads  │
│   Claude Code    ├──────────────┤
│                  │ Agent Status │
└──────────────────┴──────────────┘
```

## Safety Rules

**ONLY** use `new-pane` and `move-focus`. **NEVER** use `close-pane`, `close-tab`, or `go-to-tab` -- these can kill your own pane.

## Onboarding

If Zellij is not running, or bd is not initialized, guide the user:
- **No Zellij:** "For the best experience, run Claude inside Zellij: `zellij` then `claude`"
- **No bd:** "Run `bd init` to enable ticket tracking"

## Scripts

### `watch-beads.sh`

Displays `bd list` output in a loop. Handles missing `bd` command or uninitialized repos gracefully. Refreshes every 10 seconds.

### `watch-agents.sh`

Reads `.agent-status.md` (TSV format) and renders a Unicode box-drawing table. Looks for the file in the current working directory first, then falls back to `$HOME/.claude/agent-status.md`. Refreshes every 5 seconds.

## Setup

The `install.sh` script copies these files to the right locations. After installation, make sure:

1. Scripts are at `~/.claude/scripts/watch-beads.sh` and `~/.claude/scripts/watch-agents.sh`
2. All scripts are executable (`chmod +x`)

## Legacy: Layout File

The `layouts/dashboard.kdl` file is still included for reference. It creates a standalone tab with side-by-side panels. However, the pane-based approach above is preferred because it keeps the dashboard visible alongside your Claude session without switching tabs.
