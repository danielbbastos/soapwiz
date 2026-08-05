---
name: skills-manager
description: Use when creating a new skill, editing a SKILL.md, writing or fixing a skill description, auditing which skills are unused, or configuring hooks in .claude/hooks — including "why didn't that skill activate", "this skill never fires", "make a skill trigger more often", and rewriting a description so it routes correctly. Covers skill dispatch, frontmatter rules, and hook events.
---

# Skills Manager

## Purpose
Context-aware routing to skills and hooks management. Helps you troubleshoot, create, update, and audit the skill system.

## When Auto-Activated
- Discussing skill activation or hooks
- Creating or updating skills
- Keywords: skill activation, hook, troubleshoot, create skill, new skill, skill description, SKILL.md
- Debugging why a skill didn't activate or activated incorrectly

## 🚨 Critical Rules

1. **Description is the trigger** — skills activate via Claude Code's native Skill tool based on the `description` field; keep descriptions specific and keyword-rich
2. **Directory name must match `name` field** — `skills/my-skill/` → `name: my-skill`
3. **Validate frontmatter** — every SKILL.md must have `name` and `description` in YAML frontmatter
4. **Keep skills focused** — one domain per skill; long skills should use a `references/` subdirectory

## 📋 Diagnostic Workflow

### Problem: Skill Didn't Activate

Skills activate when Claude matches your prompt to a skill's `description` field. There is no keyword config file — the routing is semantic.

1. **Check the description**: Does the skill's `description` mention the words you used?
   ```bash
   grep -A1 "^description:" .claude/skills/SKILL-NAME/SKILL.md
   ```

2. **Rephrase your prompt** to include terms from the description, or:

3. **Improve the description**: Add the missing trigger terms to the `description` field.
   - Before: `"Use when reviewing code"`
   - After: `"Use when reviewing pull requests, providing code feedback, or discussing review standards"`

4. **Invoke explicitly**: You can always force-activate with `/skill-name`.

### Problem: Skill Activated When It Shouldn't

1. **Check the description** — is it too broad?
2. **Tighten the wording** — remove generic phrases, add domain-specific terms
3. **Example**: `"Use when working with Swift files"` → `"Use when writing async/await code, working with actors, or resolving concurrency warnings"`

## 🔧 System Components

### Hooks (Automation)

**Location**: `.claude/hooks/`

| Hook | Event | What It Does |
|------|-------|--------------|
| `swiftformat-post-edit.sh` | PostToolUse (Edit/Write) | Auto-formats Swift files immediately after edit |
| `notification-alert.sh` | Stop | Sends macOS notification when Claude needs input |

**Make hooks executable after creating them:**
```bash
chmod +x .claude/hooks/*.sh
```

### Skills (Routers)

**Location**: `.claude/skills/*/SKILL.md`

**All 18 skills:**

| Skill | Purpose |
|-------|---------|
| `claudemd-maintainer` | Auditing and updating CLAUDE.md |
| `code-review-developer` | Code review standards and PR feedback |
| `confidence-check` | Pre-implementation gate before writing code |
| `decompose` | Breaking large tasks into layered subtasks |
| `ios-dev-guidelines` | Swift/iOS architectural conventions |
| `linear-developer` | Linear issue management via linctl CLI |
| `liquid-glass-developer` | iOS 26 Liquid Glass effects in SwiftUI |
| `plan-feature` | Single-feature planning and approval flow |
| `self-review` | Post-implementation check against CODE_STANDARD.md |
| `ship-issue` | Autonomous end-to-end delivery of a Linear issue |
| `skills-manager` | This skill — skill lifecycle and hooks management |
| `swift-concurrency-developer` | Swift async/await and actor patterns |
| `swiftui-expert` | SwiftUI state, composition, animation, APIs |
| `swiftui-patterns-soapwiz` | SoapWiz-specific SwiftUI/SwiftData conventions |
| `swiftui-patterns-developer` | SwiftUI view structure, composition, subview extraction |
| `swiftui-performance-developer` | Performance auditing for SwiftUI views |
| `tests-developer` | Swift Testing patterns and test writing |
| `visual-regression` | On-device visual regression testing via simulator |

## 📝 Creating New Skills

### Required SKILL.md Format

Every skill must start with YAML frontmatter:

```yaml
---
name: skill-name
description: What this skill does and when to use it. Include trigger keywords.
---

# Skill Title

## Purpose
...
```

### Name Field Rules

- **1–64 characters**
- **Lowercase only**: `a-z`, `0-9`, `-`
- **No start/end hyphens**: `skill-name` ✅, `-skill-` ❌
- **No consecutive hyphens**: `my-skill` ✅, `my--skill` ❌
- **Must match directory name**: `skills/my-skill/SKILL.md` → `name: my-skill`

### Description Field

- **1–1024 characters**
- **Must describe**: what it does AND when to use it
- **Include keywords** that help route relevant tasks

**Good example:**
```yaml
description: Context-aware routing to iOS 26 Liquid Glass implementation patterns. Use when working with glass effects, GlassEffectContainer, morphing transitions, or iOS 26 visual effects.
```

### Directory Structure

```
skill-name/
├── SKILL.md          # Required — main skill file
├── references/       # Optional — additional docs for large skills
└── scripts/          # Optional — executable scripts
```

### New Skill Checklist

- [ ] Directory name matches `name` field
- [ ] YAML frontmatter with `name` and `description`
- [ ] Name is lowercase with hyphens only
- [ ] Description explains what AND when, with trigger keywords
- [ ] Added to the skills table in this file
- [ ] SKILL.md under ~150 lines (use `references/` for overflow)

## ⚠️ Common Issues

### Hook Not Executing

**Symptom**: SwiftFormat not running, notifications not firing

**Fix**:
```bash
# Check permissions
ls -l .claude/hooks/*.sh  # Should show -rwx

# Make executable
chmod +x .claude/hooks/*.sh
```

### Skill Not Appearing in System Reminder

**Symptom**: Skill not listed in available skills

**Check**:
```bash
# Verify frontmatter exists
head -5 .claude/skills/SKILL-NAME/SKILL.md

# Check directory name matches name field
ls .claude/skills/
```

### Frontmatter Malformed

**Symptom**: Skill loads but description is wrong or empty

**Fix**: Ensure the file starts with `---`, has `name:` and `description:` fields, and closes with `---` before any other content.

## ✅ Skill Quality Checklist

- [ ] Starts with a clear "Use this when…" in the description
- [ ] Contains actionable rules, not just descriptions
- [ ] Has examples or patterns where appropriate
- [ ] Does not duplicate content already in `CLAUDE.md` or `CODE_STANDARD.md`
- [ ] Under ~150 lines (longer → split or use `references/`)
- [ ] `name` matches directory name exactly

## 🔍 Health Check Commands

```bash
# List all skills
ls .claude/skills/

# Check all have frontmatter
for f in .claude/skills/*/SKILL.md; do
  echo "=== $f ===" && head -5 "$f"
done

# Check hook permissions
ls -l .claude/hooks/*.sh

# Count skills
ls .claude/skills/ | wc -l
```

---

**Quick help**: "Why didn't X skill activate?" → check the skill's `description` field and add missing trigger terms.
