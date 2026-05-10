# Self-Review

Run this automatically after writing or editing Swift files, before presenting the result to the user.

## Steps

1. **List changed files** — identify every file modified or created this session.

2. **Check each Swift file for violations:**

   **SwiftData**
   - `@State` used for a SwiftData-persisted property → replace with `@Query`
   - SwiftData model mutated inside a non-`@MainActor` closure → move to main actor
   - New `@Relationship` missing `deleteRule: .cascade` where children are owned → add it
   - Any SwiftData to-many displayed without `.sorted(...)` → add sort

   **SwiftUI state**
   - `@State` not marked `private` → add `private`
   - `@Binding` used when child only reads (doesn't write) parent state → change to `let`

   **View patterns**
   - FAB shown without checking `editMode?.wrappedValue != .active` → add guard
   - Form view that edits or creates a model but doesn't follow the `var thing: Thing? = nil` pattern → flag it

   **Deprecated APIs**
   - `.foregroundColor()` → `.foregroundStyle()`
   - `.cornerRadius()` → `.clipShape(.rect(cornerRadius:))`
   - `NavigationView` → `NavigationStack`
   - `NavigationLink(destination:isActive:)` → `NavigationLink(value:)` + `.navigationDestination`

   **Animations**
   - `.animation(...)` without an explicit `value:` parameter → add `value:`

   **Lists**
   - `ForEach` using `id: \.self` on a non-stable type → use a stable `id` property

   **Performance**
   - Formatter (`DateFormatter`, `NumberFormatter`) allocated inside `body` or `ForEach` → make `static`
   - Sort or filter applied inside `ForEach` → precompute in a private computed property

   **General**
   - Force unwrap (`!`) on an optional that could legitimately be nil → use `guard` or `if let`
   - `print()` statements left in → remove

3. **Check CLAUDE.md critical rules:**

   - No staged files without explicit user request
   - No commit created without explicit user request
   - No AI signatures in code or comments

4. **Fix silently** any violations found. Do not announce each fix individually.

5. **Proceed** without comment if everything is clean.

Only surface a note to the user if a violation requires their decision (e.g., a design choice is ambiguous).
