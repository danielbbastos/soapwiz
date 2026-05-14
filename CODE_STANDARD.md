# Code Standard

Mechanical rules enforced on every code change. Each rule is grep-able and has a clear remediation.
When the agent struggles with a rule, the fix is encoding it here — not "trying harder."

*Inspired by: [Harness Engineering: Codex](https://openai.com/index/harness-engineering/) — "golden principles" pattern*

## How to Use

**Before submitting code**: Run the self-review skill against this file.
**When reviewing PRs**: Check diff against these invariants.
**When a new pattern violation recurs**: Add it here with grep pattern + remediation.

---

## SwiftUI API Invariants

### No `foregroundColor()` — use `foregroundStyle()`
- **Grep**: `\.foregroundColor\(`
- **Why**: Deprecated in iOS 16+
- **Fix**: Replace with `.foregroundStyle(Color.primary)` or any `ShapeStyle`

### No `NavigationView` — use `NavigationStack`
- **Grep**: `NavigationView`
- **Why**: Deprecated in iOS 16+
- **Fix**: Replace with `NavigationStack`

### No `cornerRadius()` — use `clipShape()`
- **Grep**: `\.cornerRadius\(`
- **Why**: Deprecated
- **Fix**: `.clipShape(.rect(cornerRadius: 16))`

### No `onTapGesture` for single taps — use `Button`
- **Grep**: `\.onTapGesture\s*\{` (without `count:` parameter)
- **Why**: Not accessible to VoiceOver
- **Fix**: Wrap in `Button { } label: { }` with `.buttonStyle(.plain)` if no visual styling needed
- **Exception**: Combined gestures (tap + long press), multi-tap (`count: 2+`), inside existing Button

## Architecture Invariants

### No business logic in Views
- **Grep**: Manual review — look for service calls, data transformation, or conditional logic beyond simple view branching in `View` bodies
- **Why**: MVVM violation
- **Fix**: Move to ViewModel (`@Observable`, `@MainActor`)

### No `Group` with lifecycle modifiers on conditional content
- **Grep**: `Group\s*\{` near `.onAppear` or `.task`
- **Why**: `Group` distributes modifiers — callbacks fire multiple times when branches switch
- **Fix**: Extract to `@ViewBuilder` computed property

### No nested types inside Views
- **Grep**: `struct.*View.*\{` containing `enum` or `struct` definitions
- **Why**: Project convention — extract to top-level with descriptive name
- **Fix**: `IngredientFilterMode` instead of `IngredientListView.FilterMode`

### No `@Query` in ViewModels — `@Query` belongs in Views
- **Grep**: `@Query` inside classes
- **Why**: SwiftData `@Query` is a property wrapper that only works in SwiftUI views
- **Fix**: Pass fetched data into the ViewModel via a method or keep `@Query` in the view

## Design System Invariants

### No hardcoded colors
- **Grep**: `Color\(red:` or `Color\(hex:` or `#[0-9a-fA-F]{6}` or `UIColor\(red:`
- **Why**: Bypasses semantic color system, breaks dark mode
- **Fix**: Use semantic SwiftUI colors — `Color.primary`, `Color.secondary`, `Color.accentColor`, `.background`, `.foreground`, `Color(.systemBackground)`, `Color(.label)`, etc.

### No hardcoded font sizes
- **Grep**: `\.font\(.system\(size:` or `Font.system(size:`
- **Why**: Bypasses consistent typography
- **Fix**: Use SwiftUI semantic fonts — `.font(.body)`, `.font(.headline)`, `.font(.caption)`, `.font(.title2)`, etc.

### Custom icons must use the asset catalog
- **Grep**: `Image(systemName:` used for icons that are not SF Symbols
- **Why**: Custom icons live in the asset catalog
- **Fix**: `Image("iconName")` or `Image(.iconName)` from asset catalog

## Code Quality Invariants

### No optional booleans for tri-state — use enums
- **Grep**: `:\s*Bool\?`
- **Why**: `Bool?` (true/false/nil) creates ambiguous logic — the meaning of `nil` is implicit and context-dependent (loading? not determined? unknown?)
- **Fix**: Define an enum with explicit named cases
- **Exception**: API parameters that simply pass through optionals

```swift
// ❌ WRONG — What does nil mean here?
var isEnabled: Bool?

// ✅ CORRECT — Intent is explicit
enum EnabledState {
    case enabled
    case disabled
    case loading
}
```

### No force unwraps in production code
- **Grep**: `[^/]![^=\s]` (rough — excludes `!=`, comments)
- **Why**: Runtime crash risk
- **Fix**: Use `guard let`, `if let`, or `??` with default
- **Exception**: Test code with `#require()`, truly guaranteed values (with comment explaining why)

### No `print()` statements in production code
- **Grep**: `print\(` in non-test Swift files
- **Why**: Not captured in any logging infrastructure; clutters output
- **Fix**: Remove, or use `os_log` / `Logger` for genuine diagnostic needs

### No mutating SwiftData models off `@MainActor`
- **Grep**: Manual review — look for `modelContext` usage outside `@MainActor` context
- **Why**: SwiftData model access must stay on the main thread; the project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` globally
- **Fix**: Ensure ViewModel is `@MainActor` and all model mutations happen there

## Refactoring Invariants

### All references updated when renaming
- **Check**: `rg "oldName" --type swift` returns 0 results (excluding generated files)
- **Why**: Missed references cause build failures or dead code
- **Fix**: Search and update all: production, tests, preview providers

### Unused code removed after refactoring
- **Check**: No orphaned files, unreferenced properties, or dead imports
- **Why**: Prevents bloat and confusion
- **Fix**: Search for usages, delete if unreferenced

---

## Adding New Invariants

When you encounter a recurring pattern violation:

1. **Add it here** with: rule name, grep pattern, why, fix, exceptions
2. **Make it mechanical** — if it can be grepped, it can be enforced
3. **Include remediation** — the fix should be in the error message
4. **Keep it focused** — one rule per entry, no essays

The goal: every rule in this file should be verifiable without human judgment.
