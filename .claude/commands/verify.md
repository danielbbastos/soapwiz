allowed-tools: Bash(swiftlint:*), Bash(xcodebuild:*), Bash(git diff:*), Bash(git fetch:*)

# Verify Build

Run build verification on current changes.

## Context (Precomputed)

- **Changed Swift files**: !`git diff --name-only origin/main...HEAD -- "*.swift" 2>/dev/null | head -20`

## Usage

```
/verify          # SwiftLint only (fast, ~5-10 seconds)
/verify full     # SwiftLint + xcodebuild (slow, 2-5 minutes)
```

## Process

### Step 1: SwiftLint Check

```bash
git diff --name-only -z origin/main...HEAD -- "*.swift" | xargs -0 swiftlint lint --
```

**Results format:**
```
## SwiftLint Results

### ❌ Errors (must fix)
- `File.swift:42` — Trailing whitespace
- `File.swift:78` — Force cast

### ⚠️ Warnings (optional)
- `File.swift:15` — Line length (105 > 100)

### ✅ No Issues
All files pass SwiftLint checks.
```

If errors found, offer to auto-fix where possible.

### Step 2: Full Build (only if `/verify full`)

Ask: "Full xcodebuild takes 2-5 minutes. Run in background? (yes/no)"

**Background (yes):** use `run_in_background: true`

**Foreground (no):** run inline

```bash
xcodebuild build \
  -project /Users/danielbastos/Documents/Code/daphnia/SoapWiz/SoapWiz.xcodeproj \
  -scheme SoapWiz \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -quiet \
  2>&1 | grep -E "(error:|warning:|BUILD|FAILED|SUCCEEDED)"
```

## Output

```
## Verify Results ✅
SwiftLint: Passed (0 errors, 2 warnings)
Build: Success
```

```
## Verify Results ❌
SwiftLint: 3 errors found

Fix before committing:
1. `File.swift:42` — Trailing whitespace
2. `File.swift:78` — Force cast

Auto-fix available? (yes/no)
```
