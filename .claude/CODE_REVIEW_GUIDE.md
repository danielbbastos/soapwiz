# Code Review Guide

Comprehensive review standards for SoapWiz — a Swift/SwiftUI/SwiftData iOS app.

## Core Review Rules

Be LEAN and ACTIONABLE — only flag real issues, avoid noise.

- ONLY include sections when there are ACTUAL issues to report
- NO "Strengths" or praise sections
- NO "no concerns" statements (skip the section entirely)
- NO design/UI/spacing suggestions (padding, margins, colors) — you cannot see the visual design
- Reference specific `file:line` locations for every issue
- **If no issues found**: comment ONLY `✅ **Approved** - No issues found` — nothing else

## Review Sections

Include ONLY if issues exist:

### Bugs / Logic Errors
Real logic errors or potential crashes.

### Best Practices
Violations of Swift/SwiftUI/SwiftData conventions (code quality only, not design).

### Performance
Actual performance problems — not theoretical ones.

### Security
Real security vulnerabilities (e.g. storing sensitive data in UserDefaults unencrypted).

## Summary Format

End with ONE sentence only:

- ✅ **Approved** — [brief reason]
- ⚠️ **Minor Issues** — [what needs fixing]
- 🚨 **Major Issues** — [critical problems]

---

## Swift / SwiftUI / SwiftData Patterns to Check

### @Observable vs ObservableObject

Prefer `@Observable` (iOS 17+) over `ObservableObject` + `@Published` for new ViewModels.

```swift
// ✅ Preferred
@MainActor
@Observable
final class IngredientFormViewModel {
    var name: String = ""
    var isLoading = false
}

// ✅ View usage with @Observable
struct IngredientFormView: View {
    @State private var model = IngredientFormViewModel()
}

// When injecting @Observable into a dependency:
@ObservationIgnored
@Injected(\.ingredientService)
private var service: any IngredientServiceProtocol
```

Keep `ObservableObject` only when exposing Combine `$property` publishers to other services.

### SwiftData

- Use `@Model` for persistent entities; never manually manage persistence context
- Fetch with `@Query` in views rather than fetching inside ViewModels where possible
- Avoid force-unwrapping optional relationships; use `guard` or `if let`
- Deletions should always go through the `ModelContext`; never nil-out relationships directly

### SwiftUI

- Prefer `@State` + `@Observable` ViewModel over `@StateObject` + `ObservableObject` for new code
- Do not perform side effects (service calls, I/O) directly in `body` or `onAppear` without a Task
- Avoid `AnyView` erasure unless unavoidable — it breaks diffing
- Sheet / navigation destination closures should not capture large view state by value

### Error Handling

- `try?` is acceptable for intentional silent failures (operation logged internally, no user toast needed)
- `try await` / `throws` propagation is for user-visible errors (alert, toast)
- Never swallow errors silently without at minimum a `#if DEBUG` assertion or log

---

## Common Analysis Mistakes to Avoid

### Mistake: Declaring Code Unused After UI Element Removal

When a PR removes a visible UI element (e.g. a toolbar button) but leaves a related closure or parameter:

**Wrong:**
- ❌ "Parameter is unused, should be removed"

**Correct approach:**
1. Trace ALL usages of the parameter in the file
2. Check for dual-access patterns: toolbar button + `.contextMenu` (long-press) both use the same closure
3. Ask: "Was removing this UI element intentional? The parameter is still used by [other pattern]."

### Mistake: Flagging `try?` on Service Calls

**Wrong:**
- ❌ "Error is silently ignored, should use `try await`"

Services in this project log errors internally. `try?` = intentional silent failure. Only flag if there is evidence the error *should* surface to the user.

### Mistake: Flagging Independent Boolean Flags as Redundant

Two flags like `allowContextMenu` and `allowToolbarMenu` each control a *different* UI element — they are not redundant even if they look similar. Understand what each one controls before suggesting consolidation.

### Mistake: Flagging Generated Files

If a generated file changed alongside its source file, that is the correct workflow (edit source → regenerate). Only flag if *only* the generated file changed with no corresponding source edit.

---

## Pre-suggestion Checklist

Before suggesting removal of "unused" code:

- [ ] Searched ALL usages in the file
- [ ] Checked for dual UX patterns (button + context menu)
- [ ] Understood the purpose of each boolean flag
- [ ] Verified the code is not used by multiple consumers

If unsure, ask:
> "Was removing [element] intentional? The [parameter] is still used by [other pattern]. Should we keep both or remove [element] too?"
