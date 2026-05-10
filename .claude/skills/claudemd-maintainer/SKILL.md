# CLAUDE.md Maintainer

Run this when asked to update, audit, or improve CLAUDE.md.

## Core Rules

- **100–150 lines target**, 300 absolute ceiling. Past that, LLM instruction-following degrades.
- **Manual crafting only** — no auto-generated summaries or scaffolded boilerplate.
- **Universal scope only** — include guidance that applies across most tasks. Task-specific instructions belong in skills.
- **Reference, don't embed** — link to file paths rather than inlining code that rots.
- **One authoritative location** — critical rules live in a single place, never duplicated.

## What Belongs

✅ Include:
- Technology stack and architecture overview
- Essential build/run commands
- Must-follow behavioral rules (no commit without request, no destructive ops, etc.)
- Real-world mistakes that have actually caused problems

❌ Exclude:
- Code style (handled by linters/patterns skill)
- Exhaustive command references
- Task-specific instructions (move to skills)
- Inline code snippets (reference the file instead)

## Three-Level Structure

1. **CLAUDE.md** — critical essentials only
2. **`.claude/skills/`** — domain-specific guidance invoked per task
3. **Inline code files** — source of truth for patterns

## When Updating

1. Read current CLAUDE.md fully before touching anything.
2. Identify what's stale, redundant, or missing.
3. Present a diff-style summary of proposed changes.
4. Wait for approval before editing.
5. Keep the file under the line limit after edits.
