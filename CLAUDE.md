# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Context Management

When context reaches 70%, run `/compact` preserving: current task, modified files, and pending TODOs.

## ⚠️ Critical Rules

- **Never commit or stage files** without an explicit request from the user.
- **Never run destructive git operations** (reset --hard, branch -D, force push) without explicit approval.
- **Always present an action plan** before making multi-step or multi-file changes, and wait for approval.
- **No AI signatures** in code, comments, or commit messages.
- **Always write tests** for non-trivial production code (computed properties, business logic, edge cases). Use Swift Testing (`@Suite`, `@Test`, `#expect`). Use an in-memory `ModelContainer` for SwiftData tests.

## Project Overview

**SoapWiz** is an iOS app for soap makers. Features built incrementally:

1. **Ingredient inventory** — add ingredients, track quantities per purchase.
2. **Purchase tracking** — each ingredient purchase is a separate record with its own quantity, price, dates, and metadata. Total remaining is the sum across all purchases.
3. **Soap formulas** *(planned)* — create recipes specifying ingredient amounts.
4. **Formula execution** *(planned)* — using a formula deducts ingredient quantities from purchases.

**Stack:** Swift, SwiftUI, SwiftData, iOS 18+. iOS 26 Liquid Glass features are gated with `#available(iOS 26, *)`. No external dependencies.

## Building

```bash
open SoapWiz.xcodeproj
```

```bash
xcodebuild -project SoapWiz.xcodeproj \
  -scheme SoapWiz \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  build
```

```bash
xcodebuild -project SoapWiz.xcodeproj \
  -scheme SoapWiz \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  test
```

**Note:** The project uses `PBXFileSystemSynchronizedRootGroup` (Xcode 16+). Any Swift file created inside `SoapWiz/` is automatically included in the build — no `project.pbxproj` editing needed.

## Project Structure

```
SoapWiz/                        ← source root (auto-synced by Xcode)
├── Models/
│   ├── Ingredient.swift          ← @Model: name, category, unit, purchases[]
│   └── IngredientPurchase.swift  ← @Model: provider, dates, qty, price, badge…
├── Views/
│   └── Inventory/
│       ├── IngredientListView.swift   ← root view, @Query list, FAB, bulk delete
│       ├── IngredientRowView.swift
│       ├── IngredientDetailView.swift ← summary + purchase list
│       ├── PurchaseRowView.swift
│       ├── PurchaseDetailView.swift
│       ├── IngredientFormView.swift   ← add/edit ingredient sheet
│       └── PurchaseFormView.swift     ← add/edit purchase sheet
└── SoapWizApp.swift            ← @main, ModelContainer setup
```

## Data Model

### `Ingredient`
| Property | Type | Notes |
|---|---|---|
| `name` | `String` | |
| `category` | `String` | |
| `unit` | `String` | Base unit for all purchases (e.g. "g", "ml") |
| `purchases` | `[IngredientPurchase]` | `@Relationship(deleteRule: .cascade)` |
| `totalRemaining` | `Double` | Computed — sum of `purchase.remainingAmount` |

### `IngredientPurchase`
| Property | Type | Notes |
|---|---|---|
| `ingredient` | `Ingredient?` | Back-reference (set via relationship) |
| `provider` | `String` | |
| `dateOfPurchase` | `Date` | |
| `quantity` | `Double` | Original amount in this purchase |
| `totalPrice` | `Double` | Full price paid |
| `badge` | `String` | Lot identifier |
| `journalCode` | `String` | Internal reference |
| `expiryDate` | `Date?` | |
| `openingDate` | `Date?` | |
| `remainingAmount` | `Double` | Starts equal to `quantity`; decremented on use |
| `storageLocation` | `String` | |
| `pricePerUnit` | `Double` | Computed — `totalPrice / quantity` |

## Key Patterns

- Root view is `IngredientListView`, wrapped in `NavigationStack`.
- `ModelContainer` is configured once in `SoapWizApp` and injected via `.modelContainer()`.
- FAB (floating `+` button) is used consistently across list views. It hides when `editMode == .active`.
- `PurchaseFormView` accepts an optional `purchase` parameter — `nil` = create, non-nil = edit.
- `IngredientFormView` accepts an optional `ingredient` parameter — same pattern.

## Git Workflow

- Main branch: `main`
- Feature branches: `feature/short-description`
- Commit messages: imperative, lowercase, no period

## Simulator Testing

Available simulator: **iPad (A16)** — ID `34E90319-8EDC-4B0F-BA5F-81650ED7AAE3`  
Available simulator: **iPhone 15 Pro** — use for `xcodebuild test`

**⚠️ Always uninstall before reinstalling when the SwiftData schema has changed.** Reinstalling over an existing app with an incompatible schema causes a crash on launch. The correct sequence is:

```bash
xcrun simctl terminate <id> pt.daphnia.SoapWiz
xcrun simctl uninstall <id> pt.daphnia.SoapWiz
xcrun simctl install <id> <path-to.app>
xcrun simctl launch <id> pt.daphnia.SoapWiz
```

Build output path: `~/Library/Developer/Xcode/DerivedData/SoapWiz-*/Build/Products/Debug-iphonesimulator/SoapWiz.app`

## ⚠️ Common Mistakes

- **Forgetting the cascade delete rule** on `Ingredient.purchases` — orphaned purchases accumulate silently.
- **Mutating SwiftData models off `@MainActor`** — all model access must stay on the main thread. The project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` globally.
- **Using `@State` for persisted data** — use `@Query` for anything that lives in SwiftData.
- **Sorting `ingredient.purchases` directly in views** — purchases are unordered in SwiftData; always sort before display (currently by `dateOfPurchase` descending).
- **Discarding `ModelContainer` in tests** — never do `let ctx = try makeContainer().mainContext`; the container is released immediately and `ctx.insert()` hangs on a dead backing store. Always store the container: `let (container, ctx) = try makeContext(); _ = container`.
- **Hardcoding locale-sensitive strings in test assertions** — never hardcode `"123.5"` when testing formatted numbers; use the same formatter the production code uses so the test passes on any locale.
