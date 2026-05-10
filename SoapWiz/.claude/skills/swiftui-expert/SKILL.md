# SwiftUI Expert

Use this for SwiftUI implementation, review, or improvement decisions. Prioritizes facts and best practices over architectural opinions.

## State Management — Choose the Right Wrapper

| Wrapper | Use when |
|---|---|
| `@State` | Transient, view-local UI state (sheet flags, form field drafts). Always `private`. |
| `@Binding` | Child needs to read AND write parent's state |
| `@Query` | Anything persisted in SwiftData |
| `@Environment` | Values injected from above (modelContext, editMode, colorScheme) |
| `@StateObject` / `@ObservedObject` | Observable reference types (rare in this project) |

**Never use `@State` for SwiftData-persisted data.**

## View Composition

- Keep `body` focused — extract private computed view properties or `@ViewBuilder` methods when it grows
- Views are value types; decomposing into subviews is free — do it freely
- Order inside a view: property wrappers → properties → computed props → `body` → private view builders → helpers
- Defer expensive work to `.task`, not `init`

## Animations

```swift
// Correct — explicit value parameter
.animation(.easeInOut, value: isExpanded)

// Wrong — animates everything, causes surprises
.animation(.easeInOut)
```

Use `withAnimation { }` for imperative state changes. Match the animation curve to the interaction (spring for interactive gestures, easeOut for appearance).

## Lists and Identity

- Always provide a stable `id` — never `id: \.self` on non-`Identifiable` value types
- `ForEach` over a SwiftData to-many must use `.sorted(...)` first
- Use `.onDelete` + `editMode` for list deletion; the FAB must hide when `editMode == .active`

## Deprecated APIs (avoid these)

| Old | Use instead |
|---|---|
| `.foregroundColor()` | `.foregroundStyle()` |
| `.cornerRadius()` | `.clipShape(.rect(cornerRadius:))` |
| `NavigationView` | `NavigationStack` |
| `NavigationLink(destination:isActive:)` | `NavigationLink(value:)` + `.navigationDestination` |

## iOS 26 Features

Gate with `#available(iOS 26, *)`. Do not apply Liquid Glass effects unless explicitly requested — use `liquid-glass-developer` skill for those.

## Accessibility

- Prefer `Button` over `TapGesture` — `Button` is keyboard and VoiceOver accessible by default
- Add `.accessibilityLabel` when the visible label is insufficient (icon-only buttons)
- Test with Dynamic Type — avoid fixed font sizes

## Quick Checklist

- [ ] `@State` is `private`
- [ ] No `@State` for SwiftData data
- [ ] Deprecated APIs replaced
- [ ] Lists have stable IDs
- [ ] SwiftData to-many sorted before display
- [ ] Animations use explicit `value:` parameter
- [ ] No `print()` left in
