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

    @State private var model = RecipeFormViewModel()
    @State private var selectedTab: RecipeTab = .config
    @State private var showFragranceInfo = false
    @FocusState private var oilWeightFocused: Bool

    var onSave: ((Recipe) -> Void)?

    var body: some View {
        currentTab
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .safeAreaInset(edge: .top, spacing: 0) {
                Picker("Tab", selection: $selectedTab) {
                    ForEach(RecipeTab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .navigationTitle(recipe == nil ? "New Recipe" : "Edit Recipe")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: recipe?.persistentModelID) {
                guard let recipe else { return }
                model.load(from: recipe)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let recipe = model.save(context: modelContext)
                        onSave?(recipe)
                        dismiss()
                    }
                    .disabled(!model.canSave)
                }
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
}

// MARK: - Config Tab

private extension RecipeFormView {
    var configTab: some View {
        Form {
            detailsSection
            weightSection
            lyeSection
            fragranceSection
        }
        .scrollClipDisabled()
        .sheet(isPresented: $showFragranceInfo) {
            VStack(alignment: .leading, spacing: 12) {
                Text("EO / Fragrances %")
                    .font(.headline)
                Text("The target percentage of total oil weight reserved for essential oils and fragrance oils. Used to calculate the recommended amount and to track usage in the Ingredients tab.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .presentationDetents([.fraction(0.3)])
            .presentationDragIndicator(.visible)
        }
    }

    var detailsSection: some View {
        Section("Details") {
            TextField("Name", text: $model.name)
            TextField("Description", text: $model.desc, axis: .vertical)
                .lineLimit(3...6)
        }
    }

    var weightSection: some View {
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

    var lyeSection: some View {
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
                TextField("1.5", text: $model.waterParts)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.center)
                    .frame(width: 30)
                Text(":")
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                Text("1")
                    .foregroundStyle(.secondary)
                    .frame(width: 30, alignment: .center)
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

    var fragranceSection: some View {
        Section("Fragrance configuration") {
            HStack {
                Text("EO / Fragrances")
                Button {
                    showFragranceInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                Spacer()
                TextField("3", text: $model.fragrancePercentage)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 60)
                Text("%")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Ingredients Tab

private extension RecipeFormView {
    var ingredientsTab: some View {
        RecipeIngredientsTabView(model: model)
    }
}

// MARK: - Stats Tab

private extension RecipeFormView {
    var statsTab: some View {
        Form {
            Section {
                Text("Cost breakdown and soap properties coming soon.")
                    .foregroundStyle(.secondary)
            }
        }
        .scrollClipDisabled()
    }
}
