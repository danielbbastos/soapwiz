# Code Review

Review local code changes on the current branch against a base branch.

## Git Context (Precomputed)

- **Current branch**: !`git branch --show-current`
- **Fetch**: !`git fetch origin main 2>/dev/null || echo "(fetch failed)"`

## Usage

```
/codeReview
/codeReview to branch <base>
```

**Default base branch:** `main`

## Process

### Step 1: Get Changed Files

```bash
# Changed files and stats
git diff --name-status origin/<base>...HEAD
git diff --stat origin/<base>...HEAD

# Full diff for review
git diff origin/<base>...HEAD
```

### Step 2: Apply Review Standards

Follow **`.claude/CODE_REVIEW_GUIDE.md`** — all core rules, section formats, common mistakes, and the pre-suggestion checklist apply.

### Step 3: Focus Areas for SoapWiz

When analysing the diff, pay special attention to:

1. **@Observable** — new ViewModels should use `@Observable`, not `ObservableObject` + `@Published`
2. **SwiftData** — deletions via `ModelContext`, no direct nil-out of relationships, `@Query` in views
3. **Error handling** — `try?` vs `try await`; silent failures must at least be logged
4. **Force unwraps** — flag any `!` on optionals that could realistically be nil
5. **Thread safety** — `@MainActor` on ViewModels; avoid capturing mutable state across actor boundaries
6. **Unused code** — after refactoring, check old symbols are removed (use `grep`/`rg` before flagging)

### Step 4: Output

Present the review directly following the summary format from `CODE_REVIEW_GUIDE.md`.
