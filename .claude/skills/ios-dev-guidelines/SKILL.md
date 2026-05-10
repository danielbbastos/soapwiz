# iOS Development Guidelines

Reference this for Swift/iOS architectural patterns and non-negotiable practices in SoapWiz.

## Critical Rules

- Never hardcode UI strings — use string constants or localization keys
- Never trim whitespace-only lines from generated or existing files unintentionally
- Update tests when refactoring any production code that is tested
- All SwiftData model access stays on `@MainActor` (project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`)
- No new external dependencies without explicit discussion

## Architecture Patterns

**ViewModels** (when needed):
- Annotate with `@MainActor`
- Keep `init` lightweight — defer expensive work to `.task`
- ViewModels are optional for simple views; use `@Query` + local `@State` directly for straightforward list/detail views

**Navigation:**
- Root view is `IngredientListView` inside `NavigationStack`
- Push navigation via `NavigationLink`
- Creation and edit flows via sheets

**Dependency injection:**
- `ModelContainer` is created once in `SoapWizApp` and flows via `.modelContainer()`
- Never create a second `ModelContainer`

## SwiftUI Best Practices

- Views are value types — decompose freely into subviews without performance concern
- `body` should be declarative and readable; extract private computed view properties when it grows complex
- Defer expensive work to `.task`, not `init` or `onAppear` when avoidable
- Use `Button` over raw gesture handlers for accessibility

## Project Conventions

- PascalCase for types, camelCase for properties and functions
- 4-space indentation
- Ordering inside a view struct: property wrappers → public properties → private properties → computed properties → `body` → private view builders → helper functions

## Naming

| Thing | Convention |
|---|---|
| View | `<Noun>View`, `<Noun>RowView`, `<Noun>FormView`, `<Noun>DetailView` |
| Model | `<Noun>` (e.g., `Ingredient`, `IngredientBatch`) |
| Sheet presentation | `@State var showingAddThing = false` |
