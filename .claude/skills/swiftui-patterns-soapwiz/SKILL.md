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

- `Ingredient.batches` has `deleteRule: .cascade` — always declare this or orphaned batches accumulate silently.
- Batches are unordered in SwiftData. Always sort before display:

```swift
ingredient.batches.sorted { $0.dateOfPurchase > $1.dateOfPurchase }
```

## Navigation

- Root view is `IngredientListView` inside a `NavigationStack`.
- Use `NavigationLink` for push navigation; sheets for forms/creation flows.

## Common Anti-Patterns to Avoid

- Mutating a SwiftData model off the main actor.
- Using `@State` for data that should survive view recreation.
- Forgetting `.cascade` on a relationship with child models.
- Sorting a SwiftData relationship array directly without `.sorted`.
