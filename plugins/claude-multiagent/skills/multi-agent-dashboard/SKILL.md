---
name: multi-agent-dashboard
description: Open Zellij panes showing agent status and open tickets alongside your Claude session
---

# Reopen Dashboard Panes

Run this command to restore the dashboard panes. Requires Zellij.

```bash
"${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/plugins/claude-multiagent}/scripts/open-dashboard.sh"
```

## Safety Rules

**ONLY** use `new-pane` and `move-focus` Zellij actions. **NEVER** use `close-pane`, `close-tab`, or `go-to-tab`.
