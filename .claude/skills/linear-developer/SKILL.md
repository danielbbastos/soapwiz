---
name: linear-developer
description: Linear issue management. Use when reading, creating, or updating Linear issues, comments, or project state.
---
# Linear CLI Developer (Smart Router)

## Purpose
Context-aware routing to Linear issue tracking using `linctl` CLI. Replaces Linear MCP tools with faster, more reliable command-line operations.

**Reference Repository**: https://github.com/dorkitude/linctl

## When Auto-Activated
- Working with Linear issues, projects, or releases
- Keywords: linear, issue, linctl, SW-XXXX, release task, sprint, cycle

## Why linctl Over MCP?
- **More reliable**: Direct CLI calls vs MCP server communication
- **Less context**: Simpler command syntax vs verbose MCP tool definitions
- **Faster**: No MCP overhead
- **Agent-optimized**: Built specifically for AI agents with `--json` output

## Installation
```bash
brew tap dorkitude/linctl
brew install linctl
linctl auth  # Interactive authentication
```

## Critical Rules

1. **Always use `--json` flag** for structured output parsing
2. **Use issue identifiers** (SW-XXXX) not UUIDs for user-facing references
3. **Default filters exclude old/completed items** — use `--newer-than all_time` and `--include-completed` when needed
4. **Limit results** — Default is 50, use `--limit` for large datasets
5. **`issue list` has no `--labels` filter** — use `issue search "label-name"` to find by label
6. **No `linctl cycle` command** — filter by cycle via `linctl issue list --cycle current`
7. **`--assign-me` on create vs `--assignee me` on update** — different flags, same intent

## Quick Reference

### Issue Commands
| Task | Command |
|------|---------|
| Get issue details | `linctl issue get SW-1234 --json` |
| List my issues | `linctl issue list --assignee me --json` |
| List team issues | `linctl issue list --team SW --json` |
| Search issues | `linctl issue search "query" --team SW --json` |
| Create issue | `linctl issue create --title "Title" --team SW --json` |
| Create + assign to self | `linctl issue create --title "Title" --team SW --assign-me --json` |
| Create with labels | `linctl issue create --title "Title" --team SW --labels "Bug,urgent" --json` |
| Update issue | `linctl issue update SW-1234 --state "Done" --json` |
| Assign to self | `linctl issue assign SW-1234` |
| Set parent (sub-issue) | `linctl issue update SW-1234 --parent SW-100 --json` |
| Remove parent | `linctl issue update SW-1234 --parent none --json` |
| Add labels | `linctl issue update SW-1234 --labels "Bug,urgent" --json` |
| Clear labels | `linctl issue update SW-1234 --clear-labels --json` |
| Attach PR | `linctl issue attach SW-1234 --pr 456` |
| Attach URL | `linctl issue attach SW-1234 --url https://example.com --title "Spec"` |

### Label Commands
| Task | Command |
|------|---------|
| List team labels | `linctl label list --team SW --json` |
| Get label by ID | `linctl label get <label-id> --json` |
| Create label | `linctl label create --team SW --name "bug" --color "#ff0000"` |
| Update label | `linctl label update <label-id> --name "critical bug"` |
| Delete label | `linctl label delete <label-id>` |

### Issue Relation Commands
| Task | Command |
|------|---------|
| List relations | `linctl issue relation list SW-1234 --json` |
| Add blocks relation | `linctl issue relation add SW-1234 --blocks SW-456` |
| Add blocked-by relation | `linctl issue relation add SW-1234 --blocked-by SW-456` |
| Add related relation | `linctl issue relation add SW-1234 --related SW-456` |
| Remove relation | `linctl issue relation remove <relation-id>` |

### Project Commands
| Task | Command |
|------|---------|
| List projects | `linctl project list --json` |
| Get project | `linctl project get <project-id> --json` |
| Filter by team | `linctl project list --team SW --json` |

### Team Commands
| Task | Command |
|------|---------|
| List teams | `linctl team list --json` |
| Get team | `linctl team get SW --json` |
| Team members | `linctl team members SW --json` |
| Workflow states | `linctl team state list SW --json` |

### User Commands
| Task | Command |
|------|---------|
| Current user (with JSON) | `linctl user me --json` |
| List users | `linctl user list --json` |
| Get user | `linctl user get email@example.com --json` |

### Comment Commands
| Task | Command |
|------|---------|
| List comments | `linctl comment list SW-1234 --json` |
| Add comment | `linctl comment create SW-1234 --body "Comment text"` |
| Update comment | `linctl comment update <comment-id> --body "Updated text"` |
| Delete comment | `linctl comment delete <comment-id>` |

### Cycle Filtering (no separate cycle command)
```bash
# Filter issues by current cycle — NOT linctl cycle list
linctl issue list --team SW --cycle current --json
linctl issue list --team SW --cycle 42 --json
```

## Issue State Workflow

**Always follow this sequence when picking up a task:**

```bash
# 1. Check current state
linctl issue get SW-XXXX --json | jq -r '.state.name'

# 2. If not "Todo", set it first
linctl issue update SW-XXXX --state "Todo" --json

# 3. When starting work (branching/coding)
linctl issue update SW-XXXX --state "In Progress" --json

# 4. After merge — Linear auto-sets to Done, no action needed
```

