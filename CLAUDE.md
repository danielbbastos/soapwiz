# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## ⚠️ Critical Rules

- **Never commit or stage files** without an explicit request from the user.
- **Never run destructive git operations** (reset --hard, branch -D, force push) without explicit approval.
- **Always present an action plan** before making multi-step or multi-file changes, and wait for approval.
- **No AI signatures** in code, comments, or commit messages.

## Project Overview

**daphnia** (Xcode project: `SoapGen`) is an iOS app for soap makers. Core features, built incrementally:

1. **Ingredient inventory** — add ingredients, set units, track quantities on hand.
2. **Usage tracking** — record how much of each ingredient is consumed.
3. **Soap formulas** — create recipes specifying ingredient amounts.
4. **Formula execution** — using a formula automatically deducts ingredient quantities from inventory.

**Stack:** Swift, SwiftUI, SwiftData. No external dependencies.

## Quick Start

```bash
open SoapGen/SoapGen.xcodeproj
```

Command-line build:
```bash
xcodebuild -project SoapGen/SoapGen.xcodeproj \
  -scheme SoapGen \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  build
```

Run tests:
```bash
xcodebuild -project SoapGen/SoapGen.xcodeproj \
  -scheme SoapGen \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  test
```

**Requirements:** Xcode 16+, iOS 17+ target (SwiftData requires iOS 17).

## Architecture

The app follows **MVVM** with SwiftData as the single source of truth. SwiftUI views observe the model container directly via `@Query` and `@Environment(\.modelContext)`.

```
SoapGen/
├── Models/          # SwiftData @Model classes
├── Views/           # SwiftUI screens and components
│   ├── Inventory/   # Ingredient list and detail views
│   ├── Formulas/    # Formula list, creation, and detail views
│   └── Common/      # Shared UI components
└── App/             # App entry point, ModelContainer setup
```

### Data Model

| Model | Key Fields |
|---|---|
| `Ingredient` | `name`, `unit`, `quantityOnHand` |
| `Formula` | `name`, `notes`, `entries: [FormulaEntry]` |
| `FormulaEntry` | `ingredient: Ingredient`, `amount: Double` (join table) |
| `ProductionRun` | `formula: Formula`, `date`, `multiplier` (records a batch use; triggers deduction) |

### Key Patterns

- Model container is configured once in the `@main` App struct and injected via the environment.
- Mutations always go through `modelContext.insert()` / property assignment — SwiftData handles persistence automatically.
- Views use `@Query` for live, filtered lists; avoid fetching manually unless sorting/filtering logic requires it.
- `FormulaEntry` is the join between `Formula` and `Ingredient`; deleting a formula should cascade-delete its entries.

## Git Workflow

- Main branch: `main`
- Feature branches: `feature/short-description` (e.g. `feature/ingredient-inventory`)
- Commit messages: imperative, lowercase, no period (e.g. `add ingredient detail view`)
- PRs: short title + 1–3 bullet summary of what changed and why.

## 🔒 Pre-Implementation Checklist

Before writing code for any non-trivial feature:

- [ ] Is there an existing model or view that already covers this? (avoid duplication)
- [ ] Does the change touch the data model? If yes, consider migration impact.
- [ ] Does the UI follow the existing navigation and component patterns?
- [ ] Are all SwiftData relationships marked with the correct `@Relationship` delete rules?

## ⚠️ Common Mistakes

- **Forgetting delete rules** on `@Relationship` — orphaned `FormulaEntry` records will accumulate silently.
- **Mutating model objects off the main actor** — SwiftData model context is `@MainActor`; always update on the main thread.
- **Using `@State` for derived data** that should come from `@Query` — prefer `@Query` for anything persisted.
- **Hardcoding units** — the unit system should be data-driven so users can add custom units later.
