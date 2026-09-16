---
description: Switch to main, pull latest, delete all other local branches
---

# Sync main

Switch to main, pull, and delete every other local branch whose work is already in main.

## Why this isn't plain `git branch -d`

This repo squash-merges PRs. A squashed branch's commits never become ancestors of `main`, so `git branch -d` refuses it as "not fully merged" and deletes **nothing** — stale branches pile up after every merge. Plain `-D` is the opposite failure: it would also discard a branch still holding work that never landed.

So each branch is proven contained first, and only then force-deleted.

## Steps

```bash
git checkout main
git fetch origin --prune
git pull --ff-only
```

A branch is safe to delete when **any** of these holds:

1. **Ancestor of main** — an ordinary, non-squash merge.
2. **Tree identical to main** — squash-merged, and nothing added since.
3. **Its PR is merged** — squash-merged and then left behind, so the local branch sits at an older commit than the one that actually merged. This is the case the first two miss.

Check every branch and print the verdict *before* deleting anything:

```bash
safe=""; keep=""
for b in $(git for-each-ref --format='%(refname:short)' refs/heads/ | grep -v '^main$'); do
  if git merge-base --is-ancestor "$b" main 2>/dev/null; then
    echo "  $b -> ancestor of main (safe)"; safe="$safe $b"
  elif [ -z "$(git diff main "$b")" ]; then
    echo "  $b -> tree identical to main (safe)"; safe="$safe $b"
  elif [ -n "$(/opt/homebrew/bin/gh pr list --state merged --head "$b" --json number --jq '.[].number')" ]; then
    echo "  $b -> PR merged (safe)"; safe="$safe $b"
  else
    echo "  $b -> NOT contained, $(git log --oneline main.."$b" | wc -l | tr -d ' ') commit(s) not in main (keeping)"
    keep="$keep $b"
  fi
done
```

Then delete only what passed:

```bash
deleted=0
for b in $safe; do git branch -D "$b" && deleted=$((deleted+1)); done
echo "deleted=$deleted kept=$(echo $keep | wc -w | tr -d ' ')"
git branch -vv
git status --short
```

## Rules

- `checkout main` first — a checked-out branch cannot be deleted.
- Print every verdict before the first deletion, so a wrong call is visible rather than silent.
- Never delete a branch that fails all three checks. Report it and leave it alone.
- `--ff-only` on the pull: main should fast-forward, and a merge commit here means something unexpected happened — stop and say so.
- `gh` is not on the default PATH; use `/opt/homebrew/bin/gh`.

## Report

Confirm main is up to date, and name the branches either way:

```
Synced main to 7aa7f05 (0 ahead, 0 behind origin/main)
Deleted 2: sw-136-merge-duplicate-library-ingredients…, sw-144-nav-paths…
Kept 1: sw-150-batch-scaling (3 commits not in main)
```
