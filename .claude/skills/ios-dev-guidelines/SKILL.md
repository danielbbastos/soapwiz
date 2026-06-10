---
name: ios-dev-guidelines
description: Context-aware routing to Swift/iOS development patterns, architecture, and best practices. Use when working with .swift files, ViewModels, Coordinators, refactoring, or discussing Swift/SwiftUI patterns.
---

# iOS Development Guidelines (Smart Router)

## Purpose
Context-aware routing to iOS development patterns, code style, and architecture guidelines. This skill provides critical rules and points you to comprehensive documentation.

## When Auto-Activated
- Working with `.swift` files
- Discussing ViewModels, architecture
- Refactoring or formatting code
- Keywords: swift, swiftui, mvvm, async, await, refactor

## 🚨 CRITICAL RULES (NEVER VIOLATE)

1. **NEVER trim whitespace-only lines** — Preserve blank lines with spaces/tabs exactly as they appear
2. **NEVER add comments** unless explicitly requested
3. **ALWAYS update tests when refactoring** — Search for all references and update
4. **NEVER commit without explicit user request** — Committing is destructive and irreversible
5. **Always verify before deleting files** — Use `ls` to check; delete files individually, never with wildcards
6. **Search all usages before renaming** — `rg "oldName" --type swift`; update tests, mocks, registrations

## 📋 Quick Checklist

Before completing any task:
- [ ] Whitespace-only lines preserved (not trimmed)
- [ ] No comments added (unless requested)
- [ ] Tests updated if dependencies changed
- [ ] Explicit commit request received before committing
- [ ] File existence confirmed before deletion

## 🎯 SwiftUI View Fundamentals (WWDC24)

SwiftUI views have three key qualities:

1. **Declarative** — Describe what you want, not how to build it
2. **Compositional** — Build complex UIs from simple building blocks
3. **State-driven** — UI automatically updates when state changes

**Key insight**: Views are VALUE TYPES (structs), not long-lived objects. They are descriptions of current UI state. Breaking views into subviews doesn't hurt performance — SwiftUI maintains efficient data structures behind the scenes.

For detailed SwiftUI patterns, see **swiftui-patterns-developer** skill.

## 🎯 Common Patterns

### MVVM ViewModel
```swift
@MainActor
@Observable
final class IngredientFormViewModel {
    var name: String = ""
    var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    private let modelContext: ModelContext

    init(modelContext: ModelContext, ingredient: Ingredient? = nil) {
        self.modelContext = modelContext
        if let ingredient { self.name = ingredient.name }
    }

    func save() {
        modelContext.insert(Ingredient(name: name))
    }
}
```

### ViewModel Initialization
Keep ViewModel `init()` cheap — defer heavy work to `.task`:
```swift
// Init assigns parameters only
init(ingredient: Ingredient, modelContext: ModelContext) {
    _model = State(wrappedValue: IngredientFormViewModel(modelContext: modelContext, ingredient: ingredient))
}

// Heavy work in .task
.task { await model.loadRelatedData() }
```

For expensive init, defer creation entirely:
```swift
@State private var model: ViewModel?
.task(id: id) { model = ViewModel(id: id) }
```

## 🗂️ Project Structure

```
SoapWiz/
├── Models/              # SwiftData @Model entities (Ingredient, IngredientPurchase, Recipe, Batch, etc.)
├── ViewModels/          # @Observable @MainActor ViewModels (Inventory/, Recipes/, Batches/, Settings/)
├── Views/
│   ├── ContentView.swift  # Root TabView: Inventory · Recipes · History · Settings
│   ├── Inventory/       # Ingredient list, detail, purchase views
│   ├── Recipes/         # Recipe list, form, detail, stats
│   ├── Batches/         # Batch history list, detail, create-batch sheet
│   ├── Settings/        # Settings, categories, providers, storage locations
│   └── Components/      # FloatingActionButton, View+iOS26
├── Navigation/          # AppNavigation (@Observable tab/path state)
├── Extensions/
├── DataSeeder.swift     # Seeds demo data into an empty store
└── SoapWizApp.swift     # @main, ModelContainer setup
```

## 🔧 Code Style Quick Reference

- **Indentation**: 4 spaces (no tabs)
- **Naming**: PascalCase (types), camelCase (variables/functions)
- **Extensions**: `TypeName+Feature.swift`
- **Property order**: `@Environment`/`@Query`/`@State` → public → private → computed → init → methods
- **Avoid nested types** — Extract to top-level with descriptive names
- **Enum exhaustiveness** — Use explicit switch statements (enables compiler warnings)

## 🔗 Related Skills

- **swiftui-patterns-developer** → View structure, composition, @Observable patterns
- **swiftui-performance-developer** → Performance auditing, view invalidation
