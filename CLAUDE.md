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

1. **Ingredient inventory** — add ingredients, track quantities per purchase, low-stock and expiry warnings.
2. **Purchase tracking** — each ingredient purchase is a separate record with its own quantity, price, dates, and metadata. Total remaining is the sum across all purchases.
3. **Recipes** — soap formulas with lye calculation (NaOH/KOH, purity, superfat, water parts), fragrance %, end products, cost breakdown, and soap property stats from fatty-acid profiles.
4. **Batches** — making a batch from a recipe deducts ingredient quantities from purchases (FIFO) and records an immutable production snapshot with costs (History tab).
5. **Settings** — manage categories, providers, storage locations, and app-wide settings.

**Stack:** Swift, SwiftUI, SwiftData, iOS 18+. iOS 26 Liquid Glass features are gated with `#available(iOS 26, *)`. No external dependencies.

## Building

```bash
open SoapWiz.xcodeproj
```

```bash
xcodebuild -project SoapWiz.xcodeproj \
  -scheme SoapWiz \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
  build
```

```bash
xcodebuild -project SoapWiz.xcodeproj \
  -scheme SoapWiz \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
  test
```

**Note:** The project uses `PBXFileSystemSynchronizedRootGroup` (Xcode 16+). Any Swift file created inside `SoapWiz/` is automatically included in the build — no `project.pbxproj` editing needed.

## Project Structure

```
SoapWiz/                        ← source root (auto-synced by Xcode)
├── Models/                     ← SwiftData @Model entities + value types
│   ├── Ingredient.swift           ← name, code, category, unit, sap values, density, purchases[]
│   ├── IngredientPurchase.swift   ← one purchase: provider, dates, qty, price, remainingAmount
│   ├── Recipe.swift               ← soap formula: lye, water, superfat, ingredients[], products[]
│   ├── RecipeIngredient.swift / RecipeProduct.swift
│   ├── Batch.swift                ← immutable production run (recipeName copy, totalCost)
│   ├── BatchLineItem.swift        ← per-batch snapshot of consumed ingredient + cost
│   ├── IngredientCategory.swift / Provider.swift / StorageLocation.swift / AppSettings.swift
│   ├── IngredientUnit.swift / ProductUnit.swift / UnitConversion.swift  ← unit enums + conversion
│   └── FattyAcidProfile.swift / SoapPropertyRanges.swift                ← soap chemistry
├── ViewModels/                 ← @Observable @MainActor, one per screen
│   └── Inventory/  Recipes/  Batches/  Settings/
├── Views/
│   ├── ContentView.swift          ← root TabView: Inventory · Recipes · History · Settings
│   ├── Inventory/  Recipes/  Batches/  Settings/
│   └── Components/                ← FloatingActionButton, View+iOS26
├── Navigation/
│   └── AppNavigation.swift        ← @Observable tab/navigation state, injected via .environment
├── Extensions/                 ← e.g. Binding+DecimalOnly
├── DataSeeder.swift            ← seeds demo data into an empty store
└── SoapWizApp.swift            ← @main, ModelContainer (full schema), dev-only store reset on schema change
```

## Data Model

### `Ingredient`
| Property | Type | Notes |
|---|---|---|
| `name` | `String` | |
| `code` | `String` | Internal reference code |
| `category` | `IngredientCategory?` | Relationship |
| `unit` | `String` | Base unit for all purchases (e.g. "g", "ml") |
| `lowStockThreshold` | `Double?` | Drives computed `isLowStock` |
| `sapValue` / `kohSapValue` | `Double?` | Saponification values for lye calculation |
| `density` | `Double?` | Volume↔mass conversion |
| `fattyAcidProfile` | `FattyAcidProfile?` | Drives soap property stats |
| `purchases` | `[IngredientPurchase]` | `@Relationship(deleteRule: .cascade)` |
| `recipeIngredients` | `[RecipeIngredient]` | `.cascade` |
| `batchLineItems` | `[BatchLineItem]` | `.nullify` — batch history outlives the ingredient |
| `totalRemaining` | `Double` | Computed — sum of `purchase.remainingAmount` |
| `isLowStock` / `hasExpiredPurchase` / `nearestUpcomingExpiry` | | Computed warnings |

### `IngredientPurchase`
| Property | Type | Notes |
|---|---|---|
| `ingredient` | `Ingredient?` | Back-reference (set via relationship) |
| `provider` | `Provider?` | Relationship |
| `dateOfPurchase` | `Date` | |
| `quantity` | `Double` | Original amount in this purchase |
| `totalPrice` | `Double` | Full price paid |
| `badge` | `String` | Lot identifier |
| `journalCode` | `String` | Internal reference |
| `expiryDate` | `Date?` | |
| `openingDate` | `Date?` | |
| `remainingAmount` | `Double` | Starts equal to `quantity`; decremented on use |
| `storageLocation` | `StorageLocation?` | Relationship |
| `pricePerUnit` | `Double` | Computed — `totalPrice / quantity` |

### Other models (summary)

- **`Recipe`** — soap formula: `weightUnit`, `totalOilWeight`+`oilWeightUnit`, `lyeType`/`lyePurity`, `waterParts`, `superFat`, `fragrancePercentage`; `lyeIngredient` (`.nullify`), `ingredients[]` and `products[]` (`.cascade`), `batches[]` (`.nullify` — batch history outlives the recipe).
- **`RecipeIngredient` / `RecipeProduct`** — line items of a recipe (ingredient amounts; end products).
- **`Batch`** — immutable production run: `recipeName` (stored copy), `dateCreated`, `batchCount`, `totalCost`; `lineItems[]` (`.cascade`); soft link back to `recipe`.
- **`BatchLineItem`** — snapshot of one ingredient consumed by a batch, with cost at the time of making.
- **`IngredientCategory` / `Provider` / `StorageLocation`** — lookup entities managed in Settings.
- **`AppSettings`** — singleton, resolved at launch via `AppSettings.resolve(in:)`.

## Key Patterns

- Root view is `ContentView`: a `TabView` with Inventory, Recipes, History (batches), and Settings tabs. Tab/navigation state lives in `AppNavigation` (`@Observable`), injected via `.environment()`.
- Each tab's list view is wrapped in its own `NavigationStack`.
- ViewModels are `@Observable @MainActor`, one per screen, under `ViewModels/<Feature>/`.
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
Available simulator: **iPad Air 11-inch (M2)** — ID `BD145A0B-D38F-48F7-87CB-735E850987FF`  
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
