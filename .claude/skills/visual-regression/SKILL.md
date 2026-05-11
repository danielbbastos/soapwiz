---
name: visual-regression
description: On-demand visual regression testing for SoapWiz. Builds the app, boots a simulator, navigates to a screen, interacts with UI, takes a screenshot, and uses Claude's vision to analyse what's on screen — no pixel diffing, no locator maintenance.
allowed-tools: Bash
---

# Visual Regression

Run on-demand visual regression tests for SoapWiz without a dedicated testing pipeline.

## Usage

```
/visual-regression
/visual-regression <screen>
```

Where `<screen>` is one of: `inventory`, `ingredient-detail`, `batch-detail`, `settings`, `categories`, `storage-locations`

## Project Context

- **Bundle ID:** `pt.daphnia.SoapWiz`
- **Primary simulator:** iPad Air 11-inch (M2) — `BD145A0B-D38F-48F7-87CB-735E850987FF`
- **Fallback simulator:** iPad (A16) — `34E90319-8EDC-4B0F-BA5F-81650ED7AAE3`
- **Scripts root:** `.claude/skills/visual-regression/scripts/`
- **Build command:**
  ```bash
  xcodebuild build \
    -project SoapWiz.xcodeproj \
    -scheme SoapWiz \
    -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
    -quiet
  ```

## Process

### Step 1 — Environment check
```bash
bash .claude/skills/visual-regression/scripts/sim_health_check.sh
```
If idb is missing, fall back to `xcrun simctl` for interaction and `xcrun simctl io <udid> screenshot` for captures.

### Step 2 — Build
Run `xcodebuild build` (quiet). Stop and report on error.

### Step 3 — Boot & install
```bash
# Prefer already-booted simulator; boot if needed
python .claude/skills/visual-regression/scripts/app_launcher.py \
  --install <path-to.app> --launch pt.daphnia.SoapWiz
```
**Schema change rule:** Always uninstall before reinstalling when a model was added or a property type changed.

### Step 4 — Navigate to target screen
Use `app_launcher.py --open-url` for deep links when available, or `navigator.py` to tap through the UI.

| Screen | Navigation |
|---|---|
| `inventory` | App root — already on screen |
| `settings` | Tap "Settings" tab |
| `categories` | Settings → tap "Categories" row |
| `storage-locations` | Settings → tap "Storage Locations" row |
| `ingredient-detail` | Inventory → tap first ingredient |
| `batch-detail` | Ingredient detail → tap first batch |

Use `screen_mapper.py` to verify what's on screen if navigation fails.

### Step 5 — Screenshot & analyse
```bash
xcrun simctl io <udid> screenshot /tmp/soapwiz_regression_<screen>.png
```
Read the screenshot with the Read tool (multimodal). Analyse for:

**Layout issues:**
- Truncated text (labels cut off, `…` where not expected)
- Elements overlapping or clipping outside safe area
- Buttons or FAB off-screen or obscured
- Empty states where content is expected (or vice versa)
- Broken spacing or misaligned rows

**Functional issues:**
- Missing navigation elements (tab bar, back button, toolbar items)
- Wrong screen shown for the navigation path taken
- Count badges showing stale/incorrect values

**iOS 26 / Liquid Glass specifics:**
- Glass tab bar rendering at top on iPad (expected — not a bug)
- EditButton glass pill visible in toolbar when list has items
- FAB hidden correctly when edit mode is active

### Step 6 — Report

```
## Visual Regression — <screen> ✅ / ⚠️ / ❌

**Simulator:** iPad Air 11-inch (M2) — iOS 26
**Build:** <branch>

### Issues Found
- `<description>` — [severity: low / medium / high]

### Passed
- Layout renders within safe area
- Tab navigation accessible
- (etc.)
```

If issues are found, offer to fix immediately or log as a known issue.

## Interaction Primitives

```bash
# Map current screen elements
python scripts/screen_mapper.py

# Tap by visible text
python scripts/navigator.py --find-text "Settings" --tap

# Tap by element type
python scripts/navigator.py --find-type Button --tap

# Enter text in a field
python scripts/navigator.py --find-type TextField --enter-text "Olive Oil"

# Swipe / scroll
python scripts/gesture.py --swipe down

# Compare two screenshots
python scripts/visual_diff.py --before /tmp/before.png --after /tmp/after.png --threshold 0.02
```

## Notes

- Scripts auto-detect the booted simulator — no `--udid` needed if only one is booted.
- idb is optional; most features work with `xcrun simctl` alone.
- Never commit screenshots produced by this skill.
- Run after every feature branch before `/crpp` to catch visual regressions early.
