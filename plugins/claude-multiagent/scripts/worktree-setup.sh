#!/usr/bin/env bash
# worktree-setup.sh — Create a correctly-named git worktree for a bead.
#
# Reads bead metadata via `bd show` to determine whether the bead is a
# session-level item or a task, generates a slug, creates the worktree with
# the right naming convention, and prints machine-readable output for eval.
#
# Usage:
#   worktree-setup.sh <bead-id> [--repo-root /path/to/repo]
#
# Output (stdout, machine-readable — safe to eval):
#   WORKTREE_PATH=/absolute/path/to/.worktrees/session--task
#   WORKTREE_BRANCH=session--task
#   WORKTREE_TYPE=task
#   SESSION_SLUG=session
#
# Exit codes:
#   0 — success (worktree created or already exists)
#   1 — usage / argument error
#   2 — bd command not found or bead not found
#   3 — safety check failed (nesting, wrong directory, etc.)
#   4 — git worktree creation failed

set -euo pipefail

###############################################################################
# Helpers
###############################################################################

die()  { echo "ERROR: $*" >&2; exit 1; }
warn() { echo "WARNING: $*" >&2; }
info() { echo "INFO: $*" >&2; }

usage() {
  cat >&2 <<'USAGE'
Usage: worktree-setup.sh <bead-id> [--repo-root /path/to/repo]

Creates a git worktree for the given bead with the correct naming convention.

Options:
  --repo-root DIR   Use DIR as the repository root (default: auto-detect)
  -h, --help        Show this help message
USAGE
  exit 1
}

# slugify — convert a string into a URL/branch-safe slug.
#
# Rules:
#   1. Lowercase everything
#   2. Replace spaces/underscores with hyphens
#   3. Strip common prefixes: epic:, [pN], fix-
#   4. Strip everything except [a-z0-9-]
#   5. Collapse multiple hyphens
#   6. Trim leading/trailing hyphens
#   7. Truncate to 30 characters (at word boundary if possible)
slugify() {
  local input="$1"

  # Pipeline: lowercase -> substitute -> strip prefixes -> clean -> truncate
  echo "$input" \
    | tr '[:upper:]' '[:lower:]' \
    | tr ' _' '--' \
    | sed -E 's/^epic[: -]+//' \
    | sed -E 's/^\[p[0-4]\][- ]*//' \
    | sed -E 's/^fix-//' \
    | tr -cd 'a-z0-9-' \
    | sed -E 's/-+/-/g' \
    | sed -E 's/^-+//; s/-+$//' \
    | awk '{
        if (length($0) <= 30) { print; next }
        s = substr($0, 1, 30)
        # If char at position 31 is not a hyphen, try to cut at last hyphen
        if (substr($0, 31, 1) != "-") {
          n = match(s, /.*-/)
          if (n > 0) s = substr(s, 1, RLENGTH - 1)
        }
        # Trim trailing hyphens
        sub(/-+$/, "", s)
        print s
      }'
}

###############################################################################
# Argument Parsing
###############################################################################

BEAD_ID=""
REPO_ROOT=""
REPO_ROOT_ARG=""

while [ $# -gt 0 ]; do
  case "$1" in
    --repo-root)
      [ $# -lt 2 ] && die "--repo-root requires a path argument"
      REPO_ROOT_ARG="$2"
      shift 2
      ;;
    --repo-root=*)
      REPO_ROOT_ARG="${1#--repo-root=}"
      shift
      ;;
    -h|--help)
      usage
      ;;
    -*)
      die "Unknown option: $1"
      ;;
    *)
      if [ -z "$BEAD_ID" ]; then
        BEAD_ID="$1"
      else
        die "Unexpected argument: $1 (bead-id already set to $BEAD_ID)"
      fi
      shift
      ;;
  esac
done

[ -z "$BEAD_ID" ] && usage

###############################################################################
# Resolve Repo Root
###############################################################################

# 1. Find where we actually are
ACTUAL_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" \
  || die "Not inside a git repository and --repo-root not provided"

# 2. Detect if we're in a worktree
GIT_DIR="$(cd "$ACTUAL_ROOT" && git rev-parse --git-dir)"
GIT_COMMON="$(cd "$ACTUAL_ROOT" && git rev-parse --git-common-dir)"
# Normalize to absolute paths
GIT_DIR="$(cd "$ACTUAL_ROOT" && cd "$GIT_DIR" && pwd)"
GIT_COMMON="$(cd "$ACTUAL_ROOT" && cd "$GIT_COMMON" && pwd)"

IN_WORKTREE=false
if [ "$GIT_DIR" != "$GIT_COMMON" ]; then
  IN_WORKTREE=true
fi

