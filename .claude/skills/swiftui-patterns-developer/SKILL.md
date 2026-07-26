---
name: swiftui-patterns-developer
description: SwiftUI view structure and composition — body ordering, extracting subviews, splitting an oversized view file, @ViewBuilder usage. Use when a view file has grown too large or when reorganising a view's internals. Not for state management or API choice (see swiftui-expert), performance audits (see swiftui-performance-developer), or SoapWiz data conventions (see swiftui-patterns-soapwiz).
---

# SwiftUI Patterns Developer (Smart Router)

## Purpose
Apply consistent structure and patterns to SwiftUI views, with focus on ordering, subview extraction, and proper composition.

## When Auto-Activated
- Refactoring SwiftUI view structure
- Organizing view file layout
- Splitting large views into subviews
- Keywords: view structure, view ordering, split view, extract subview, large view, refactor view

## Core Guidelines

### 0) Three Qualities of SwiftUI Views (WWDC24)

Understanding these fundamentals helps you write better SwiftUI code:

**1. Declarative** — Describe what you want, not how to create it:
```swift
// ✅ Declarative - describe the result
List(ingredients) { ingredient in
    HStack {
        Text(ingredient.name)
        Spacer()
        Text(ingredient.unit)
    }
}
// No need to add/remove rows manually - SwiftUI handles it
```

**2. Compositional** — Build complex UIs from simple building blocks:
```swift
// ViewBuilder closures define children of containers
HStack {
    Image(systemName: "flask")
    VStack(alignment: .leading) {
        Text(ingredient.name)
        Text(ingredient.category ?? "—")
    }
    Spacer()
}
```

**3. State-Driven** — UI automatically updates when state changes:
```swift
// SwiftUI tracks dependencies and updates views automatically
@State private var count = 0

var body: some View {
    Button("Count: \(count)") {  // Dependency on `count`
        count += 1               // State change triggers re-render
    }
}
```

**Key insight**: Views are VALUE TYPES (structs), not long-lived objects. They are descriptions of current UI state, not objects that receive commands over time. SwiftUI maintains the actual UI behind the scenes.

### 1) View Ordering (top → bottom)

```swift
struct IngredientFormView: View {
    // 1. Property wrappers (@State, @Environment, @Query)
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var categories: [IngredientCategory]
    @State private var model: IngredientFormViewModel

    // 2. Public properties
    let ingredient: Ingredient?

    // 3. Private properties
    private var isEditing: Bool { ingredient != nil }

    // 4. init (if needed)
    init(ingredient: Ingredient? = nil) {
        self.ingredient = ingredient
        _model = State(wrappedValue: IngredientFormViewModel(ingredient: ingredient))
    }

    // 5. body
    var body: some View {
        content
            .navigationTitle(isEditing ? "Edit Ingredient" : "New Ingredient")
    }

    // 6. Computed view builders
    private var content: some View { ... }

    // 7. Helper / async functions
    private func save() { ... }
}
```

### 2) ViewModel Pattern (SoapWiz Standard)

SoapWiz uses **MVVM with ViewModels**. Always use ViewModels for business logic:

```swift
// View — lightweight, UI only
struct IngredientFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var model: IngredientFormViewModel

    init(ingredient: Ingredient? = nil) {
        _model = State(wrappedValue: IngredientFormViewModel(ingredient: ingredient))
    }

    var body: some View {
        form
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { model.save(context: modelContext); dismiss() }
                        .disabled(!model.isValid)
                }
            }
    }

    private var form: some View {
        Form {
            TextField("Name", text: $model.name)
        }
    }
}

// ViewModel — handles business logic
@MainActor
@Observable
final class IngredientFormViewModel {
    var name: String = ""
    var unit: String = ""

    var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    init(ingredient: Ingredient? = nil) {
        if let ingredient {
            name = ingredient.name
            unit = ingredient.unit
        }
    }

    func save(context: ModelContext) {
        // Persistence logic here
    }
}
```

