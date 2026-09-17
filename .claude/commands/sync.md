---
description: Switch to main, pull latest, and delete local branches whose work is already in main
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

Resolve `gh` up front. Check 3 below depends on it, and a missing `gh` must stop the
command rather than quietly downgrade every verdict to "keep":

```bash
gh_bin="$(command -v gh || true)"
[ -n "$gh_bin" ] || for c in /opt/homebrew/bin/gh /usr/local/bin/gh; do
  [ -x "$c" ] && gh_bin="$c" && break
done
[ -n "$gh_bin" ] || { echo "gh not found — cannot prove squash-merges; aborting"; exit 1; }
```

A branch is safe to delete when **any** of these holds:

1. **Ancestor of main** — an ordinary, non-squash merge.
2. **Tree identical to main** — squash-merged, and nothing added since.
3. **Its PR merged at this exact tip** — squash-merged and then left behind, so the local branch sits at an older commit than the one that actually merged. This is the case the first two miss.

Check 3 compares the local tip against `headRefOid`, the commit GitHub actually merged.
A merged PR alone is **not** enough: if the branch picked up further commits afterwards,
or local commits GitHub never saw, those exist nowhere else once the remote ref is pruned,
and `-D` would destroy them. Tip equality is what makes the force-delete safe.

Check every branch and print the verdict *before* deleting anything:

```bash
safe=""; keep=""
for b in $(git for-each-ref --format='%(refname:short)' refs/heads/ | grep -v '^main$'); do
  if git merge-base --is-ancestor "$b" main 2>/dev/null; then
    echo "  $b -> ancestor of main (safe)"; safe="$safe $b"
  elif [ -z "$(git diff main "$b")" ]; then
    echo "  $b -> tree identical to main (safe)"; safe="$safe $b"
  else
    merged_tip="$("$gh_bin" pr list --state merged --head "$b" --json headRefOid --jq '.[0].headRefOid')"
    local_tip="$(git rev-parse "$b")"
    ahead="$(git log --oneline main.."$b" | wc -l | tr -d ' ')"
    if [ -n "$merged_tip" ] && [ "$merged_tip" = "$local_tip" ]; then
      echo "  $b -> PR merged at this exact tip (safe)"; safe="$safe $b"
    elif [ -n "$merged_tip" ]; then
      echo "  $b -> PR merged, but local tip $(echo "$local_tip" | cut -c1-7) != merged $(echo "$merged_tip" | cut -c1-7) — unpushed work, KEEPING"
      keep="$keep $b"
    else
      echo "  $b -> NOT contained, $ahead commit(s) not in main (keeping)"
      keep="$keep $b"
    fi
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
- A merged PR by itself never justifies deletion — only a merged PR **at the branch's current tip** does.
- `--ff-only` on the pull: main should fast-forward, and a merge commit here means something unexpected happened — stop and say so.
- `gh` may not be on the default PATH. Resolve it once as above and abort if it is missing; never let an absent `gh` silently turn check 3 into "not merged".

## Report

Confirm main is up to date, and name the branches either way:

```
Synced main to 7aa7f05 (0 ahead, 0 behind origin/main)
Deleted 2: sw-136-merge-duplicate-library-ingredients…, sw-144-nav-paths…
Kept 1: sw-150-batch-scaling (3 commits not in main)
```