# 3. Resolve REPO_ROOT to main repo root (not worktree root)
if [ -n "${REPO_ROOT_ARG:-}" ]; then
  # User passed --repo-root explicitly
  [ -d "$REPO_ROOT_ARG/.git" ] || [ -f "$REPO_ROOT_ARG/.git" ] \
    || die "Not a git repository: $REPO_ROOT_ARG"
  REPO_ROOT="$REPO_ROOT_ARG"
elif [ "$IN_WORKTREE" = true ]; then
  # GIT_COMMON is the main .git dir; repo root is its parent
  REPO_ROOT="$(dirname "$GIT_COMMON")"

  # Safety: only allow from session worktrees (no -- in branch name)
  CURRENT_BRANCH="$(git -C "$ACTUAL_ROOT" branch --show-current 2>/dev/null || true)"
  case "$CURRENT_BRANCH" in
    *--*)
      die "Refusing to run from a task worktree ($CURRENT_BRANCH). Run from the session worktree or main repo root."
      ;;
  esac

  info "Running from session worktree ($CURRENT_BRANCH). Using main repo root: $REPO_ROOT"
else
  REPO_ROOT="$ACTUAL_ROOT"
fi

REPO_ROOT="$(cd "$REPO_ROOT" && pwd)"  # absolute path

###############################################################################
# Check bd availability
###############################################################################

BD="$(command -v bd 2>/dev/null)" || die "bd command not found in PATH. Install beads first."

###############################################################################
# Fetch Bead Metadata
###############################################################################

BEAD_JSON=$("$BD" show "$BEAD_ID" --json 2>/dev/null) \
  || die "Failed to fetch bead: $BEAD_ID (bd show returned error)"