**Key points:**
- Use `@State private var model: ViewModel` in views
- Initialize ViewModel in view's `init` with `_model = State(wrappedValue:)`
- Keep ViewModel init cheap — heavy work in `.task`
- Use `@Observable` macro (not `ObservableObject`)
- Mark ViewModels `@MainActor`
- `@Query` and `@Environment(\.modelContext)` stay in views (SwiftData requirement)

### 3) How Observation Works (WWDC23)

Understanding **why** `@Observable` works helps you use it correctly.

**Property Access Tracking:**
- SwiftUI tracks which properties you **access** during `body` evaluation
- Only those accessed properties trigger view invalidation when changed
- Properties NOT read in `body` don't cause re-renders (unlike `@Published`)

```swift
@Observable
final class IngredientDetailViewModel {
    var name: String = ""            // Accessed in body → triggers update
    var isLoading: Bool = false      // Accessed in body → triggers update
    var internalCache: [String] = [] // NOT accessed in body → no update
}
```

**Per-Instance Tracking:**
- Arrays of `@Observable` objects work efficiently
- Only the specific instance that changed triggers updates

```swift
// Each IngredientRow only updates when ITS ingredient changes
List(ingredients) { ingredient in
    IngredientRow(ingredient: ingredient)
}
```

**Computed Properties Just Work:**
- Computed properties composed from stored properties are automatically tracked
- SwiftUI traces through to the underlying stored properties

```swift
@Observable
final class BatchFormViewModel {
    var quantity: Double = 0
    var totalPrice: Double = 0

    // Computed → tracks both `quantity` and `totalPrice`
    var pricePerUnit: Double {
        guard quantity > 0 else { return 0 }
        return totalPrice / quantity
    }
}
```

**Performance Benefit:**
With `@Observable`, views only update when properties they actually read change. This is more efficient than `ObservableObject` where ANY `@Published` change triggers `objectWillChange` for ALL subscribers.

### 4) Property Wrapper Decision Tree

When to use which wrapper with `@Observable`:

| Scenario | Wrapper | Why |
|----------|---------|-----|
| View **owns** model lifecycle | `@State` | View creates and manages the model |
| Model shared **app-wide** | `@Environment` | Injected at app root, read anywhere |
| Just need **bindings** ($syntax) | `@Bindable` | Pass to TextField, Toggle, etc. |
| Just **reading** the model | Nothing | Direct property access triggers tracking |

```swift
// View OWNS the model (creates it)
struct IngredientFormView: View {
    @State private var model: IngredientFormViewModel

    init(ingredient: Ingredient? = nil) {
        _model = State(wrappedValue: IngredientFormViewModel(ingredient: ingredient))
    }
}

// Need $ bindings inside body
var body: some View {
    @Bindable var model = model  // Local binding for $ syntax
    TextField("Name", text: $model.name)
}

// Just reading, no bindings needed
struct IngredientRow: View {
    let ingredient: Ingredient  // Nothing — just read properties

    var body: some View {
        Text(ingredient.name)
        Image(systemName: ingredient.totalRemaining > 0 ? "checkmark.circle" : "exclamationmark.circle")
    }
}
```

**Migration from ObservableObject:**

| Old | New |
|-----|-----|
| `@StateObject` | `@State` |
| `@ObservedObject` | `@Bindable` or nothing |
| `@EnvironmentObject` | `@Environment` |

### 5) Migration from ObservableObject

Step-by-step conversion from legacy `ObservableObject`:

**Before (ObservableObject):**
```swift
class IngredientFormViewModel: ObservableObject {
    @Published var name: String = ""
    @Published var unit: String = ""
}

struct IngredientFormView: View {
    @StateObject private var model = IngredientFormViewModel()

    var body: some View {
        TextField("Name", text: $model.name)
        TextField("Unit", text: $model.unit)
    }
}
```

