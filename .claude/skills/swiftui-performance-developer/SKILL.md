---
name: swiftui-performance-developer
description: SwiftUI performance auditor. Use when investigating slow rendering, janky or stuttering scrolling, frame drops, excessive view updates, a body recomputed too often, @Observable over-invalidation, a large or unfiltered @Query, slow navigation pushes, or "the app feels sluggish" — and when profiling SwiftUI with Instruments.
---

# SwiftUI Performance Developer

Use this when auditing slow rendering, janky scrolling, or excessive view updates in SoapWiz.

## Workflow Decision Tree

1. **Code provided** → Start with Code-First Review
2. **Only symptoms described** → Ask for code/context, then Code-First Review
3. **Code review inconclusive** → Guide user to profile with Instruments

## Core Insight

SwiftUI views are value types describing UI state — not long-lived objects. Splitting views into subviews is free. SwiftUI only re-evaluates `body` on views whose observed state changed. Performance problems come from what's inside `body`, not how many views you have.

```swift
// ✅ Free — SwiftUI only updates the specific subview whose state changed
var body: some View {
    VStack {
        HeaderView(title: title)
        ContentView(items: items)
        FooterView(action: saveAction)
    }
}
```

## Code-First Review

### State-Driven Updates

SwiftUI tracks dependencies automatically. Any data a view reads in `body` becomes a dependency. With `@Observable`, only properties actually read trigger re-evaluation:

```swift
@Observable class IngredientModel {
    var name: String = ""
    var isLowStock: Bool = false
}

struct IngredientRow: View {
    let ingredient: IngredientModel

    var body: some View {
        // Only re-evaluates when name or isLowStock changes
        HStack {
            Text(ingredient.name)
            if ingredient.isLowStock { LowStockBadge() }
        }
    }
}
```

### View Invalidation Storms

```swift
// BAD — broad state triggers all child views
@Observable class Model {
    var items: [Item] = []
}

// GOOD — granular per-item state scoped to leaf views
@Observable class ItemModel {
    var isFavorite: Bool = false
}
```

### Constant View Count in Lists (Critical)

For List/ForEach performance, each element must produce a **constant number** of views. Variable counts force SwiftUI to build all cells just to count rows.

```swift
// BAD — conditional produces 0 or 1 views; forces full rebuild to count rows
ForEach(purchases) { purchase in
    if purchase.isExpired {
        PurchaseRow(purchase: purchase)
    }
}

// BAD — AnyView hides structure and view count
ForEach(purchases) { purchase in
    AnyView(conditionalContent(for: purchase))
}

// GOOD — pre-filter; always 1 view per element
ForEach(expiredPurchases) { purchase in
    PurchaseRow(purchase: purchase)
}

// GOOD — constant count with conditional visibility
ForEach(purchases) { purchase in
    PurchaseRow(purchase: purchase)
        .opacity(purchase.isExpired ? 1 : 0)
}
```

### Unstable Identity in Lists

```swift
// BAD — id churn causes full re-render on every update
ForEach(items, id: \.self) { item in Row(item) }

// GOOD — stable identity
ForEach(items) { item in Row(item) } // when Identifiable
ForEach(items, id: \.id) { item in Row(item) }
```

### Heavy Work in `body`

```swift
// BAD — allocates a formatter every render
var body: some View {
    Text(purchase.dateOfPurchase, formatter: DateFormatter())
}

// GOOD — cached static formatter
private static let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    return f
}()
```

### Sorting/Filtering in ForEach

```swift
// BAD — re-sorts every body evaluation
ForEach(ingredient.purchases.sorted { $0.dateOfPurchase > $1.dateOfPurchase }) { ... }

// GOOD — sort once, outside body
private var sortedPurchases: [IngredientPurchase] {
    ingredient.purchases.sorted { $0.dateOfPurchase > $1.dateOfPurchase }
}
```

## Common Code Smells

| Pattern | Problem | Fix |
|---------|---------|-----|
| `DateFormatter()` / `NumberFormatter()` in body | Allocation per render | Static cached formatter |
| `.filter { }` or `.sorted { }` in `ForEach` | Recomputes every render | Pre-filter/sort, cache result |
| `id: \.self` on non-stable values | Identity churn | Use stable `.id` property |
| `UUID()` per render | New identity every time | Store ID in model |
| `GeometryReader` nested >1 level deep | Layout thrash | Move up or use fixed sizes |
| Conditional `if` in `ForEach` | Variable view count | Pre-filter or use `opacity` |
| `AnyView` in list rows | Hides identity and count | Use `@ViewBuilder` or concrete types |
| Expensive work in computed property used by body | Runs on every render | Precompute, cache, or use `@State` |

## Debugging with `_printChanges()`

Use `_printChanges()` to find what's triggering unexpected `body` calls:

```swift
var body: some View {
    #if DEBUG
    let _ = Self._printChanges()
    #endif
    // rest of body
}
```

**LLDB workflow**: set a breakpoint in `body`, then run `po Self._printChanges()`.

| Output | Meaning |
|--------|---------|
| `@Self` | Stored properties (passed from parent) changed |
| `_propertyName` | That specific dynamic property changed |

**Never ship `_printChanges()` to production** — it has runtime overhead.

## When Code Review Is Inconclusive

Profile with Instruments:

1. **Record**: Product > Profile, SwiftUI template (**Release** build)
2. **Reproduce**: Exact interaction (scroll, navigate, animate)
3. **Capture**: SwiftUI timeline + Time Profiler
4. **Analyze**:
   - "Long View Body Updates" — orange >500µs, red >1000µs
   - "Hitches" lane for frame misses
   - Time Profiler call tree for hot frames
5. Use **Cause & Effect Graph** ("Show Causes") to find unintended update fan-out

Do not optimize speculatively — profile first, then fix the measured bottleneck.

## Remediation Checklist

- [ ] Narrow state scope (`@State` / `@Observable` closer to leaf views)
- [ ] Stabilize `ForEach` identities
- [ ] Move heavy work out of `body` (precompute, cache, `@State`)
- [ ] Pre-filter/sort collections; never filter inside `ForEach`
- [ ] Use `equatable()` for expensive subtrees that rarely change
- [ ] Eliminate `AnyView` from list rows
- [ ] Reduce `GeometryReader` depth

## References

For detailed WWDC guidance:
- `references/demystify-swiftui-performance-wwdc23.md`
- `references/optimizing-swiftui-performance-instruments.md`
- `references/understanding-improving-swiftui-performance.md`

## Related Skills

- **ios-dev-guidelines** → General Swift/iOS patterns
- **swiftui-patterns-soapwiz** → View structure and SoapWiz conventions
