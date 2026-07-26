---
name: decompose
description: Break a large feature into independent subtasks. Use when the work touches more than 3 files, needs both new models and new views, or has a model→ViewModel→view dependency chain. Produces plans/PLAN_SW-XX.md plus Linear sub-issues. For a single-pass feature use plan-feature instead.
---

# Task Decomposition (Workflow)

## Purpose

Break down a large feature or task into independent, implementable subtasks. Produces a `PLAN_SW-XX.md` in the `plans/` directory and creates Linear sub-issues — all designed so future Claude sessions can pick up any subtask with full context.

## When to Use

- Feature touches more than 3 files
- Requires both new models and new views
- Has a dependency chain (model → ViewModel → view)
- You're unsure of the order of work
- Keywords: decompose, break down, split task, subtasks, plan feature

For smaller tasks, use `plan-feature` instead.

## Workflow

### Phase 1 — Gather Context (parallel)

Collect ALL of the following before proposing anything:

1. **Parent Linear issue** — read via `mcp__linear__get_issue` (with `includeRelations: true`)
2. **Comments on the issue** — `mcp__linear__list_comments` for any decisions or constraints already discussed
3. **Existing PRs/branches** — check `gh pr list` and `git branch -a` for work already started
4. **Codebase exploration** — use Agent(Explore) to understand the area being changed. Focus on:
   - Models (`@Model` types and their relationships)
   - ViewModels (`@Observable`, `@MainActor` classes)
   - Views (SwiftUI, existing patterns)
   - Tests (existing coverage and patterns)

Do NOT propose anything yet.

### Phase 2 — Propose Decomposition

Present the breakdown as a numbered list organized in **dependency layers**:

```
### Layer 0: Foundation (no dependencies)
1. Task A — brief description
2. Task B — brief description

### Layer 1: Components (depends on Layer 0)
3. Task C — brief description. Depends on: #1
4. Task D — brief description. Depends on: #2

### Layer 2: Integration (depends on Layer 1)
5. Task E — brief description. Depends on: #3, #4
```

Include a simple ASCII dependency graph and call out what can be parallelised.

**Decomposition principles:**
- Each subtask must be independently implementable and testable
- Each subtask gets its own branch and PR
- Subtasks in the same layer can be done in parallel
- Dependencies flow downward only (Layer N depends on Layer N-1 or earlier)
- Prefer small, focused subtasks over large ones
- Separate model changes from ViewModel logic from View work
- Separate reusable components from feature orchestration
- Edge cases and polish go in the last layer

**Wait for user approval before proceeding to Phase 3.**

### Phase 3 — Create Artifacts (after approval)

#### 3a. Create PLAN_SW-XX.md

Create at `plans/PLAN_SW-XX.md` (relative to repo root) with this structure:

```markdown
# SW-XX: Feature Title

## Overview
What the feature does and why. 2–3 paragraphs max.

**Linear**: <link>

## Key Concepts
Bullet list of domain terms and what they mean in this context.

## Flows
ASCII diagrams of user flows or data flows if helpful.

---

## Decomposition & Progress

### Layer 0: Foundation

#### 1. Subtask Title — [SW-YY](link)
- [ ] Checklist item 1
- [ ] Checklist item 2
- **Branch**: `sw-YY-short-description`
- **Status**: Not started

---

## Codebase Reference
Key files and entry points relevant to this feature.
```

**The plan must contain enough context that a fresh Claude session can:**
- Understand the full feature scope
- Know which files to modify
- Understand how subtasks connect
- Track progress across sessions

#### 3b. Create Linear Sub-Issues

For each subtask, create a Linear issue via `mcp__linear__save_issue` with:
- **Title**: Concise, action-oriented
- **Parent**: The original issue ID (`parentId`)
- **Team**: Same as parent
- **Priority**: High for Layer 0, Medium for others, Low for polish
- **Description** (self-contained):

```markdown
## Summary
One paragraph: what this subtask does.

## What to do
Concrete steps and key files to change.

### Dependencies
Which subtasks must be done first (if any).

### Acceptance Criteria
- [ ] Criteria 1
- [ ] Criteria 2
```

Each sub-issue must be self-contained — a fresh session should be able to work from the plan + the sub-issue alone.

#### 3c. Update Memory

Save a project memory entry noting the feature, number of subtasks, plan file path, and any key architectural decisions.

### Phase 4 — Working on Subtasks (Future Sessions)

When starting a subtask in a new session:
1. Read `plans/PLAN_SW-XX.md` — full feature context and current progress
2. Read the Linear sub-issue — specific instructions for this subtask
3. Checkout the subtask branch from `origin/main`
4. Implement, run tests, self-review
5. After PR is merged, update the status in `plans/PLAN_SW-XX.md` on the parent branch

## Common Mistakes

- **Starting Phase 3 without approval** — always wait for the user to confirm the decomposition
- **Subtasks that are too coupled** — if subtask B can't be tested without subtask A being merged, reconsider the split
- **Vague subtask descriptions** — each must be specific enough to implement without guessing
- **Forgetting to check existing work** — PRs or branches may already cover parts of the task
- **Over-decomposing** — don't create 10 subtasks for a feature that's really 3; prefer meaningful chunks over micro-tasks
