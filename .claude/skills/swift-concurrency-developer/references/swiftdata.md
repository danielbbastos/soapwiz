# SwiftData + Concurrency

Patterns for using SwiftData safely with Swift Concurrency in SoapWiz.

## Project Baseline

SoapWiz sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, which means all SwiftData operations naturally stay on the main actor. This simplifies everything — there is no background context to manage for typical CRUD work.

## Core Rules

### 1. ModelContext stays on @MainActor

```swift
// ✅ CORRECT — all model operations on main actor (default in SoapWiz)
@Observable
@MainActor
final class IngredientListViewModel {
    func deleteIngredient(_ ingredient: Ingredient, context: ModelContext) {
        context.delete(ingredient)
        try? context.save()
    }
}

// ❌ WRONG — accessing ModelContext off main actor
Task.detached {
    context.delete(ingredient)  // Crash: ModelContext is not Sendable
}
```

### 2. Never pass @Model instances across actor boundaries

`@Model` objects are not `Sendable`. Passing them across isolation boundaries causes data races and compiler errors.

```swift
// ❌ WRONG — sending model instance across actor boundary
Task.detached {
    await process(ingredient)  // Error: Ingredient is not Sendable
}

// ✅ CORRECT — pass the identifier, re-fetch in the target context
let ingredientID = ingredient.persistentModelID
Task.detached {
    await processIngredient(withID: ingredientID)
}

@MainActor
func processIngredient(withID id: PersistentIdentifier) {
    guard let ingredient = modelContext.model(for: id) as? Ingredient else { return }
    // work with ingredient on main actor
}
```

### 3. @Query belongs in views, not ViewModels

`@Query` is a SwiftUI property wrapper that auto-fetches and observes changes. It only works inside `View` structs.

```swift
// ✅ CORRECT — @Query in view
struct IngredientListView: View {
    @Query private var ingredients: [Ingredient]
    var model: IngredientListViewModel

    var body: some View {
        List(model.filtered(ingredients)) { ... }
    }
}

// ❌ WRONG — @Query in ViewModel (won't compile)
@Observable final class IngredientListViewModel {
    @Query var ingredients: [Ingredient]  // Error
}
```

### 4. Don't replicate @Query with manual Task polling

```swift
// ❌ WRONG — manual polling duplicates what @Query already does
.task {
    while true {
        ingredients = try? modelContext.fetch(FetchDescriptor<Ingredient>())
        try? await Task.sleep(for: .seconds(5))
    }
}

// ✅ CORRECT — let @Query handle observation
@Query private var ingredients: [Ingredient]
```

## Background Processing Pattern

If you need to do heavy computation on ingredient data without blocking the UI, copy the data out of the model layer first, then process it off-main:

```swift
@MainActor
func runExpensiveAnalysis() async {
    // 1. Extract plain data on main actor (fast)
    let snapshot = ingredients.map { IngredientSnapshot(from: $0) }

    // 2. Do heavy work off main actor
    let results = await Task.detached(priority: .userInitiated) {
        analyzeSnapshot(snapshot)  // Works on plain Sendable structs
    }.value

    // 3. Apply results back on main actor
    applyResults(results)
}

// Plain Sendable struct — safe to pass across boundaries
struct IngredientSnapshot: Sendable {
    let id: PersistentIdentifier
    let name: String
    let totalRemaining: Double
}
```

## Deletion and Cascade

Always delete through the `ModelContext` — never nil out relationships manually.

```swift
// ✅ CORRECT — context handles cascade
modelContext.delete(ingredient)  // Cascades to ingredient.purchases automatically

// ❌ WRONG — orphans purchases
ingredient.purchases = []  // Purchases remain in the store as orphans
```

## Common Errors

| Error | Cause | Fix |
|-------|-------|-----|
| `Ingredient is not Sendable` | Passing model across actor boundary | Pass `PersistentIdentifier` instead |
| `ModelContext used from wrong thread` | Background task accessing context | Move to `@MainActor` |
| Stale data after save | Forgot to call `context.save()` | Call `try? context.save()` after mutations |
| Orphaned batches accumulate | Nil-ing relationship instead of deleting | Use `context.delete(ingredient)` |
