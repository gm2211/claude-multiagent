# claude-flows

A workflow for using [Claude Code](https://docs.anthropic.com/en/docs/claude-code) as an **async coordinator/dispatcher** that delegates all implementation to background sub-agents working in git worktrees.

## What is this?

Instead of Claude Code doing everything sequentially in one thread, this workflow turns it into a **project manager**:

1. **You describe work** -- features, bugs, refactors
2. **Claude files a ticket** using [bd (beads)](https://github.com/gm2211/beads), a git-backed issue tracker
3. **Claude dispatches a sub-agent** to do the work in an isolated git worktree
4. **You keep talking to Claude** -- it stays responsive while agents work in the background
5. **Claude merges completed work** back to main when agents finish

A [Zellij](https://zellij.dev/) dashboard gives you real-time visibility into ticket status and agent progress, right alongside your Claude session.

## Components

| Component | Description |
|-----------|-------------|
| `workflow/coordinator.md` | The coordinator role and rules for Claude |
| `workflow/beads.md` | bd (beads) ticket tracking integration |
| `workflow/zellij-dashboard.md` | Zellij dashboard setup (pane-based) |
| `scripts/watch-beads.sh` | Live-refreshing bd ticket list |
| `scripts/watch-agents.sh` | Live-refreshing agent status with Unicode table |
| `layouts/dashboard.kdl` | Legacy Zellij layout (tab-based, for reference) |
| `examples/CLAUDE.md` | Example global CLAUDE.md with full workflow |
| `examples/settings.json` | Example Claude Code permissions config |
| `install.sh` | Installer that copies scripts and layout into place |

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed and configured
- [Zellij](https://zellij.dev/) terminal multiplexer
- [bd (beads)](https://github.com/gm2211/beads) issue tracker (`~/.local/bin/bd`)
- Git (for worktrees)

## Quick Start

### 1. Install files

```bash
git clone https://github.com/gm2211/claude-flows.git
cd claude-flows
./install.sh
```

This copies scripts and the Zellij layout to `~/.claude/`. It does **not** modify your `CLAUDE.md` or `settings.json` -- you do that manually.

### 2. Update your global CLAUDE.md

Add the workflow rules to `~/.claude/CLAUDE.md`. See `examples/CLAUDE.md` for a complete template that includes all workflow rules inline, or copy the contents of the `workflow/` files directly into your CLAUDE.md.

### 3. Update your settings.json

Merge the permissions from `examples/settings.json` into `~/.claude/settings.json`. The key additions are:
- `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` environment variable
- Permission patterns for git, worktree, bd, and zellij commands

### 4. Initialize bd in your project

```bash
cd your-project
bd init
```

### 5. Start a Zellij session and use Claude

```bash
zellij
claude
```

Claude will now operate as a coordinator, delegating work to sub-agents and tracking everything through bd tickets. On startup, it will add dashboard panes to your current Zellij tab showing ticket status and agent progress.

## How It Works

### The Coordinator Pattern

Claude operates under strict rules:
- **Never writes implementation code** -- always delegates to sub-agents
- **Stays async** -- dispatches work and immediately returns to idle
- **Files tickets first** -- every task gets a bd ticket before work begins
- **Manages merging** -- reviews diffs and merges completed agent work to main

### Sub-Agent Teams

Sub-agents are managed via **teams** (TeamCreate + SendMessage), allowing the coordinator to course-correct agents mid-flight. Each agent:
- Works in its own git worktree under `.worktrees/` (gitignored)
- Sends heartbeat status updates every 30 seconds
- Cannot interfere with other agents or the main working tree

Up to 5 agents can work concurrently.

### Zellij Dashboard

Dashboard panes are added directly to your current Zellij tab (no tab switching needed):

```
┌──────────────────┬──────────────┐
│                  │  Open Beads  │
│   Claude Code    ├──────────────┤
│                  │ Agent Status │
└──────────────────┴──────────────┘
```

- **Right pane**: Open bd tickets (refreshes every 10s)
- **Lower-right pane**: Agent status table (refreshes every 5s)

### Status Tracking

Agents update `.agent-status.md` in the repo root using TSV format:

```
Agent	Ticket	Duration	Summary	ETA	Needs Help?
my-agent	abc	2 min	Working on X	~5 min	No
```

The `watch-agents.sh` script renders this as a Unicode box-drawing table:

```
┌──────────┬────────┬──────────┬──────────────┬───────┬─────────────┐
│  Agent   │ Ticket │ Duration │   Summary    │  ETA  │ Needs Help? │
├──────────┼────────┼──────────┼──────────────┼───────┼─────────────┤
│ my-agent │ abc    │ 2 min    │ Working on X │ ~5min │ No          │
└──────────┴────────┴──────────┴──────────────┴───────┴─────────────┘
```

Completed agents are removed from the status file after cleanup (merge + worktree removal + ticket close).

## Customization

### Project-specific CLAUDE.md

Each project can have its own `CLAUDE.md` at the repo root with:
- Quality gates (build/test commands)
- Project-specific gotchas
- Deploy monitoring config
- Custom worktree conventions

### Adjusting Agent Count

The default limit is 5 concurrent agents. Adjust this in your coordinator workflow rules based on your machine's resources.

## License

MIT
