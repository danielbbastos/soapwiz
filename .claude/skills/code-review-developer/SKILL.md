# Code Review Developer

Run this when reviewing a PR, a set of changed files, or when asked to review code.

## Core Principle

Be **lean and actionable** — only report actual issues. No praise sections. No design suggestions you cannot verify against the code.

## Approval Format

When everything is clean, respond with exactly:

```
✅ Approved - No issues found
```

Nothing else.

## Issue Sections

Only include a section when a real problem exists:

- **Bugs / Correctness** — logic errors, wrong API usage, incorrect SwiftData access
- **SwiftData Violations** — off-`@MainActor` mutation, missing cascade delete, `@State` for persisted data
- **Performance** — formatters or sorts in `body`, unstable list IDs, heavy work not deferred to `.task`
- **Security** — not applicable for most app code; note if user input is unsanitized

Every issue must cite **file and line number**.

## Checklist Before Submitting

- [ ] Read CLAUDE.md for project-specific rules first
- [ ] Check all usages before flagging something as unused
- [ ] Verify SwiftData relationships have correct `deleteRule`
- [ ] Confirm any SwiftData to-many is sorted before display
- [ ] Confirm FAB hides when `editMode == .active`
- [ ] Form views follow the `var thing: Thing? = nil` pattern
- [ ] No force unwraps on legitimately optional values
- [ ] No leftover `print()` statements
- [ ] End with a single status line
