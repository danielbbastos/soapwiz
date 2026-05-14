# Demystify SwiftUI Performance (WWDC23) - Summary

Context: WWDC23 session on building a mental model for SwiftUI performance and triaging hangs/hitches.

## Performance Loop

- Measure → Identify → Optimize → Re-measure
- Focus on concrete symptoms (slow navigation, broken animations, janky scrolling)

## Update Process Internals

SwiftUI's view update follows a three-step process:

```
┌─────────────────────────────────────────────────────────────┐
│                     UPDATE PROCESS                          │
├─────────────────────────────────────────────────────────────┤
│  1. PRODUCE VIEW VALUE                                      │
│     └── Stored properties + initial dynamic property values │
│                                                             │
│  2. UPDATE DYNAMIC PROPERTIES                               │
│     └── Replace initial values with current graph values    │
│     └── @State, @Binding, @Environment, @Query, etc.        │
│                                                             │
│  3. RUN BODY                                                │
│     └── Produce child views                                 │
│     └── Recurse only for children with changed values       │
└─────────────────────────────────────────────────────────────┘
```

**Key insight**: The update only recurses into child views that have *actually changed*.

### What Triggers an Update

A view's `body` is re-evaluated when:
- Its stored properties (passed from parent) change
- Any dynamic property it depends on changes (`@State`, `@Binding`, `@Environment`, `@ObservedObject`, `@Query`, etc.)

## Dependencies and Updates

- Views form a dependency graph; dynamic properties are a frequent source of updates
- Use `Self._printChanges()` in debug only to inspect extra dependencies
- Eliminate unnecessary dependencies by extracting views or narrowing state
- Use `@Observable` for granular property-level tracking

## Debugging with `_printChanges()`

### LLDB Workflow

1. Set a breakpoint in the view's `body` property
2. When breakpoint hits, type in LLDB console:
   ```
   po Self._printChanges()
   ```
3. Analyze the output to understand what triggered the update

### Output Meanings

| Output | Meaning |
|--------|---------|
| `@Self` | View value changed (stored properties passed from parent) |
| `_propertyName` | That specific dynamic property changed |
| Multiple items | Multiple dependencies changed simultaneously |

**`_printChanges()` has runtime impact — debug only, never ship.**

```swift
var body: some View {
    #if DEBUG
    let _ = Self._printChanges()
    #endif
    Text(ingredient.name)
}
```

## Common Causes of Slow Updates

- Expensive view bodies (string interpolation, filtering, formatting)
- Dynamic property instantiation and state initialization in `body`
- Slow identity resolution in lists
- Hidden work: heap allocations, repeated string construction

## Constant View Count Pattern (Critical for Lists)

**Formula**: `total rows = elements × views per element`

For List performance, each `ForEach` element must produce a **constant number** of views.

### BAD: Variable View Count (0 or 1)
```swift
// ❌ Forces SwiftUI to build ALL cells to count rows
ForEach(batches) { batch in
    if batch.isExpired {
        BatchRow(batch: batch)
    }
}
```

### BAD: Unknown View Count
```swift
// ❌ AnyView hides structure; count unknown
ForEach(batches) { batch in
    AnyView(conditionalContent(for: batch))
}
```

### OK But Costly: Inline Filtering
```swift
// ⚠️ O(n) filter runs every render
ForEach(batches.filter { $0.isExpired }) { batch in
    BatchRow(batch: batch)
}
```

### GOOD: Pre-filtered Collection
```swift
// ✅ Cache filter result in model/view model
ForEach(expiredBatches) { batch in
    BatchRow(batch: batch)  // Always 1 view per element
}
```

### Sectioned Lists Are Fine
```swift
// ✅ Section structure is constant
ForEach(categories) { category in
    Section(header: Text(category.name)) {
        ForEach(category.ingredients) { ingredient in
            IngredientRow(ingredient: ingredient)
        }
    }
}
```

## Dependency Reduction Patterns

### Extract Only Needed Data
```swift
// ❌ BAD — view depends on entire ingredient object
struct IngredientCard: View {
    let ingredient: Ingredient
    var body: some View {
        IngredientImage(ingredient: ingredient)
    }
}

// ✅ GOOD — view depends only on what it reads
struct IngredientCard: View {
    let ingredient: Ingredient
    var body: some View {
        IngredientImage(name: ingredient.name)
    }
}
```

### Extract Subviews to Isolate Dependencies
```swift
// ✅ Extracted header only re-evaluates when name/category changes
struct IngredientDetail: View {
    @State var ingredient: Ingredient

    var body: some View {
        VStack {
            IngredientHeader(name: ingredient.name, category: ingredient.category)
            BatchListView(batches: ingredient.batches)
        }
    }
}
```

## Avoid Slow Initialization in View Bodies

```swift
// ✅ Defer async work to .task
struct IngredientListView: View {
    @State var model = IngredientViewModel()

    var body: some View {
        List(model.ingredients) { IngredientRow(ingredient: $0) }
            .task { await model.load() }
    }
}
```

## Lists and Tables Identity Rules

- Stable identity is critical for performance and animation
- Constant number of views per `ForEach` element
- Avoid inline filtering in `ForEach` — pre-filter and cache
- Avoid `AnyView` in list rows

## iOS 17+ Changes

- iOS 17 includes significant internal optimizations for filtering in lists and scroll performance
- `@Observable` (introduced iOS 17) provides property-level dependency tracking, reducing unnecessary re-evaluations compared to `ObservableObject`

---

**Source**: [WWDC23 - Demystify SwiftUI Performance](https://developer.apple.com/videos/play/wwdc2023/10160/)
