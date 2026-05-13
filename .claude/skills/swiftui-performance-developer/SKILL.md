---
name: swiftui-performance-developer
description: SwiftUI performance auditor. Use when investigating slow rendering, janky scrolling, or excessive view updates in SoapWiz.
---

# SwiftUI Performance Developer

Use this when auditing slow rendering, janky scrolling, or excessive view updates in SoapWiz.

## Core Insight

SwiftUI views are value types describing UI state — not long-lived objects. Splitting views into subviews is free. SwiftUI only re-evaluates `body` on views whose observed state changed. Performance problems come from what's inside `body`, not how many views you have.

## Code Smell Checklist

Scan for these in any SwiftUI file:

- [ ] `DateFormatter`, `NumberFormatter`, or other formatters allocated inside `body` or `ForEach`
- [ ] Filtering or sorting applied inside `ForEach` (should be precomputed or use `@Query` sort descriptors)
- [ ] `UUID()` or random values generated per render
- [ ] `GeometryReader` nested more than one level deep
- [ ] `AnyView` wrapping views inside a list — hides identity from the diffing engine
- [ ] `id: \.self` on non-`Identifiable`, non-`Hashable`-stable types
- [ ] Expensive computation directly in a computed property used by `body`

## Fixes

**Formatter per render:**
```swift
// Bad
Text(batch.dateOfPurchase, formatter: DateFormatter()) // allocates every render

// Good — computed once
private static let dateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .medium
    return f
}()
```

**Sort inside ForEach:**
```swift
// Bad
ForEach(ingredient.batches.sorted { ... }) { ... }

// Good — sort once, outside body
private var sortedBatches: [IngredientBatch] {
    ingredient.batches.sorted { $0.dateOfPurchase > $1.dateOfPurchase }
}
```

**Unstable ID:**
```swift
// Bad
ForEach(items, id: \.self)

// Good
ForEach(items) // when Identifiable, or:
ForEach(items, id: \.stableProperty)
```

## When Code Review Is Inconclusive

Profile with Instruments:
1. Run on a real device in Release mode
2. Use the **SwiftUI** Instruments template
3. Look for view body updates > 500µs and frame hitches
4. Time Profiler identifies heavy call sites

Do not optimize speculatively — profile first, then fix the measured bottleneck.
