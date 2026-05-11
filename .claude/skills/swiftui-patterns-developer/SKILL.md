---
name: swiftui-patterns-developer
description: SwiftUI view structure, composition, and best practices. Use when refactoring SwiftUI views, organizing view files, or extracting subviews.
---

# SwiftUI Patterns Developer

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
List(ingredients) { ingredient in
    HStack {
        Text(ingredient.name)
        Spacer()
        Text(ingredient.unit)
    }
}
// No need to add/remove rows manually — SwiftUI handles it
```

**2. Compositional** — Build complex UIs from simple building blocks:
```swift
HStack {
    Image(systemName: "flask")
    VStack(alignment: .leading) {
        Text(ingredient.name)
        Text(ingredient.category?.name ?? "—")
    }
    Spacer()
}
```

**3. State-Driven** — UI automatically updates when state changes:
```swift
@State private var count = 0

var body: some View {
    Button("Count: \(count)") {
        count += 1
    }
}
```

**Key insight**: Views are VALUE TYPES (structs), not long-lived objects. They are descriptions of current UI state, not objects that receive commands over time. SwiftUI maintains the actual UI behind the scenes.

### 1) View Ordering (top → bottom)

```swift
struct IngredientFormView: View {
    // 1. Environment / Query
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var categories: [IngredientCategory]

    // 2. ViewModel (once SW-37 is implemented)
    @State private var model: IngredientFormViewModel

    // 3. Public properties
    let ingredient: Ingredient?

    // 4. Computed properties
    private var isEditing: Bool { ingredient != nil }

    // 5. init (if needed)
    init(ingredient: Ingredient? = nil) {
        self.ingredient = ingredient
        _model = State(initialValue: IngredientFormViewModel(ingredient: ingredient))
    }

    // 6. body
    var body: some View {
        content
            .navigationTitle(isEditing ? "Edit Ingredient" : "New Ingredient")
    }

    // 7. Computed view builders
    private var content: some View { ... }

    // 8. Helper functions
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
        _model = State(initialValue: IngredientFormViewModel(ingredient: ingredient))
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
    var selectedCategory: IngredientCategory?

    var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    init(ingredient: Ingredient? = nil) {
        if let ingredient {
            name = ingredient.name
            unit = ingredient.unit
            selectedCategory = ingredient.category
        }
    }

    func save(context: ModelContext) {
        // Persistence logic here
    }
}
```

**Key points:**
- Use `@State private var model: ViewModel` in views
- Initialize ViewModel in view's `init` with `_model = State(initialValue:)`
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
    var name: String = ""           // Accessed in body → triggers update
    var isLoading: Bool = false     // Accessed in body → triggers update
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
        _model = State(initialValue: IngredientFormViewModel(ingredient: ingredient))
    }
}

// Need $ bindings inside body
var body: some View {
    @Bindable var model = model
    TextField("Name", text: $model.name)
}

// Just reading, no bindings needed
struct IngredientRow: View {
    let ingredient: Ingredient  // Nothing — just read properties

    var body: some View {
        Text(ingredient.name)
    }
}
```

**Migration from ObservableObject (for SW-37):**

| Old | New |
|-----|-----|
| `@StateObject` | `@State` |
| `@ObservedObject` | `@Bindable` or nothing |
| `@EnvironmentObject` | `@Environment` |

### 5) Migration from ObservableObject (SW-37 Reference)

Step-by-step conversion when implementing ViewModels per SW-37:

**Before (no ViewModel — current state):**
```swift
struct IngredientFormView: View {
    @State private var name = ""
    @State private var unit = ""

    private var isValid: Bool { !name.isEmpty }

    private func save() {
        // persistence logic directly in view
    }
}
```

**After (@Observable ViewModel):**
```swift
@Observable
final class IngredientFormViewModel {
    var name: String = ""
    var unit: String = ""
    var isValid: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    func save(context: ModelContext) { ... }
}

struct IngredientFormView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var model = IngredientFormViewModel()

    var body: some View {
        @Bindable var model = model
        TextField("Name", text: $model.name)
    }
}
```

