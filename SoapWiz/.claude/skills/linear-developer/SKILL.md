# Linear Developer

Use this when working with Linear issues via the Linear MCP integration.

## Status

Linear MCP is planned but not yet configured. This skill will be activated once it's set up.

## Intended Workflows

Once Linear MCP is available:

### Fetching an issue
```
Get issue <ID> from Linear
```

### Listing my open issues
```
List open issues assigned to me
```

### Creating a sub-issue
```
Create sub-issue of <parent-ID>: "<title>"
```

### Updating status
```
Set issue <ID> to In Progress / Done / Cancelled
```

## Key Rules (for when Linear is active)

- Always use issue identifiers (e.g., `SW-42`) for readability
- When decomposing a task, create sub-issues for each subtask after plan approval
- Keep issue descriptions self-contained — a future session should be able to work from the issue alone
- Use the `decompose` skill to plan before creating sub-issues

## Update This File When Linear Is Configured

Replace this placeholder with actual MCP tool names, command syntax, and any project-specific workflow (e.g., which team, default labels, status transitions).
