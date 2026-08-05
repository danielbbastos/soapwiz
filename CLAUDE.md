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

**SoapWiz** is an iOS app for soap makers. Swift, SwiftUI, SwiftData, iOS 18+, no external dependencies. iOS 26 Liquid Glass features are gated with `#available(iOS 26, *)`. Features built incrementally:

1. **Ingredient inventory** — add ingredients, track quantities per purchase, low-stock and expiry warnings.
2. **Purchase tracking** — each ingredient purchase is a separate record with its own quantity, price, dates, and metadata. Total remaining is the sum across all purchases.
3. **Recipes** — soap formulas with lye calculation (NaOH/KOH, purity, superfat, water parts), fragrance %, end products, cost breakdown, and soap property stats from fatty-acid profiles.
4. **Batches** — making a batch from a recipe deducts ingredient quantities from purchases (FIFO) and records an immutable production snapshot with costs (History tab).
5. **Settings** — manage categories, providers, storage locations, and app-wide settings.

For SwiftUI/SwiftData conventions — state, forms, FAB, navigation, ViewModel structure, anti-patterns — the `swiftui-patterns-soapwiz` and `ios-dev-guidelines` skills are authoritative. Invoke them before editing any `.swift` file.

## Building

```bash
xcodebuild -project SoapWiz.xcodeproj -scheme SoapWiz \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' build   # or: test
```

**Note:** The project uses `PBXFileSystemSynchronizedRootGroup` (Xcode 16+). Any Swift file created inside `SoapWiz/` is automatically included in the build — no `project.pbxproj` editing needed.

## Invariants

- Delete rules encode intent, not convenience: `Ingredient.purchases`, `Recipe.ingredients`/`products`, and `Batch.lineItems` cascade; `Ingredient.batchLineItems`, `Recipe.batches`, and `Recipe.lyeIngredient` nullify — batch history must outlive the ingredient and the recipe.
- All SwiftData model access stays on `@MainActor`. The project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` globally.
- `AppSettings` is a singleton, resolved at launch via `AppSettings.resolve(in:)`.

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