**Migration Steps:**
1. Create `ViewModel` class with `@Observable` + `@MainActor`
2. Move `@State` vars, validation, and save/delete logic into ViewModel
3. Remove `@Published` / `ObservableObject` if present
4. Add `@ObservationIgnored` to properties that shouldn't trigger updates
5. Change `@StateObject` → `@State` in views
6. For `$` binding syntax, use `@Bindable var model = model` in body

### 6) View Modifiers and Order (WWDC24)

View modifiers create a hierarchical structure. **Order matters** — modifiers are applied sequentially:

```swift
Image(systemName: "flask")
    .clipShape(Circle())
    .shadow(radius: 4)
    .overlay(
        Circle().stroke(.accent, lineWidth: 2)
    )
```

### 7) Adaptive Views (WWDC24)

SwiftUI views describe **purpose**, not exact visual construction:

```swift
// Adapts to context automatically
Button("Edit", action: handleEdit)

// In swipe actions
.swipeActions {
    Button("Delete", role: .destructive) { delete() }
}

// Toggle adapts to platform/context
Toggle("Has Expiry Date", isOn: $hasExpiryDate)

// Searchable handles idiomatic presentation
List(filteredIngredients) { ... }
    .searchable(text: $searchText)
```

### 8) Split Large Bodies

If `body` grows beyond a screen, split into smaller subviews:

```swift
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
// Extracted reusable subview
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
final class IngredientListViewModel {
    var viewState: ViewState = .loading
    var ingredients: [Ingredient] = []

    func load() async {
        do {
            ingredients = try await ingredientService.all()
            viewState = .loaded
        } catch {
            viewState = .error(error.localizedDescription)
        }
    }
}

struct IngredientListView: View {
    @State private var model: IngredientListViewModel

    var body: some View {
        content
            .task { await model.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.viewState {
        case .loading: ProgressView()
        case .error(let message): Text(message).foregroundStyle(.red)
        case .loaded: List(model.ingredients) { IngredientRow(ingredient: $0) }
        }
    }
}
```

### 10) State, Binding, and Source of Truth (WWDC24)

**@State** creates internal source of data for a view:
```swift
struct RatingView: View {
    @State private var rating = 0

    var body: some View {
        HStack {
            Text("\(rating)")
            Button("+") { rating += 1 }
        }
    }
}
```

**@Binding** creates two-way reference to state owned elsewhere:
```swift
struct BatchFormView: View {
    @State private var quantity: Double = 0  // Single source of truth

    var body: some View {
        QuantityEditor(quantity: $quantity)
    }
}

struct QuantityEditor: View {
    @Binding var quantity: Double  // Two-way reference

    var body: some View {
        TextField("0", value: $quantity, format: .number)
    }
}
```

**Key principle**: One source of truth. When multiple views need the same data, lift state up to common ancestor and pass bindings down.

### 11) Animation with State Changes (WWDC24)

```swift
Button("Add Batch") {
    withAnimation {
        showingAddBatch = true
    }
}

Text("\(batch.remainingAmount)")
    .contentTransition(.numericText())
```

### 12) Task and onChange Usage

```swift
// Initial load
.task {
    await model.loadData()
}

// React to state changes
.task(id: searchText) {
    guard !searchText.isEmpty else { return }
    await model.search(query: searchText)
}

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

### Using onAppear with Group + Conditionals
```swift
// ❌ WRONG — onAppear can fire multiple times
var body: some View {
    Group {
        if model.isLoading { ProgressView() }
        else { content }
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
    if model.isLoading { ProgressView() }
    else { content }
}
```

## Related Skills

- **ios-dev-guidelines** → Full MVVM patterns, code style, critical rules
- **swiftui-performance-developer** → Performance optimization, view invalidation
