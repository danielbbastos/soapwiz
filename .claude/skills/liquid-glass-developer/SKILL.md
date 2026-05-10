# Liquid Glass Developer (iOS 26+)

Use this when implementing iOS 26 Liquid Glass effects in SwiftUI.

## Critical Rules

1. **Container grouping** — glass elements must be grouped within a `GlassEffectContainer` for unified composition
2. **Morphing IDs** — elements that appear/disappear require a `glassEffectID` for smooth transitions
3. **No separate clip** — glass effects define their own shape; never add `clipShape()` on top
4. **Navigation layer only** — glass styling applies to floating controls (FAB, toolbars), never to content views

## SwiftUI Patterns

**Static glass element:**
```swift
Button("Add") { ... }
    .glassEffect()
```

**Interactive (touch feedback):**
```swift
Button("Add") { ... }
    .glassEffect(.regular.interactive())
```

**Morphing between states (requires matching namespace):**
```swift
@Namespace var glass

// Element A
view.glassEffect(.regular, in: .capsule, id: "fab", namespace: glass)

// Element B (same ID = morphs)
view.glassEffect(.regular, in: .capsule, id: "fab", namespace: glass)
```

**Container (required when grouping multiple glass elements):**
```swift
GlassEffectContainer {
    // glass-styled views here
}
```

## When to Apply

- FAB (`+` button) on list views — good candidate for glass
- Bottom toolbars / action bars
- Modal sheet drag handles

## When NOT to Apply

- List rows or content cells
- Form fields
- Any view that is primarily content, not navigation/control

## Backward Compatibility

Use `#available(iOS 26, *)` guards. On older OS versions, fall back to standard button styles — the glass modifiers handle this automatically when used with the provided APIs.

## Gate on Explicit Request

Do not apply Liquid Glass effects speculatively. Only add them when the user explicitly asks, or when implementing a view that is clearly a floating control.
