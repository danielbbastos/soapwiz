---
allowed-tools: Bash(git branch:*), Bash(git status:*), Bash(git log:*), Bash(git diff:*), Bash(git fetch:*)
---

# Commit, review, push, pull request

## Git Context (Precomputed)
- **Fetch**: !`git fetch origin main 2>/dev/null || echo "(fetch failed)"`
- **Current branch**: !`git branch --show-current`
- **Staged files**: !`git diff --cached --name-only`
- **Unstaged changes**: !`git status --short`
- **Recent commits**: !`git log --oneline -5`

## Usage
```
/crpp [in branch <branch-name>]
```

## Description
Commits the current changes, performs a code review, applies fixes if needed, then pushes to remote and creates a pull request.

## Optional Arguments
- `in branch <branch-name>` - Specifies the target branch for the commit, push, and PR. Creates it if it doesn't exist.

## Workflow

### 1. Verify Correct Branch
**ALWAYS check the branch before any commit operations.**

- If a Linear task ID is known (from context or branch name): fetch the issue via the Linear MCP tool and confirm the current branch matches. If it doesn't, stop and ask the user to confirm before switching.
- If no task ID is known: stop and ask — "What Linear task are you working on? (e.g., SWZ-42)" — then verify as above.

**Never commit without confirming you're on the correct branch.**

### 2. Stage Changes
- Stage all changes to prepare for review and commit.

### 3. Polish Code
- Review staged Swift files for simplification opportunities.
- **If none found**: auto-proceed to commit.
- **If found**: present findings and wait for explicit approval before making any changes. If approved, apply, re-stage, then commit. If declined, commit as-is.
- Key checks: guard-let early returns, keypath shorthand (where clearer), unused code removal.

### 4. Commit
- Commit staged changes with a descriptive message following CLAUDE.md guidelines.

### 5. Code Review
- Run `/codeReview` and apply `CODE_REVIEW_GUIDE.md` standards.
- Check for bugs, best practice violations, performance issues, security concerns.
- **If no issues found**: auto-proceed to push/PR.
- **If any issues found**: stop and present findings. Let the developer decide whether to fix, skip, or flag as false positives. Never auto-amend.

### 6. Push and PR
- Push to remote with tracking.
- Open a PR targeting `main` unless a different base is specified.

## Examples
```bash
/crpp

/crpp in branch SWZ-42-add-formula-model
```
