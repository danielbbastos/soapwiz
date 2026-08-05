---
name: claudemd-maintainer
description: Use when creating, editing, auditing, or trimming CLAUDE.md, project instructions, or memory/context files for Claude — including "CLAUDE.md is too long", "reduce always-loaded context", "make CLAUDE.md leaner", moving guidance out of CLAUDE.md and into a skill, or deduplicating instructions across CLAUDE.md, skills, and memory. Covers what belongs in CLAUDE.md versus a skill, length limits, and cutting content the codebase already documents.
---

# CLAUDE.md Maintainer (Smart Router)

## Purpose
Context-aware guidance for maintaining and improving CLAUDE.md files. Helps ensure the file stays effective, concise, and follows best practices for LLM instruction files.

## When Auto-Activated
- Editing or discussing CLAUDE.md
- Keywords: claude.md, project instructions, onboarding claude, context file
- Discussing documentation structure for AI assistants

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