**After (@Observable):**
```swift
@Observable
final class IngredientFormViewModel {
    var name: String = ""
    var unit: String = ""
}

struct IngredientFormView: View {
    @State private var model = IngredientFormViewModel()

    var body: some View {
        @Bindable var model = model  // Local binding for $ syntax
        TextField("Name", text: $model.name)
        TextField("Unit", text: $model.unit)
    }
}
```

**Migration Steps:**
1. Remove `ObservableObject` conformance, add `@Observable` macro
2. Remove `@Published` from all properties (observation is automatic)
3. Add `@ObservationIgnored` to properties that shouldn't trigger updates
4. Change `@StateObject` → `@State` in views
5. For `$` binding syntax, use `@Bindable var model = model` in body
6. Replace `@EnvironmentObject` with `@Environment`

### 6) View Modifiers and Order (WWDC24)

View modifiers create a hierarchical structure. **Order matters** — modifiers are applied sequentially:

```swift
// Each modifier wraps the previous result
Image(systemName: "flask")
    .clipShape(Circle())      // 1. Clip to circle first
    .shadow(radius: 4)        // 2. Add shadow to clipped shape
    .overlay(                 // 3. Overlay on top of shadow
        Circle().stroke(Color.accentColor, lineWidth: 2)
    )
```

The hierarchy and order of effect is defined by the exact order of modifiers. Chaining modifiers makes it clear how results are produced and how to customize them.

### 7) Adaptive Views (WWDC24)

SwiftUI views describe **purpose**, not exact visual construction. This enables adaptation:

**Buttons** — Same purpose (labeled action), different contexts:
```swift
// Adapts to: borderless, bordered, prominent styles
// Adapts to: swipe actions, menus, forms
Button("Edit", action: handleEdit)

// In swipe actions
.swipeActions {
    Button("Delete", role: .destructive) { delete() }
    Button("Archive") { archive() }
}
```

**Toggles** — Switch, checkbox, or toggle button depending on context:
```swift
// Automatically shows appropriate style for platform/context
Toggle("Has Expiry Date", isOn: $hasExpiryDate)
```

**Searchable** — Describes capability, SwiftUI handles idiomatic presentation:
```swift
// iOS: overlay list, filters as search suggestions
List(filteredIngredients) { ... }
    .searchable(text: $searchText)
    .searchSuggestions {
        ForEach(suggestions) { Text($0) }
    }
```

### 8) Split Large Bodies

If `body` grows beyond a screen, split into smaller subviews:

```swift
// Computed view properties (same file)
var body: some View {
    List {
        purchaseSection
        identificationSection
        datesSection
    }
}

private var purchaseSection: some View { ... }
private var identificationSection: some View { ... }
private var datesSection: some View { ... }
```

```swift
// Extracted subview (reusable or complex)
struct SectionHeader: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.headline)
            if let subtitle {
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
```

### 9) ViewState Enum Pattern

For views with loading/error/loaded states:

```swift
enum ViewState {
    case loading
    case error(String)
    case loaded
}

@MainActor
@Observable
final class FeedViewModel {
    var viewState: ViewState = .loading
    var items: [Item] = []

    func load() async {
        do {
            items = try await service.fetchAll()
            viewState = .loaded
        } catch {
            viewState = .error(error.localizedDescription)
        }
    }
}

struct FeedView: View {
    @State private var model: FeedViewModel

    var body: some View {
        content
            .task { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.viewState {
        case .loading:
            ProgressView()
        case .error(let message):
            ContentUnavailableView(message, systemImage: "exclamationmark.triangle")
        case .loaded:
            List(model.items) { ItemRow(item: $0) }
        }
    }
}
```

### 10) State, Binding, and Source of Truth (WWDC24)

**@State** creates internal source of data for a view:
```swift
struct RatingView: View {
    @State private var rating = 0  // View owns this state

    var body: some View {
        HStack {
            Text("\(rating)")
            Button("+") { rating += 1 }
            Button("-") { rating -= 1 }
        }
    }
}
```

