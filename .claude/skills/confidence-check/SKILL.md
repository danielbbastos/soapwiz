---
name: confidence-check
description: Pre-implementation confidence gate. Use before starting any non-trivial feature, refactor, or bug fix to surface unknowns early.
---

# Confidence Check

Run this before implementing any non-trivial feature, refactor, or bug fix. Skip for obvious one-liners.

## The 4 Checks

| Check | Weight | Question |
|---|---|---|
| No duplicates | 30% | Does this functionality already exist somewhere in the codebase? |
| Pattern compliance | 30% | Does the approach follow the conventions in `swiftui-patterns-soapwiz`? |
| Scope is clear | 25% | Do I understand exactly what files change and why? |
| Root cause clear | 15% | For bug fixes: do I understand *why* the bug happens, not just its symptom? |

## Thresholds

- **≥ 85%** — proceed.
- **70–84%** — state the uncertainty and proceed with a note.
- **< 70%** — stop and ask the user for clarification before writing any code.

## How to Score

Each check is binary: either confident (full weight) or not (zero). Sum the weights of passing checks.

Example: duplicates ✓, patterns ✓, scope ✗, root cause n/a (not a bug fix) → 30 + 30 = 60 out of 85 applicable → 70% → state uncertainty and proceed with a note.

## Example Assessment

```
Task: Add a batch expiry date filter to the ingredient list

CHECK 1 - No Duplicates: [PASS - 30%]
  - Searched: rg "expiryFilter\|expiry.*filter" --type swift
  - Found: hasExpiredBatch and nearestUpcomingExpiry on Ingredient,
    but no filter state or filtered(_:) method in IngredientListViewModel

CHECK 2 - Pattern Compliance: [PASS - 30%]
  - Filter state goes on IngredientListViewModel (@Observable, @MainActor)
  - filtered(_:) takes [Ingredient] and returns [Ingredient] — pure function
  - InventoryFilterView uses @Bindable var model: IngredientListViewModel
  - @Query stays in the view, not the ViewModel

CHECK 3 - Scope is clear: [PASS - 25%]
  - IngredientListViewModel.swift — add ExpiryFilter enum + filter state
  - IngredientListView.swift — wire up filter button and sheet
  - InventoryFilterView.swift (new) — filter sheet UI
  - IngredientListViewModelFilterTests.swift (new) — tests for filtered(_:)

CHECK 4 - Root cause clear: [n/a — not a bug fix]

TOTAL SCORE: 85% (30+30+25 out of 85 applicable) → PROCEED
```

## Quick Checklist

```
CONFIDENCE CHECK:
[ ] No duplicate functionality found (30%)
[ ] Follows @Observable ViewModel + @Query in view patterns (30%)
[ ] Scope is clear — know exactly which files change and why (25%)
[ ] Root cause understood — for bug fixes only (15%)

Score: ___% → [PROCEED / note uncertainty and proceed / STOP and ask]
```

## Skip Conditions

- Typo or trivial rename
- User provided an explicit, step-by-step instruction with no ambiguity
