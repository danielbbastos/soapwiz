# Decompose

Run this when a task is large enough to need a structured breakdown before starting.

## When to Use

- Feature touches more than 3 files
- Requires both a new model and new views
- Has a dependency chain (model → service → view)
- You're unsure of the order of work

For smaller tasks, use `plan-feature` instead.

## 4-Phase Workflow

### Phase 1 — Gather context
- Read CLAUDE.md and relevant existing files
- Understand the full scope: what models, views, and relationships are affected
- Do NOT propose anything yet

### Phase 2 — Present decomposition
Produce a numbered breakdown organized by dependency layers:

```
Layer 1 (no dependencies):
  1. <task> — what it does
  2. <task> — what it does

Layer 2 (depends on Layer 1):
  3. <task> — what it does

Layer 3 (depends on Layer 2):
  4. <task> — what it does
```

State what can be parallelized. **Wait for user approval before Phase 3.**

### Phase 3 — Create the plan document
After approval, write `PLAN_<FEATURE>.md` in the project root with:
- Overview and goal
- Key concepts and data model changes
- Ordered subtask list with status checkboxes

### Phase 4 — Implement
Work through subtasks in layer order. Run `self-review` after each one. Update the plan document as tasks complete.

## Key Rules

- Subtasks must be independently implementable and testable
- Dependencies flow downward only (Layer N depends on N-1 or earlier)
- Each subtask description must be self-contained — a future session should be able to work from it alone
- Never start Phase 3 without approval
