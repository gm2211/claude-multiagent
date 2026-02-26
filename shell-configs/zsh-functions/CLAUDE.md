# ZSH Functions — Installation Instructions

This directory contains portable shell functions to be sourced from `~/.zshrc`.

## How to install

1. **Ensure `pngpaste` is installed** (required by the `ss` function):

   ```bash
   brew install pngpaste
   ```

2. **Add a source line to `~/.zshrc`.**
   Determine the absolute path to `functions.zsh` in this repo and append:

   ```bash
   # Portable shell functions from claude-plugins
   source /absolute/path/to/claude-plugins/shell-configs/zsh-functions/functions.zsh
   ```

   Replace `/absolute/path/to/claude-plugins` with wherever this repo is cloned on the current machine.

   > **Note:** This file now includes the `claude()` worktree function (previously in `shell-configs/claude-function.sh`). If you had a separate `source .../claude-function.sh` line in your `.zshrc`, remove it — sourcing `functions.zsh` is sufficient.

3. **Reload the shell** (`source ~/.zshrc` or open a new terminal).

## What's included

| Function | Description |
|----------|-------------|
| `ss`     | Saves the current clipboard image to a temp file (via `pngpaste`) and copies the file path to the clipboard. |
| `claude` | Intercepts the `claude` command when on the default branch (main/master) of a git repo and offers to create or switch to a worktree first. Prevents accidental work directly on main. |
