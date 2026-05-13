---
name: plan-feature
description: Feature planning assistant. Use before starting any feature that touches more than one file or introduces a new model, view, or ViewModel.
---

# Plan Feature

Use this before starting any new feature that touches more than one file or adds a new model/view.

## Steps

### 1. Gather context
- Read the relevant existing files (models, views, app entry point).
- Check CLAUDE.md for any constraints that apply.
- Run `confidence-check` if requirements feel ambiguous.

### 2. Draft the plan

Produce a short plan in this format:

```
## Feature: <name>

### What it does
One or two sentences.

### Files to create
- Path/To/NewFile.swift — purpose

### Files to modify
- Path/To/ExistingFile.swift — what changes and why

### Data model changes
List any new @Model types or new properties, with types and relationships.

### Order of work
1. Step one
2. Step two
...
```

### 3. Wait for approval

Present the plan. Do **not** write any implementation code until the user approves.

### 4. Implement

Work through the steps in order. Run `self-review` when done.

## Scope rules

- No extra abstractions beyond what the plan requires.
- No placeholder TODOs or half-finished implementations.
- If a step turns out to require a design decision not covered by the plan, pause and ask — don't invent.
