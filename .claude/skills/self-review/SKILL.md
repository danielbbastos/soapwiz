---
name: self-review
description: Agent self-reviews its own diff against CODE_STANDARD.md before presenting to user. Catches mechanical violations early.
---

# Self-Review Skill

## Purpose
Verify your own code changes against `CODE_STANDARD.md` before presenting them to the user. Catch mechanical violations before they reach human review.

## When to Use
- After completing any code implementation
- Before suggesting changes are ready
- When the `polish` skill activates (complements it)

## Workflow

### Step 1: Gather Your Changes
Identify all files you modified or created in this session.

### Step 2: Run Invariant Checks
For each modified `.swift` file, check against `CODE_STANDARD.md`:

```bash
# Deprecated APIs
rg '\.foregroundColor\(' <file>
rg '\.cornerRadius\(' <file>
rg 'NavigationView' <file>

# Hardcoded colors and fonts
rg 'Color\(red:|UIColor\(red:|#[0-9a-fA-F]{6}' <file>
rg '\.font\(\.system\(size:|Font\.system\(size:' <file>

# Force unwraps (rough — excludes comments and !=)
rg '!\.' <file> | grep -v '//' | grep -v 'test'

# Print statements
rg 'print\(' <file>

# onTapGesture without count (accessibility)
rg '\.onTapGesture\s*\{' <file>

# Group with lifecycle modifiers
rg -A5 'Group\s*\{' <file> | rg '\.onAppear|\.task'

# @Query in classes (should be in views only)
rg '@Query' <file> | grep -v 'struct'
```

### Step 3: Check SoapWiz-Specific Rules

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
- `.animation(...)` without an explicit `value:` parameter → add `value:`
- `ForEach` using `id: \.self` on a non-stable type → use a stable `id` property

**Performance**
- Formatter (`DateFormatter`, `NumberFormatter`) allocated inside `body` or `ForEach` → make `static`
- Sort or filter applied inside `ForEach` → precompute in a private computed property

### Step 4: Check CLAUDE.md Critical Rules
- No staged files without explicit user request
- No commit created without explicit user request
- No AI signatures in code or comments

### Step 5: Check Refactoring Completeness
If you renamed anything:
```bash
rg "oldName" --type swift
```
Ensure 0 results outside generated files.

### Step 6: Report
- If violations found: fix them before presenting to user
- If clean: proceed silently (don't announce the self-review)
- If uncertain about an exception: note it to the user

## Key Principle
> "When the agent struggles, the fix is never 'try harder' — it's 'what capability is missing?'"
>
> If you keep violating the same invariant, add it to `CODE_STANDARD.md` — not more willpower.

## Related
- `CODE_STANDARD.md` — the source of truth for mechanical rules
- `code-review-developer` — for reviewing others' code
- `polish` — for code quality improvements