**@Binding** creates two-way reference to state owned elsewhere:
```swift
struct BatchFormView: View {
    @State private var quantity: Double = 0  // Single source of truth

    var body: some View {
        VStack {
            Text("Quantity: \(quantity)")
            QuantityEditor(quantity: $quantity)  // Pass binding
        }
    }
}

struct QuantityEditor: View {
    @Binding var quantity: Double  // Two-way reference to parent's state

    var body: some View {
        TextField("0", value: $quantity, format: .number)  // Updates parent's state
    }
}
```

**Key principle**: One source of truth. When multiple views need the same data, lift state up to common ancestor and pass bindings down.

### 11) Animation with State Changes (WWDC24)

Wrap state changes with `withAnimation` to animate resulting view updates:

```swift
Button("Add Batch") {
    withAnimation {
        showingAddBatch = true
    }
}
```

Customize transitions for specific views:
```swift
Text("\(batch.remainingAmount, format: .number)")
    .contentTransition(.numericText())  // Smooth number transition
```

Animations in SwiftUI build on the same data-driven updates — when state changes, views update, and `withAnimation` makes those updates animate.

### 12) Task and onChange Usage

```swift
// Initial load
.task {
    await model.loadData()
}

// React to identity change (re-runs when searchText changes)
.task(id: searchText) {
    guard !searchText.isEmpty else { return }
    await model.search(query: searchText)
}

// React to value change
.onChange(of: selectedCategory) { _, newValue in
    model.filterByCategory(newValue)
}
```

### 13) Large View File Organization

When file exceeds ~300 lines:

```swift
struct IngredientDetailView: View {
    // Properties and body here
}

// MARK: - Subviews
private extension IngredientDetailView {
    var batchList: some View { ... }
    var summaryHeader: some View { ... }
}

// MARK: - Actions
private extension IngredientDetailView {
    func deleteSelected() { ... }
}
```

## Common Mistakes

### Missing ViewModel for Complex Views
```swift
// ❌ WRONG — Business logic in view
struct BatchFormView: View {
    @State private var quantity: Double = 0
    @State private var totalPrice: Double = 0

    private var pricePerUnit: Double { totalPrice / quantity }  // logic in view

    private func save() { ... }  // persistence in view
}

// ✅ CORRECT — ViewModel handles business logic
struct BatchFormView: View {
    @State private var model: BatchFormViewModel
    // pricePerUnit and save() live in ViewModel
}
```

### Avoid Group with Lifecycle Modifiers + Conditionals

```swift
// ❌ WRONG — onAppear can fire multiple times
var body: some View {
    Group {
        if model.isLoading {
            ProgressView()
        } else {
            content
        }
    }
    .onAppear { model.onAppear() }
}

// ✅ CORRECT — Use @ViewBuilder
var body: some View {
    loadingContent
        .onAppear { model.onAppear() }
}

@ViewBuilder
private var loadingContent: some View {
    if model.isLoading {
        ProgressView()
    } else {
        content
    }
}
```

### Task Inside onAppear Instead of .task Modifier

```swift
// ❌ WRONG — not cancelled on disappear, fires on every re-appear
.onAppear {
    Task { await model.loadData() }
}

// ✅ CORRECT — cancelled automatically when view disappears
.task {
    await model.loadData()
}
```

## Related Skills

- **ios-dev-guidelines** → Full MVVM patterns, code style, critical rules
- **swiftui-patterns-soapwiz** → SoapWiz-specific conventions (SwiftData, FAB, form pattern)
- **swiftui-expert** → In-depth SwiftUI API guidance, state management, performance
- **swiftui-performance-developer** → Performance optimization, view invalidation

---

**Navigation**: This skill provides SwiftUI structure patterns. For full API guidance, see the `swiftui-expert` skill.

**Attribution**: View structure patterns adapted from [Dimillian/Skills](https://github.com/Dimillian/Skills). WWDC24 insights from "SwiftUI Essentials" session.
