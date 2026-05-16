---
description: Switch to main, pull latest, delete all other local branches
---

# Sync main

Switch to main, fetch origin, pull to sync, and delete all other local branches.

## Steps

```bash
git checkout main
git fetch origin
git pull
git branch | grep -v '^\* main' | xargs git branch -D
```

Run these sequentially. Report how many branches were deleted and confirm main is up to date.
