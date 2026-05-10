# Confidence Check

Run this before implementing any non-trivial feature, refactor, or bug fix. Skip for obvious one-liners.

## The 4 Checks

| Check | Weight | Question |
|---|---|---|
| No duplicates | 30% | Does this functionality already exist somewhere in the codebase? |
| Pattern compliance | 30% | Does the approach follow the conventions in `swiftui-patterns`? |
| Scope is clear | 25% | Do I understand exactly what files change and why? |
| Root cause clear | 15% | For bug fixes: do I understand *why* the bug happens, not just its symptom? |

## Thresholds

- **≥ 85%** — proceed.
- **70–84%** — state the uncertainty and proceed with a note.
- **< 70%** — stop and ask the user for clarification before writing any code.

## How to Score

Each check is binary: either confident (full weight) or not (zero). Sum the weights of passing checks.

Example: duplicates ✓, patterns ✓, scope ✗, root cause n/a (not a bug fix) → 30 + 30 = 60 out of 85 applicable → 70% → state uncertainty and proceed with a note.

## Skip Conditions

- Typo or trivial rename
- User provided an explicit, step-by-step instruction with no ambiguity
