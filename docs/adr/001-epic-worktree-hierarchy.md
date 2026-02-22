# ADR 001: Epic-based Worktree Hierarchy

## Status

Proposed

## Context

The claude-multiagent plugin turns Claude Code into an async coordinator that delegates work to sub-agents in git worktrees. The current model (v1.31.0) is:

- One Claude session = one feature worktree
- Coordinator `cd`s into the feature worktree
- Sub-agents get `feature--task` worktrees
- Flat structure under `.worktrees/`

This works for single-feature sessions but breaks down when:

1. **Epics require multiple related features.** A large feature (e.g., "add auth system") decomposes into sub-tasks (login form, API middleware, session management). These need coordinated merging.
2. **Multiple Claude sessions on the same repo.** If two coordinators run simultaneously, they need isolation without explicit locking.
3. **Session resume.** When a coordinator session ends and restarts, it needs to find and resume in-flight work.

The user wants a model that mirrors organizational structure: a coordinator manages multiple epics, each epic has tasks, and the hierarchy is reflected in the worktree layout.

## Decision

### The coordinator always stays on `main`

It never `cd`s into a worktree. It manages all epics from the repo root.

### Three-tier worktree hierarchy

```
main (coordinator lives here, never leaves)
│
├── .worktrees/<epic>/                    ← epic worktree (long-lived feature branch)
│   └── (accumulates merged task branches)
│
├── .worktrees/<epic>--<task>/            ← task worktree (sub-agent works here)
│   └── (short-lived, merged into epic when done)
│
└── .worktrees/<other-epic>/              ← another epic, possibly managed by another coordinator
```

### Naming convention

- Epic worktrees: `.worktrees/<epic-name>/` on branch `<epic-name>`
- Task worktrees: `.worktrees/<epic-name>--<task-slug>/` on branch `<epic-name>--<task-slug>`
- The `--` delimiter separates epic from task, making `git worktree list` and `ls .worktrees/` visually group tasks under their epic

### Merge flow (three stages)

1. **Task to Epic:** Coordinator merges `<epic>--<task>` into `<epic>`, removes task worktree, closes bd issue.
2. **Epic to Main:** When all tasks complete, coordinator merges `<epic>` into `main`, removes epic worktree, closes bd epic issue.
3. **Push:** Only happens when an epic merges to main. Epics are the unit of shipment.

### bd issue structure

- Epic = bd issue with type `epic` or a parent issue
- Tasks = bd issues that are children/dependents of the epic
- Each task maps 1:1 to a sub-agent and a task worktree

### Session lifecycle

1. Session starts on `main`. `session-start.sh` injects `<WORKTREE_SETUP>` with list of existing epic worktrees.
2. Coordinator checks bd for open epics. Offers to resume existing or create new via `AskUserQuestion`.
3. For new epic: `bd create` epic issue, `git worktree add .worktrees/<epic> -b <epic>`, break down into tasks.
4. For each task: `bd create` task issue, dispatch sub-agent with instructions to create `.worktrees/<epic>--<task>`.
5. As tasks complete: coordinator merges task into epic from main (`git -C .worktrees/<epic> merge <epic>--<task>`).
6. When epic is done: coordinator merges epic into main, pushes, cleans up.

### Why explicit locking is not necessary

Multiple coordinators on the same repo are safe without locking due to three properties:

1. **Git worktree uniqueness is atomic.** `git worktree add .worktrees/foo` fails if `.worktrees/foo` already exists. Two coordinators cannot create the same epic worktree. The worktree's existence IS the lock, enforced by git, not by us. There is no TOCTOU race because `git worktree add` is a single atomic operation that checks and creates.

2. **Epic ownership is visible via bd.** When a coordinator picks up an epic, it marks the bd issue `in_progress` with an assignee. Other coordinators see this in `bd list` and in the `<WORKTREE_SETUP>` tag (which lists existing worktrees). A second coordinator knows "auth-system is taken" because both the worktree exists AND the bd issue is assigned.

3. **Merge targets are disjoint by convention.** Coordinator A merges tasks into epic A's worktree. Coordinator B merges tasks into epic B's worktree. They never merge into each other's epics. The only shared merge target is `main`, and that only happens when an epic is complete, a deliberate, serialized operation (coordinator merges to main, pushes, then the next epic can merge).

4. **No stale lock problem.** If a coordinator session crashes, there is no lockfile to clean up. The worktree and bd issue remain, correctly reflecting "this work is in progress." The next session sees them and offers to resume. This is repair-free: the state IS the truth, not a lock that represents the state.

The combination of atomic worktree creation, bd ownership semantics, and disjoint merge targets means explicit locking would be redundant machinery that adds failure modes (stale locks, lock contention, deadlocks) without adding safety.

## Consequences

### Positive

- Multiple coordinators are safe by construction, not by convention
- Session resume is trivial: state lives in worktrees and bd, not in memory
- Clear visual hierarchy in `ls .worktrees/` and `git worktree list`
- Epics as shipment units give natural push boundaries
- Maps to familiar organizational structure (coordinator, epics, tasks)

### Negative

- Coordinator on main means it cannot use `git status` to see epic-level changes without `-C`
- More worktrees in flight means more disk usage (git worktrees share objects, so this is minimal)
- Deeper conceptual model: new users need to understand epic vs task distinction
- Merge conflicts between tasks within an epic must be resolved during task-to-epic merge

### Neutral

- This is backward-compatible. Single-task features just have one epic with one task. The overhead is one extra worktree level.