# bd show --json returns an array; extract fields via python3
BEAD_TITLE=$(echo "$BEAD_JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d[0]['title'])
" 2>/dev/null) || die "Failed to parse bead JSON for $BEAD_ID"

BEAD_TYPE=$(echo "$BEAD_JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d[0].get('issue_type', ''))
" 2>/dev/null || echo "")

DEPENDENT_COUNT=$(echo "$BEAD_JSON" | python3 -c "
import sys, json
d = json.load(sys.stdin)[0]
print(d.get('dependent_count', 0))
" 2>/dev/null || echo "0")

info "Bead: $BEAD_ID -- $BEAD_TITLE (type=$BEAD_TYPE)"

###############################################################################
# Check for children (dependents)
###############################################################################

CHILDREN_JSON=$("$BD" children "$BEAD_ID" --json 2>/dev/null || echo "[]")
CHILDREN_COUNT=$(echo "$CHILDREN_JSON" | python3 -c "
import sys, json
print(len(json.load(sys.stdin)))
" 2>/dev/null || echo "0")

###############################################################################
# Determine: Epic or Task?
###############################################################################

IS_EPIC=false

# Check issue_type
if [ "$BEAD_TYPE" = "epic" ]; then
  IS_EPIC=true
fi

# Check title prefix (case-insensitive)
TITLE_LOWER=$(echo "$BEAD_TITLE" | tr '[:upper:]' '[:lower:]')
case "$TITLE_LOWER" in
  epic:*|"epic "*)
    IS_EPIC=true
    ;;
esac

# Check children/dependents
if [ "$CHILDREN_COUNT" -gt 0 ] 2>/dev/null || [ "$DEPENDENT_COUNT" -gt 0 ] 2>/dev/null; then
  IS_EPIC=true
fi

###############################################################################
# Worktree Directory
###############################################################################

WORKTREES_DIR="$REPO_ROOT/.worktrees"
mkdir -p "$WORKTREES_DIR"

###############################################################################
# Standalone Worktree (for epic-type beads)
###############################################################################

if [ "$IS_EPIC" = true ]; then
  SLUG=$(slugify "$BEAD_TITLE")
  WORKTREE_PATH="$WORKTREES_DIR/$SLUG"
  BRANCH="$SLUG"

  # Already exists?
  if [ -d "$WORKTREE_PATH" ]; then
    info "Standalone worktree already exists: $WORKTREE_PATH"
    echo "WORKTREE_PATH=$WORKTREE_PATH"
    echo "WORKTREE_BRANCH=$BRANCH"
    echo "WORKTREE_TYPE=standalone"
    echo "SESSION_SLUG=$SLUG"
    exit 0
  fi

  # Check if branch already exists
  if git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/$BRANCH" 2>/dev/null; then
    die "Branch '$BRANCH' already exists but no worktree at $WORKTREE_PATH. Resolve manually."
  fi

  info "Creating standalone worktree: $WORKTREE_PATH (branch: $BRANCH)"
  git -C "$REPO_ROOT" worktree add "$WORKTREE_PATH" -b "$BRANCH" \
    || die "git worktree add failed"

  echo "WORKTREE_PATH=$WORKTREE_PATH"
  echo "WORKTREE_BRANCH=$BRANCH"
  echo "WORKTREE_TYPE=standalone"
  echo "SESSION_SLUG=$SLUG"
  exit 0
fi

###############################################################################
# Task Worktree — Find Parent Session
###############################################################################

SESSION_SLUG=""

# Strategy 1: Check bd refs — look for a referenced epic/parent
REFS_JSON=$("$BD" show "$BEAD_ID" --refs --json 2>/dev/null || echo "{}")
PARENT_FROM_REFS=$(echo "$REFS_JSON" | python3 -c "
import sys, json
bead_id = sys.argv[1]
data = json.load(sys.stdin)
refs = data.get(bead_id) or []
for ref in refs:
    title = ref.get('title', '')
    itype = ref.get('issue_type', '')
    if itype == 'epic' or title.lower().startswith('epic:') or title.lower().startswith('epic '):
        print(title)
        break
" "$BEAD_ID" 2>/dev/null || echo "")

if [ -n "$PARENT_FROM_REFS" ]; then
  SESSION_SLUG=$(slugify "$PARENT_FROM_REFS")
  info "Found parent from refs: $PARENT_FROM_REFS (slug: $SESSION_SLUG)"
fi

# Strategy 2: Check existing session worktrees (directories without -- in name)
if [ -z "$SESSION_SLUG" ] && [ -d "$WORKTREES_DIR" ]; then
  for wt_dir in "$WORKTREES_DIR"/*/; do
    [ -d "$wt_dir" ] || continue
    wt_name=$(basename "$wt_dir")
    # Skip task worktrees (contain --)
    case "$wt_name" in *--*) continue ;; esac
    info "Found existing session worktree: $wt_name"
    SESSION_SLUG="$wt_name"
    info "Using existing session worktree as parent: $wt_name"
    break
  done
fi

# Strategy 3: Search bd for epic issues
if [ -z "$SESSION_SLUG" ]; then
  PARENT_FROM_BD=$(
    "$BD" list --json 2>/dev/null | python3 -c "
import sys, json
issues = json.load(sys.stdin)
epics = []
for issue in issues:
    title = issue.get('title', '')
    itype = issue.get('issue_type', '')
    if itype == 'epic' or title.lower().startswith('epic:') or title.lower().startswith('epic '):
        epics.append(issue)
if len(epics) == 1:
    print(epics[0]['title'])
" 2>/dev/null || echo ""
  )

  if [ -n "$PARENT_FROM_BD" ]; then
    SESSION_SLUG=$(slugify "$PARENT_FROM_BD")
    info "Found single parent from bd: $PARENT_FROM_BD (slug: $SESSION_SLUG)"
  fi
fi

###############################################################################
# Create Task Worktree
###############################################################################

TASK_SLUG=$(slugify "$BEAD_TITLE")

if [ -n "$SESSION_SLUG" ]; then
  BRANCH="${SESSION_SLUG}--${TASK_SLUG}"
  WORKTREE_PATH="$WORKTREES_DIR/$BRANCH"
  WORKTREE_TYPE="task"
else
  warn "No parent session found for $BEAD_ID. Creating standalone worktree."
  BRANCH="$TASK_SLUG"
  WORKTREE_PATH="$WORKTREES_DIR/$TASK_SLUG"
  WORKTREE_TYPE="standalone"
  SESSION_SLUG=""
fi

# Safety: refuse to nest inside an existing worktree
case "$WORKTREE_PATH" in
  "$WORKTREES_DIR"/*/*)
    die "Refusing to create nested worktree: $WORKTREE_PATH. All worktrees must be direct children of .worktrees/."
    ;;
esac

# Already exists?
if [ -d "$WORKTREE_PATH" ]; then
  info "Worktree already exists: $WORKTREE_PATH"
  echo "WORKTREE_PATH=$WORKTREE_PATH"
  echo "WORKTREE_BRANCH=$BRANCH"
  echo "WORKTREE_TYPE=$WORKTREE_TYPE"
  echo "SESSION_SLUG=$SESSION_SLUG"
  exit 0
fi

# Check if branch already exists
if git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/$BRANCH" 2>/dev/null; then
  die "Branch '$BRANCH' already exists but no worktree at $WORKTREE_PATH. Resolve manually."
fi

info "Creating $WORKTREE_TYPE worktree: $WORKTREE_PATH (branch: $BRANCH)"
git -C "$REPO_ROOT" worktree add "$WORKTREE_PATH" -b "$BRANCH" \
  || die "git worktree add failed"

echo "WORKTREE_PATH=$WORKTREE_PATH"
echo "WORKTREE_BRANCH=$BRANCH"
echo "WORKTREE_TYPE=$WORKTREE_TYPE"
echo "SESSION_SLUG=$SESSION_SLUG"
exit 0
