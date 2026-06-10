---
name: swiftui-patterns-soapwiz
description: SoapWiz-specific SwiftUI + SwiftData conventions. Use when writing or reviewing Swift files to apply project-wide state, persistence, FAB, and form patterns.
---

# SwiftUI + SwiftData Patterns (SoapWiz)

Apply these conventions whenever writing or reviewing Swift files in this project.

## State & Persistence

- Use `@Query` for anything stored in SwiftData — never `@State` for persisted data.
- Use `@State` only for transient, view-local UI state (sheet presentation, form fields, edit mode).
- `ModelContainer` is configured once in `SoapWizApp` and flows down via `.modelContainer()` — never create a second container.
- All SwiftData model access must stay on `@MainActor`. The project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` globally.

## Form Pattern

Every form view that can create or edit a model follows this signature:

```swift
struct ThingFormView: View {
    var thing: Thing? = nil   // nil = create, non-nil = edit
}
```

Populate local `@State` fields from `thing` in `init`. On save, either insert a new model or mutate the existing one.

## FAB Pattern

Floating action button (`+`) is used consistently on list views. It must hide when `editMode == .active`:

```swift
if editMode?.wrappedValue != .active {
    // FAB button
}
```

## Relationships & Deletion

- `Ingredient.purchases` has `deleteRule: .cascade` — always declare this or orphaned purchases accumulate silently.
- History records use `.nullify`: `Ingredient.batchLineItems` and `Recipe.batches` must outlive the ingredient/recipe they reference — never cascade them.
- Relationship arrays are unordered in SwiftData. Always sort before display:

```swift
ingredient.purchases.sorted { $0.dateOfPurchase > $1.dateOfPurchase }
```

## Naming: Purchase vs Batch

- **`IngredientPurchase`** ("purchase") = one inventory acquisition of an ingredient.
- **`Batch`** ("batch") = one production run made from a `Recipe`, with immutable `BatchLineItem` cost snapshots.
- Never use "batch" to mean an inventory purchase — that naming was retired in SW-73.

## Navigation

- Root view is `ContentView`: a `TabView` with Inventory, Recipes, History (batches), and Settings tabs.
- Tab/navigation state lives in `AppNavigation` (`@Observable`), injected via `.environment()`.
- Each tab root wraps its content in its own `NavigationStack`.
- Use `NavigationLink` for push navigation; sheets for forms/creation flows.

## Common Anti-Patterns to Avoid

- Mutating a SwiftData model off the main actor.
- Using `@State` for data that should survive view recreation.
- Forgetting `.cascade` on a relationship with child models.
- Sorting a SwiftData relationship array directly without `.sorted`.
