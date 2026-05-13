---
name: skills-manager
description: Context-aware routing to skills and hooks management. Use when troubleshooting skill activation, fine-tuning keywords, or managing the automated documentation system.
---

# Skills Manager

Use this when creating, updating, or auditing the skills in `.claude/skills/`.

## Skill File Structure

Each skill lives at:
```
.claude/skills/<skill-name>/SKILL.md
```

**Naming rules:**
- Lowercase with hyphens only (no underscores or spaces)
- 1–64 characters
- Cannot start/end with a hyphen or contain consecutive hyphens
- Directory name must match the skill name

## Current Skills

| Skill | Purpose |
|---|---|
| `claudemd-maintainer` | Auditing and updating CLAUDE.md |
| `code-review-developer` | Lean, issue-only code review |
| `confidence-check` | Pre-implementation gate |
| `decompose` | Breaking large tasks into subtask layers |
| `ios-dev-guidelines` | iOS/Swift architectural conventions |
| `linear-developer` | Linear issue management (pending MCP setup) |
| `liquid-glass-developer` | iOS 26 Liquid Glass effects |
| `plan-feature` | Single-feature planning and approval flow |
| `self-review` | Post-implementation checklist |
| `skills-manager` | This file — skill lifecycle management |
| `swift-concurrency-developer` | Swift async/await and actor patterns |
| `swiftui-expert` | SwiftUI state, composition, animation, APIs |
| `swiftui-patterns` | Project-specific SwiftUI/SwiftData conventions |
| `swiftui-performance-developer` | Performance auditing for SwiftUI views |
| `tests-developer` | Swift Testing patterns and test writing |

## When Creating a New Skill

1. Identify the domain and name it with the naming rules above
2. Create `SKILL.md` with: purpose, when to use, key rules, examples
3. Add it to the table in this file
4. Keep skills focused — one domain per skill

## When Updating a Skill

1. Read the current SKILL.md before editing
2. Update the content, then verify the table here is still accurate
3. Remove outdated entries when a skill is deleted

## Skill Quality Checklist

- [ ] Starts with a clear "Use this when..." statement
- [ ] Contains actionable rules, not just descriptions
- [ ] Has examples or patterns where appropriate
- [ ] Does not duplicate content already in CLAUDE.md
- [ ] Under ~80 lines (longer = split into two skills)
