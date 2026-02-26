# Portable ZSH functions
# Sourced from claude-plugins/shell-configs/zsh-functions/

function ss() {
    local f="/tmp/ss-${RANDOM}${RANDOM}.png"
    pngpaste "$f" && {
      echo -n "$f" | pbcopy
      echo "Saved & copied: $f"
    }
}

# claude() — Worktree-first shell function for Claude Code.
#
# Prevents Claude Code sessions from accidentally working on the default branch
# (main/master) of a git repo. When it detects that situation, it offers to
# create or select a worktree before launching Claude inside it.
#
# Pass-through cases (no intervention):
#   - Not inside a git repository
#   - Already inside a git worktree
#   - On a non-default branch (not main/master)
#
# Target case (on main/master in a repo root):
#   - Lists existing epic worktrees in .worktrees/
#   - Offers to create a new worktree with an AI-generated branch name
#   - Launches claude from inside the chosen worktree
#
# Compatible with bash and zsh.

claude() {
  ###############################################################################
  # Helpers
  ###############################################################################

  _claude_msg()  { printf '%s\n' "$*" >&2; }
  _claude_warn() { printf 'WARNING: %s\n' "$*" >&2; }
  _claude_err()  { printf 'ERROR: %s\n' "$*" >&2; }

  # Clean up on Ctrl+C
  trap '_claude_msg ""; _claude_msg "Interrupted."; return 130' INT

  ###############################################################################
  # Case 1: Not a git repo → pass through
  ###############################################################################

  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    command claude "$@"
    return $?
  fi

  ###############################################################################
  # Case 2: Already in a worktree → pass through
  ###############################################################################

  local git_dir git_common_dir abs_git_dir abs_git_common
  git_dir="$(git rev-parse --git-dir 2>/dev/null)"
  git_common_dir="$(git rev-parse --git-common-dir 2>/dev/null)"

  # Normalize to absolute paths for reliable comparison
  abs_git_dir="$(cd "$git_dir" && pwd)"
  abs_git_common="$(cd "$git_common_dir" && pwd)"

  if [ "$abs_git_dir" != "$abs_git_common" ]; then
    command claude "$@"
    return $?
  fi

  ###############################################################################
  # Case 3: On a non-default branch → pass through
  ###############################################################################

  local default_branch current_branch
  # Detect the default branch dynamically
  default_branch="$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')"
  if [ -z "$default_branch" ]; then
    # Fallback: check if main or master exists
    if git show-ref --verify --quiet refs/heads/main 2>/dev/null; then
      default_branch="main"
    elif git show-ref --verify --quiet refs/heads/master 2>/dev/null; then
      default_branch="master"
    else
      default_branch="main"
    fi
  fi

  current_branch="$(git symbolic-ref --short HEAD 2>/dev/null || echo "")"

  if [ "$current_branch" != "$default_branch" ]; then
    command claude "$@"
    return $?
  fi

  ###############################################################################
  # Case 4: On default branch in a git repo — offer worktree selection/creation
  ###############################################################################

  local repo_root worktrees_dir
  repo_root="$(git rev-parse --show-toplevel)"
  worktrees_dir="$repo_root/.worktrees"
  mkdir -p "$worktrees_dir"

  _claude_msg ""
  _claude_msg "You are on the '$default_branch' branch. Claude should run in a worktree."
  _claude_msg ""

  # Collect existing epic worktrees (directories without -- in their name)
  local epic_worktrees=()
  if [ -d "$worktrees_dir" ]; then
    local wt_dir wt_name
    # Suppress "no matches found" in zsh when glob matches nothing
    [ -n "$ZSH_VERSION" ] && setopt local_options NULL_GLOB
    for wt_dir in "$worktrees_dir"/*/; do
      [ -d "$wt_dir" ] || continue
      wt_name="$(basename "$wt_dir")"
      # Skip task worktrees (contain --)
      case "$wt_name" in *--*) continue ;; esac
      epic_worktrees+=("$wt_name")
    done
  fi

  local choice=""

  if [ ${#epic_worktrees[@]} -gt 0 ]; then
    _claude_msg "Existing worktrees:"
    local i
    for i in "${!epic_worktrees[@]}"; do
      _claude_msg "  $((i + 1))) ${epic_worktrees[$i]}"
    done
    _claude_msg "  n) Create new worktree"
    _claude_msg ""

    local selection
    read -r -p "Select a worktree [1-${#epic_worktrees[@]}/n]: " selection </dev/tty >&2

    if [ "$selection" = "n" ] || [ "$selection" = "N" ]; then
      choice="__new__"
    elif echo "$selection" | grep -qE '^[0-9]+$' && [ "$selection" -ge 1 ] && [ "$selection" -le ${#epic_worktrees[@]} ]; then
      choice="${epic_worktrees[$((selection - 1))]}"
    else
      _claude_err "Invalid selection: $selection"
      trap - INT
      return 1
    fi
  else
    choice="__new__"
  fi

  ###############################################################################
  # Create new worktree
  ###############################################################################

  if [ "$choice" = "__new__" ]; then
    local description
    read -r -p "What are you working on? (short description): " description </dev/tty >&2

    if [ -z "$description" ]; then
      _claude_err "Description cannot be empty."
      trap - INT
      return 1
    fi

    # Try to generate a branch name using claude -p
    local branch_name=""
    _claude_msg "Generating branch name..."

    branch_name=$(command claude -p "Generate a short kebab-case branch name (max 30 chars, no prefix) for this feature: ${description}. Output ONLY the branch name, nothing else." 2>/dev/null) || true

    # Clean up the response: trim whitespace, remove quotes, take first line only
    branch_name="$(printf '%s' "$branch_name" | head -1 | tr -d '[:space:]"'\'' ' | tr -cd 'a-z0-9-')"

    # Fallback if claude -p failed or returned empty/garbage
    if [ -z "$branch_name" ] || [ "${#branch_name}" -gt 40 ]; then
      _claude_warn "Could not generate branch name automatically. Please provide one."
      read -r -p "Branch name (kebab-case, max 30 chars): " branch_name </dev/tty >&2

      if [ -z "$branch_name" ]; then
        _claude_err "Branch name cannot be empty."
        trap - INT
        return 1
      fi

      # Sanitize user input
      branch_name="$(printf '%s' "$branch_name" | tr '[:upper:]' '[:lower:]' | tr ' _' '--' | tr -cd 'a-z0-9-' | sed -E 's/-+/-/g; s/^-+//; s/-+$//' | cut -c1-30)"
    fi

    local worktree_path="$worktrees_dir/$branch_name"

    # If this worktree already exists, just use it
    if [ -d "$worktree_path" ]; then
      _claude_msg "Worktree '$branch_name' already exists. Using it."
      choice="$branch_name"
    else
      _claude_msg "Creating worktree: $branch_name"
      git worktree add "$worktree_path" -b "$branch_name" || {
        _claude_err "Failed to create worktree. You may need to resolve this manually."
        trap - INT
        return 1
      }
      choice="$branch_name"
    fi
  fi

  ###############################################################################
  # Launch claude from inside the chosen worktree
  ###############################################################################

  local target_dir="$worktrees_dir/$choice"

  if [ ! -d "$target_dir" ]; then
    _claude_err "Worktree directory does not exist: $target_dir"
    trap - INT
    return 1
  fi

  _claude_msg ""
  _claude_msg "Launching Claude in worktree: $choice"
  _claude_msg ""

  trap - INT
  (cd "$target_dir" && command claude "$@")
}
