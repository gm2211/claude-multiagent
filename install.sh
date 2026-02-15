#!/bin/bash
# claude-flows installer
# Copies scripts and layout to ~/.claude/ directories.
# Does NOT modify CLAUDE.md or settings.json -- you do that manually.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"

echo "Installing claude-flows..."
echo ""

# Create directories
mkdir -p "$CLAUDE_DIR/scripts"
mkdir -p "$CLAUDE_DIR/layouts"

# Copy scripts
cp "$SCRIPT_DIR/scripts/watch-beads.sh" "$CLAUDE_DIR/scripts/watch-beads.sh"
cp "$SCRIPT_DIR/scripts/watch-agents.sh" "$CLAUDE_DIR/scripts/watch-agents.sh"
chmod +x "$CLAUDE_DIR/scripts/watch-beads.sh"
chmod +x "$CLAUDE_DIR/scripts/watch-agents.sh"
echo "  Copied scripts to $CLAUDE_DIR/scripts/"

# Copy layout
cp "$SCRIPT_DIR/layouts/dashboard.kdl" "$CLAUDE_DIR/layouts/dashboard.kdl"
echo "  Copied layout to $CLAUDE_DIR/layouts/"

echo ""
echo "Installation complete!"
echo ""
echo "Next steps:"
echo ""
echo "  1. Update your global CLAUDE.md (~/.claude/CLAUDE.md)"
echo "     Copy the contents of the workflow/ files into your CLAUDE.md."
echo "     See examples/CLAUDE.md for a template."
echo ""
echo "  2. Update your settings.json (~/.claude/settings.json)"
echo "     Merge the permissions from examples/settings.json into your settings."
echo "     Key additions:"
echo "       - CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS env var"
echo "       - Permission patterns for git, worktree, and bd commands"
echo ""
echo "  3. Install bd (beads) if you haven't already"
echo "     See: https://github.com/gm2211/beads"
echo ""
echo "  4. Install Zellij if you haven't already"
echo "     See: https://zellij.dev/documentation/installation"
echo ""
echo "  5. Start using it!"
echo "     cd your-project && bd init"
echo "     zellij && claude"
