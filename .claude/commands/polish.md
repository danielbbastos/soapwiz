# Polish Code

Simplify and clean up code in the current changes.

**⚠️ Requires explicit user approval before making any changes.**

## Usage

```
/polish
/polish to branch <base>
```

**Default base branch:** `main`

## Git Context (Precomputed)

- **Current branch**: !`git branch --show-current`

## Process

### Step 1: Analyse (READ-ONLY)

```bash
# Changed Swift files vs base
git diff origin/<base>...HEAD --name-only -- "*.swift"

# Full diff per file
git diff origin/<base>...HEAD -- "path/to/file.swift"

# Unstaged whitespace noise
git diff --name-only -- "*.swift"
```

Categorise each changed line:
1. **Real code change** — logic, new/removed code, refactor
2. **Whitespace-only change** — trailing spaces, empty lines

**Critical rules:**
- File has **only whitespace changes** → `git checkout HEAD -- <file>` (revert entire file)
- File has **both** → restore original whitespace for whitespace-only lines; keep real changes

### Step 2: Present Findings

**If nothing to improve** (no simplifications, no unused code):
```
## Polish Analysis ✅
All files already follow best practices. No changes needed.
```
→ Auto-proceed, no approval needed.

**If improvements found**, present:
```
## Polish Proposals

### Simplifications
1. `File.swift:42` — Use guard let instead of nested if
2. `File.swift:78` — Keypath shorthand available

### Unused Code
1. `OldHelper.swift` — No references after refactor
2. `Model.swift:15` — `unusedProperty` has no references

### Files to Revert (whitespace-only)
1. `SearchView.swift` — Only trailing whitespace changes

### Whitespace to Restore (mixed files)
1. `IngredientForm.swift:44,48` — Restore original empty lines

Apply these changes? (yes/no)
```

### Step 3: Wait for Approval

- No findings → skip, auto-proceed
- yes/approved → Step 4
- no/skip → exit without changes
- partial → apply only approved items

### Step 4: Apply Changes

Look for and fix:

- **Unnecessary nesting** → `guard let` early returns
- **Verbose closures** → `$0`, `\.property` shorthands
- **Repeated logic** → extract to local variable or function
- **Force unwraps** → replace with safe unwrapping
- **Long functions** → split if doing multiple distinct things

**Swift idioms:**

```swift
// ❌ Verbose
if let x = optional { return x } else { return default }

// ✅ Idiomatic
return optional ?? default

// Closure shorthand
array.filter(\.isActive).map(\.name)

// guard early return
guard let model else { return }
```

**⚠️ Do NOT touch formatting/whitespace** — only changes that improve logic or remove dead code.

**Revert whitespace-only files:**
```bash
git checkout HEAD -- path/to/file.swift
```

### Step 5: Clean Up Unused Code

For renamed/removed symbols, search before declaring unused:
```bash
rg "oldSymbolName" --type swift .
```

Check: `*Tests.swift`, `*Mock*.swift`, preview providers.

### Step 6: Final Check

- No broken references introduced
- Code still follows project patterns

## Output

```
## Polish Applied ✅
- Simplified: [list]
- Removed: [list]
- Reverted (whitespace-only): [list]
```
