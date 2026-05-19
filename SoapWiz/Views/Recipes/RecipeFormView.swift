import SwiftUI
import SwiftData

private enum RecipeTab: String, CaseIterable {
    case config = "Config"
    case ingredients = "Ingredients"
    case stats = "Stats"
}

private let weightUnits = ["g", "oz", "lb", "kg", "%"]
private let absoluteWeightUnits = ["g", "oz", "lb", "kg"]

struct RecipeFormView: View {
    var recipe: Recipe? = nil

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \QuantityUnit.name) private var quantityUnits: [QuantityUnit]

    @State private var model = RecipeFormViewModel()
    @State private var selectedTab: RecipeTab = .config
    @State private var showingPicker = false
    @FocusState private var oilWeightFocused: Bool

    var onSave: ((Recipe) -> Void)?

    var body: some View {
        currentTab
            .safeAreaInset(edge: .top, spacing: 0) {
                Picker("Tab", selection: $selectedTab) {
                    ForEach(RecipeTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
            }
            .navigationTitle("New Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let recipe = model.save(context: modelContext)
                        onSave?(recipe)
                        dismiss()
                    }
                    .disabled(!model.canSave)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showingPicker) {
                IngredientPickerView(
                    addedIDs: Set(model.ingredientDrafts.map(\.ingredient.persistentModelID)),
                    onSelect: model.addIngredient
                )
            }
    }

    @ViewBuilder
    private var currentTab: some View {
        switch selectedTab {
        case .config: configTab
        case .ingredients: ingredientsTab
        case .stats: statsTab
        }
    }

    // MARK: - Config Tab

    private var configTab: some View {
        Form {
            detailsSection
            weightSection
            lyeSection
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            TextField("Name", text: $model.name)
            TextField("Description", text: $model.desc, axis: .vertical)
                .lineLimit(3...6)
        }
    }

    private var weightSection: some View {
        Section("Weight & unit") {
            HStack {
                Text("Measurement unit")
                Spacer()
                Picker("Unit", selection: $model.weightUnit) {
                    ForEach(weightUnits, id: \.self) { Text($0) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            if model.weightUnitIsPercentage {
                HStack {
                    Text("Total oil weight")
                    Spacer()
                    TextField("0", text: $model.totalOilWeight)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .focused($oilWeightFocused)
                    Picker("Oil unit", selection: $model.oilWeightUnit) {
                        ForEach(absoluteWeightUnits, id: \.self) { Text($0) }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.default, value: model.weightUnitIsPercentage)
        .onChange(of: model.weightUnitIsPercentage) { _, isPercentage in
            if isPercentage {
                Task {
                    try? await Task.sleep(for: .seconds(0.15))
                    oilWeightFocused = true
                }
            }
        }
    }

    private var lyeSection: some View {
        Section("Lye configuration") {
            HStack {
                Text("Lye type")
                Spacer()
                Text("NaOH")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Lye purity")
                Spacer()
                TextField("99", text: $model.lyePurity)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                Text("%")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Water to lye ratio")
                Spacer()
                TextField("2", text: $model.waterParts)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .frame(width: 30)
                Text(":")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                TextField("1", text: $model.lyeParts)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .frame(width: 30)
            }
            HStack {
                Text("Super Fat")
                Spacer()
                TextField("5", text: $model.superFat)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                Text("%")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Ingredients Tab

    private var ingredientsTab: some View {
        Form {
            Section("Ingredients") {
                HStack {
                    Button {
                        showingPicker = true
                    } label: {
                        Label("Add ingredient", systemImage: "plus")
                    }
                    Spacer()
                    if !model.ingredientDrafts.isEmpty {
                        Text(model.totalPercentageText)
                            .foregroundStyle(abs(model.totalPercentage - 100) < 0.1 ? Color.green : Color.red)
                            .frame(width: 60, alignment: .trailing)
                        Text("%")
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(model.ingredientDrafts) { draft in
                    HStack {
                        Text(draft.ingredient.name)
                        Spacer()
                        TextField("0", text: Binding(
                            get: { draft.percentage },
                            set: { model.userEdited(id: draft.id, percentage: $0) }
                        ))
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                        Text("%")
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { model.removeIngredient(at: $0) }
            }

            if !model.ingredientDrafts.isEmpty {
                Section("Products") {
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 0) {
                                ForEach($model.productDrafts) { $draft in
                                    let result = model.breakdownAndCost(for: draft)
                                    RecipeProductCardView(
                                        draft: $draft,
                                        breakdown: result.breakdown,
                                        totalCost: result.total,
                                        availableUnits: quantityUnits
                                    )
                                    .containerRelativeFrame(.horizontal)
                                    .id(draft.id)
                                }
                                AddProductCardView {
                                    let symbol = quantityUnits.first?.symbol ?? ""
                                    model.addProduct(defaultUnitSymbol: symbol)
                                    if let newID = model.productDrafts.last?.id {
                                        withAnimation { proxy.scrollTo(newID) }
                                    }
                                }
                                .containerRelativeFrame(.horizontal)
                                .id("addButton")
                            }
                            .scrollTargetLayout()
                        }
                        .scrollTargetBehavior(.paging)
                    }
                    .listRowInsets(EdgeInsets())

                    if !model.productDrafts.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(0...model.productDrafts.count, id: \.self) { _ in
                                Circle()
                                    .fill(Color.secondary.opacity(0.5))
                                    .frame(width: 6, height: 6)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    // MARK: - Stats Tab

    private var statsTab: some View {
        Form {
            Section {
                Text("Cost breakdown and soap properties coming soon.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
