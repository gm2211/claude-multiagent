# Portable ZSH functions
# Sourced from claude-plugins/shell-configs/zsh-functions/

function ss() {
    local f="/tmp/ss-${RANDOM}${RANDOM}.png"
    pngpaste "$f" && {
      echo -n "$f" | pbcopy
      echo "Saved & copied: $f"
    }
}

# wt() — Interactive worktree selector/creator.
#
# Works from any git repo. When on the default branch (main/master), offers to
# select an existing worktree or create a new one, then cd's into it.
#
# Behavior:
#   - Not inside a git repository → error, return 1
#   - Already inside a git worktree → print which worktree, return 0
#   - On a non-default branch → print which branch, return 0
#   - On the default branch (main/master):
#     1. List existing epic worktrees from .worktrees/ (skip task worktrees with --)
#     2. If worktrees exist: numbered list + "n) Create new" option
#     3. If no worktrees: go straight to creation
#     4. For creation: prompt for description, generate branch name via claude -p
#     5. cd into the selected/created worktree
#
# Compatible with bash and zsh.

wt() {
  #############################################################################
  # Helpers
  #############################################################################

  _wt_msg()  { printf '%s\n' "$*" >&2; }
  _wt_warn() { printf 'WARNING: %s\n' "$*" >&2; }
  _wt_err()  { printf 'ERROR: %s\n' "$*" >&2; }

  # Clean up on Ctrl+C
  trap '_wt_msg ""; _wt_msg "Interrupted."; return 130' INT

  #############################################################################
  # Case 1: Not a git repo → error
  #############################################################################

  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    _wt_err "Not inside a git repository."
    trap - INT
    return 1
  fi

  #############################################################################
  # Case 2: Already in a worktree → inform and return
  #############################################################################

  local git_dir git_common_dir abs_git_dir abs_git_common
  git_dir="$(git rev-parse --git-dir 2>/dev/null)"
  git_common_dir="$(git rev-parse --git-common-dir 2>/dev/null)"

  # Normalize to absolute paths for reliable comparison
  abs_git_dir="$(cd "$git_dir" && pwd)"
  abs_git_common="$(cd "$git_common_dir" && pwd)"

  if [ "$abs_git_dir" != "$abs_git_common" ]; then
    local wt_branch
    wt_branch="$(git symbolic-ref --short HEAD 2>/dev/null || echo "(detached)")"
    _wt_msg "Already in a worktree: $wt_branch ($(pwd))"
    trap - INT
    return 0
  fi

  #############################################################################
  # Case 3: On a non-default branch → inform and return
  #############################################################################

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
    _wt_msg "On branch '$current_branch' (not the default branch)."
    trap - INT
    return 0
  fi

  #############################################################################
  # Case 4: On default branch — offer worktree selection/creation
  #############################################################################

  local repo_root worktrees_dir
  repo_root="$(git rev-parse --show-toplevel)"
  worktrees_dir="$repo_root/.worktrees"
  mkdir -p "$worktrees_dir"

  _wt_msg ""
  _wt_msg "You are on the '$default_branch' branch."
  _wt_msg ""

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
    _wt_msg "Existing worktrees:"
    local _i=0
    local _wt
    for _wt in "${epic_worktrees[@]}"; do
      _i=$((_i + 1))
      _wt_msg "  ${_i}) ${_wt}"
    done
    _wt_msg "  n) Create new worktree"
    _wt_msg ""

    local selection
    printf "Select a worktree [1-${#epic_worktrees[@]}/n]: " >&2
    read -r selection </dev/tty

    if [ "$selection" = "n" ] || [ "$selection" = "N" ]; then
      choice="__new__"
    elif echo "$selection" | grep -qE '^[0-9]+$' && [ "$selection" -ge 1 ] && [ "$selection" -le ${#epic_worktrees[@]} ]; then
      # Portable: walk array to find the Nth element
      _i=0
      for _wt in "${epic_worktrees[@]}"; do
        _i=$((_i + 1))
        if [ "$_i" -eq "$selection" ]; then
          choice="$_wt"
          break
        fi
      done
    else
      _wt_err "Invalid selection: $selection"
      trap - INT
      return 1
    fi
  else
    choice="__new__"
  fi

  #############################################################################
  # Create new worktree
  #############################################################################

  if [ "$choice" = "__new__" ]; then
    local description
    printf "What are you working on? (short description): " >&2
    read -r description </dev/tty

    if [ -z "$description" ]; then
      _wt_err "Description cannot be empty."
      trap - INT
      return 1
    fi

    # Try to generate a branch name using claude -p
    local branch_name=""
    _wt_msg "Generating branch name..."

    branch_name=$(command claude -p "Generate a short kebab-case branch name (max 30 chars, no prefix) for this feature: ${description}. Output ONLY the branch name, nothing else." 2>/dev/null) || true

    # Clean up the response: trim whitespace, remove quotes, take first line only
    branch_name="$(printf '%s' "$branch_name" | head -1 | tr -d '[:space:]"'\'' ' | tr -cd 'a-z0-9-')"

    # Fallback if claude -p failed or returned empty/garbage
    if [ -z "$branch_name" ] || [ "${#branch_name}" -gt 40 ]; then
      _wt_warn "Could not generate branch name automatically. Please provide one."
      printf "Branch name (kebab-case, max 30 chars): " >&2
      read -r branch_name </dev/tty

      if [ -z "$branch_name" ]; then
        _wt_err "Branch name cannot be empty."
        trap - INT
        return 1
      fi

      # Sanitize user input
      branch_name="$(printf '%s' "$branch_name" | tr '[:upper:]' '[:lower:]' | tr ' _' '--' | tr -cd 'a-z0-9-' | sed -E 's/-+/-/g; s/^-+//; s/-+$//' | cut -c1-30)"
    fi

    local worktree_path="$worktrees_dir/$branch_name"

    # If this worktree already exists, just use it
    if [ -d "$worktree_path" ]; then
      _wt_msg "Worktree '$branch_name' already exists. Using it."
      choice="$branch_name"
    else
      _wt_msg "Creating worktree: $branch_name"
      git worktree add "$worktree_path" -b "$branch_name" || {
        _wt_err "Failed to create worktree. You may need to resolve this manually."
        trap - INT
        return 1
      }
      choice="$branch_name"
    fi
  fi

  #############################################################################
  # cd into the chosen worktree
  #############################################################################

  local target_dir="$worktrees_dir/$choice"

  if [ ! -d "$target_dir" ]; then
    _wt_err "Worktree directory does not exist: $target_dir"
    trap - INT
    return 1
  fi

  _wt_msg ""
  _wt_msg "Switching to worktree: $choice"
  _wt_msg ""

  trap - INT
  cd "$target_dir"
}

# claude() — Worktree-first shell function for Claude Code.
#
# Prevents Claude Code sessions from accidentally working on the default branch
# (main/master) of a git repo. When it detects that situation, it calls wt() to
# select or create a worktree, then launches Claude inside it.
#
# Pass-through cases (no intervention):
#   - Not inside a git repository
#   - Already inside a git worktree
#   - On a non-default branch (not main/master)
#
# Target case (on main/master in a repo root):
#   - Delegates to wt() for worktree selection/creation
#   - Launches claude from inside the chosen worktree (in a subshell so the
#     cd from wt() does not leak to the parent shell)
#
# Compatible with bash and zsh.

claude() {
  #############################################################################
  # Case 1: Not a git repo → pass through
  #############################################################################

  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    command claude "$@"
    return $?
  fi

  #############################################################################
  # Case 2: Already in a worktree → pass through
  #############################################################################

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

  #############################################################################
  # Case 3: On a non-default branch → pass through
  #############################################################################

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

  #############################################################################
  # Case 4: On default branch — use wt() then launch claude
  #############################################################################

  printf '%s\n' "" >&2
  printf '%s\n' "You are on the '$default_branch' branch. Claude should run in a worktree." >&2
  printf '%s\n' "" >&2

  # Run wt + claude in a subshell so the cd does not leak to the parent shell
  (wt && command claude "$@")
}
