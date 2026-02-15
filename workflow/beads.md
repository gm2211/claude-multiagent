# Task Tracking with bd (Beads)

`bd` is a git-backed issue tracker. Install it to `~/.local/bin/bd` or anywhere on your PATH. Run `bd --help` for the full command reference.

**When to use:** Any work involving multiple steps. Run `bd init` once per repo, then `bd create` per task. Always `bd list` before creating to avoid duplicates.

**Interpreting the user:** "bd" or "beads" = use this tool.

## Common Commands

```bash
bd init              # Initialize beads in a repo (once per repo)
bd create --title "..." --body "..."   # Create a new ticket
bd list              # List open tickets
bd close <id> --reason "..."           # Close a completed ticket
bd sync              # Sync beads state with git
```

## Integration with Coordinator Workflow

1. **Before dispatching any work**, create a bd ticket
2. **Include the ticket ID** in every sub-agent prompt
3. **Close tickets** immediately after merging the agent's work
4. **Run `bd list`** periodically to avoid duplicate or stale tickets