## Common Workflows

### Create a fully populated issue
```bash
linctl issue create \
  --title "Fix login bug" \
  --team SW \
  --labels "Bug" \
  --assign-me \
  --state "In Progress" \
  --json
# Then set parent, description, etc. via update
linctl issue update SW-1234 \
  --parent SW-5 \
  --description "Detailed description here" \
  --json
```

### Find epics and set sub-issue
```bash
# Search for epics
linctl issue search "EPIC" --team SW --newer-than all_time --json

# Set sub-issue relationship
linctl issue update SW-1234 --parent SW-5 --json
```

### Get Branch Name for Task
```bash
linctl issue get SW-1234 --json | jq -r '.branchName'
```

The field is `branchName`, not `gitBranchName` — the latter is the Linear GraphQL name and returns `null` through `linctl`.

### Release Task Hierarchy
```bash
# Step 1: Get release task
linctl issue get SW-5467 --json

# Step 2: Get subtasks — use search since issue list has no --parent-id flag
linctl issue search "SW-5467" --team SW --json
# Or get issue details which includes children
linctl issue get SW-5467 --json | jq '.children'
```

### List All Issues for Sprint
```bash
linctl issue list --team SW --cycle current --json
```

### Filter by State
```bash
linctl issue list --state "In Progress" --json
linctl issue list --state "Done" --include-completed --json
```

## MCP to linctl Migration Table

| MCP Tool | linctl Equivalent |
|----------|-------------------|
| `mcp__linear-server__get_issue(id)` | `linctl issue get <id> --json` |
| `mcp__linear-server__list_issues(...)` | `linctl issue list [filters] --json` |
| `mcp__linear-server__create_issue(...)` | `linctl issue create [options] --json` |
| `mcp__linear-server__update_issue(...)` | `linctl issue update <id> [options] --json` |
| `mcp__linear-server__list_comments(issueId)` | `linctl comment list <id> --json` |
| `mcp__linear-server__create_comment(...)` | `linctl comment create <id> --body "..."` |
| `mcp__linear-server__list_teams` | `linctl team list --json` |
| `mcp__linear-server__get_team(query)` | `linctl team get <key> --json` |
| `mcp__linear-server__list_projects` | `linctl project list --json` |
| `mcp__linear-server__get_project(query)` | `linctl project get <id> --json` |
| `mcp__linear-server__list_users` | `linctl user list --json` |
| `mcp__linear-server__get_user(query)` | `linctl user get <email> --json` |
| `mcp__linear-server__list_cycles(...)` | `linctl issue list --cycle current --json` |

## Priority Values
| Priority | Name |
|----------|------|
| 0 | None |
| 1 | Urgent |
| 2 | High |
| 3 | Normal (default) |
| 4 | Low |

## Time Filters (`--newer-than`)
- `all_time` - No filter
- `6_months_ago` - Default
- `1_month_ago`
- `1_week_ago`
- `1_day_ago`
- ISO-8601 dates (e.g. `2025-07-01`)

## Output Formats
- `--json` - Structured JSON (recommended for agents)
- `--plaintext` - Markdown formatted
- Default: Table format

## Common Mistakes

### Using --labels on issue list (doesn't exist)
```bash
# Wrong — issue list has no --labels flag
linctl issue list --team SW --labels "Epic" --json

# Correct — use search to filter by label name
linctl issue search "Epic" --team SW --newer-than all_time --json
```

### Using linctl cycle list (doesn't exist)
```bash
# Wrong — no top-level cycle command
linctl cycle list --team SW --type current --json

# Correct — cycle is a filter on issue list
linctl issue list --team SW --cycle current --json
```

### Using linctl whoami --json (no --json on whoami)
```bash
# Wrong — whoami has no --json flag
linctl whoami --json

# Correct
linctl user me --json
```

### Using --parent-id on issue list (doesn't exist)
```bash
# Wrong — issue list has no --parent-id flag
linctl issue list --parent-id <uuid> --json

# Correct — use issue get and check .children, or search by parent identifier
linctl issue get SW-5 --json | jq '.children'
```

### Wrong flag for labels on create vs update
```bash
# Create: use --labels (comma-separated names or IDs)
linctl issue create --title "..." --team SW --labels "Bug,urgent"

# Create: use --assign-me (not --assignee me)
linctl issue create --title "..." --team SW --assign-me

# Update: use --assignee me (not --assign-me)
linctl issue update SW-1234 --assignee me
```

### Forgetting --json
```bash
# Wrong - table output, hard to parse
linctl issue get SW-1234

# Correct - structured JSON
linctl issue get SW-1234 --json
```

### Missing --include-completed
```bash
# Wrong - misses completed/canceled items
linctl issue list --newer-than all_time --json

# Correct - includes all states
linctl issue list --newer-than all_time --include-completed --json
```

### Using UUID in User-Facing Output
```bash
# Wrong - UUIDs are internal
"Task: cab796c7-b58d-4876-b1a4-cc9f39da1431"

# Correct - identifiers are readable
"Task: SW-5467"
```

## Related Skills & Docs

- **crpp** → Uses Linear for branch names

---

**Navigation**: This is a smart router. For CLI details, see: https://github.com/dorkitude/linctl
