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
Commits the current changes, reviews them with three reviewers (this session plus two parallel agents), lets the developer decide which findings to fix, repeats the review until clean, then pushes to remote and creates a pull request.

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
Each review round has three reviewers of the diff `git diff origin/main...HEAD`: this session, running `/codeReview` with `CODE_REVIEW_GUIDE.md` standards, and **two freshly spawned agents** (Agent tool, `general-purpose`), started in one message so they run in parallel. The user has explicitly asked for these agents, so spawning them is authorised here.

**Agent brief** (the same for both):
- Read-only: review the diff, never edit, stage, commit or push.
- Load the `code-review-developer` skill and follow `.claude/CODE_REVIEW_GUIDE.md` and `CLAUDE.md`.
- Look for bugs, CLAUDE.md violations, performance and security issues, missing tests and simplifications; read the surrounding code rather than judging the diff alone.
- Report each finding as `file:line`, the problem, and a concrete failure scenario, or reply exactly `No issues found`.

**Each round:**
1. Run your own review while the two agents run theirs. The agents are done once they report; don't keep or reuse them.
2. Merge the three lists into one: de-duplicate, and check each finding against the code yourself. Mark any you believe is a false positive and say why, but still show it.
3. **If no issues found**: auto-proceed to push/PR.
4. **If any issues found**: stop and present the merged findings. Let the developer decide whether to fix, skip, or flag as false positives. Never auto-amend.
5. Apply only what the developer approves, run the tests, and commit the fixes as a new commit. Then run another round with **two new** agents, and repeat until a round finds nothing or the developer says to move on.

### 6. Push and PR
- Push to remote with tracking.
- Open a PR targeting `main` unless a different base is specified.

## Examples
```bash
/crpp

/crpp in branch SWZ-42-add-formula-model
```
