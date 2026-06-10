---
name: ship-issue
description: Autonomous end-to-end delivery of a Linear issue — implement, test, review, PR, merge, until the issue is Done. Use when the user sets a goal like "work until issue N is done" or asks to ship/complete an issue end to end without supervision.
---

# Ship Issue (End-to-End)

Drive a Linear issue from Backlog to **Done** with no human in the loop. "Done" means:
the PR is squash-merged to `main` and Linear shows the issue in the Done state.

## Authorization

When this skill is invoked — explicitly, or via a `/goal` naming an issue — the
approval gates in CLAUDE.md and memory ("present a plan and wait", "never commit
without explicit request") are **pre-authorized for this pipeline only**: branch,
commit, push, open PR, and squash-merge are all in scope. Do not stop to ask
permission for any of those steps. Everything outside the pipeline (e.g. touching
other branches, force-pushes, closing other PRs) stays forbidden.

## Pipeline

Follow the steps in order. Each step gates the next — never skip a failing gate.

### 1. Resolve the issue
- Load the **linear-developer** skill; fetch with `linctl issue get SW-NN --json`.
- Confirm dependencies ("Depends on" / blocking relations) are Done. If not, stop and report.
- State workflow: if not Todo, set Todo; then set **In Progress** and assign to me.

### 2. Branch
- `git checkout -b <branchName>` using the issue's `gitBranchName` from Linear, off up-to-date `main`.

### 3. Implement
- Read the relevant existing code first; match its patterns (load **swiftui-patterns-soapwiz** for views, **tests-developer** before writing any tests).
- Honor the issue's Notes/Acceptance sections literally — they encode constraints (e.g. "read-only", "don't recompute").
- Make sure every helper written for testability is actually used by the production view — never test dead code.

### 4. Verify
- Run the full suite headlessly: `xcodebuild test -project SoapWiz.xcodeproj -scheme SoapWiz -destination 'platform=iOS Simulator,name=iPhone 15 Pro'`.
- All acceptance criteria from the issue must map to either a test or an implemented behavior. Re-run after every subsequent fix.

### 5. Self-review
- Run the **self-review** skill on the diff; fix findings before committing.

### 6. Commit / review / push / PR
- Run **/crpp**: stage, polish, commit (style: match `git log` history, reference `(SW-NN)`), run **/codeReview**, push, open PR against `main`.
- Review findings on own unpushed code: fix them in a follow-up commit (squash-merge erases the noise). Never auto-amend.

### 7. Wait for CI / review bot
- `gh pr checks <PR> --watch` (gh is at `/opt/homebrew/bin/gh`).
- Read the bot's review comments (`gh pr view <PR> --comments`).
  - **Approved / no issues** → proceed.
  - **Findings** → fix, push, wait for re-check. If a finding is a false positive, reply explaining why, then proceed only if checks are green.
  - **Checks fail** → fix and repeat. Do not merge red.

### 8. Merge
- `gh pr merge <PR> --squash --delete-branch`, then `git checkout main && git pull --ff-only`.

### 9. Confirm Done
- Wait briefly, then `linctl issue get SW-NN --json | jq -r '.state.name'`.
- The GitHub↔Linear integration auto-sets Done on merge; if it hasn't after ~1 min, set it manually via `linctl issue update SW-NN --state "Done"`.
- Report: PR link, merge commit, test count, and the Linear state.

## Stop conditions (the only reasons to halt and ask)

- A dependency issue is not Done.
- Tests fail and the fix would change scope beyond the issue.
- The review bot raises a finding that requires a product decision.
- Merge conflicts with `main` that can't be resolved mechanically.
- The issue description is ambiguous about user-visible behavior.
