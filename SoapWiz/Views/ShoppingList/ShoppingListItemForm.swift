import SwiftUI
import SwiftData

/// Adds a line to the shopping list, or edits one.
struct ShoppingListItemForm: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let item: ShoppingListItem?
    let ingredients: [Ingredient]

    @State private var name: String
    @State private var amountText: String
    @State private var unit: String
    @State private var note: String
    @State private var ingredient: Ingredient?

    private static let maxMatches = 5

    init(item: ShoppingListItem? = nil, ingredients: [Ingredient]) {
        self.item = item
        self.ingredients = ingredients
        _name = State(initialValue: item?.name ?? "")
        _amountText = State(initialValue: item?.amount.map(Self.displayText) ?? "")
        _unit = State(initialValue: item?.unit ?? "")
        _note = State(initialValue: item?.note ?? "")
        _ingredient = State(initialValue: item?.ingredient)
    }

    private static func displayText(_ amount: Double) -> String {
        amount.formatted(.number.precision(.fractionLength(0...4)).grouping(.never))
    }

    private var amount: Double? {
        LocaleDecimal.parse(amountText.trimmingCharacters(in: .whitespaces))
    }

    private var hasUnreadableAmount: Bool {
        let trimmed = amountText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        guard let amount else { return true }
        return !amount.isFinite || amount <= 0
    }

    private var isDirty: Bool {
        name != (item?.name ?? "")
            || amountText != (item?.amount.map(Self.displayText) ?? "")
            || unit != (item?.unit ?? "")
            || note != (item?.note ?? "")
            || ingredient?.persistentModelID != item?.ingredient?.persistentModelID
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !hasUnreadableAmount
    }

    private var matches: [Ingredient] {
        let query = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ingredient == nil, !query.isEmpty else { return [] }
        return ingredients
            .filter { !$0.isHidden && $0.name.localizedStandardContains(query) }
            .prefix(Self.maxMatches)
            .map { $0 }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HoneyLedgerField("Name", text: $name, prompt: "Required")
                        .ledgerSheetRow(position: .only)
                }
                linkSection
                Section {
                    HoneyLedgerField(
                        "Amount",
                        text: $amountText.decimalOnly(),
                        prompt: "Optional",
                        unit: unit.isEmpty ? nil : unit,
                        error: hasUnreadableAmount ? String(localized: "Enter an amount above zero.") : nil,
                        keyboard: .decimalPad
                    )
                    .ledgerSheetRow(position: .first)
                    if ingredient == nil {
                        unitMenu
                            .ledgerSheetRow(position: .middle)
                    }
                    HoneyLedgerStackedField(title: "Note", text: $note, prompt: "Optional (e.g. brand, size)")
                        .ledgerSheetRow(position: .last)
                }
            }
            .navigationTitle(item == nil ? "New Item" : "Edit Item")
            .navigationBarTitleDisplayMode(.inline)
            .honeyLedgerInlineTitle(item == nil ? "New Item" : "Edit Item")
            .ledgerBackground()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(item == nil ? "Add" : "Save", action: save)
                        .disabled(!isValid)
                }
            }
            .interactiveDismissDisabled(isDirty)
        }
        .fitsSheetToContent()
    }

    @ViewBuilder
    private var linkSection: some View {
        if let ingredient {
            Section {
                HoneyLedgerLabeledRow("Ingredient") {
                    Button("Unlink") { self.ingredient = nil }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Color.amberText)
                } below: {
                    Text(ingredient.name)
                        .font(.subheadline)
                        .foregroundStyle(Color.inkSoft)
                }
                .ledgerSheetRow(position: .only)
            }
        } else if !matches.isEmpty {
            let matches = matches
            Section {
                ForEach(Array(matches.enumerated()), id: \.element.id) { index, match in
                    Button {
                        link(match)
                    } label: {
                        HStack {
                            Text(match.name)
                                .foregroundStyle(Color.ink)
                            Spacer()
                            if !match.unit.isEmpty {
                                Text(match.unit)
                                    .foregroundStyle(Color.inkSoft)
                            }
                        }
                    }
                    .ledgerSheetRow(position: .position(index: index, count: matches.count))
                }
            } header: {
                HoneyLedgerSectionLabel("Your ingredients")
            }
        }
    }

    private var unitMenu: some View {
        Menu {
            Button { unit = "" } label: {
                MenuSelectionLabel("None", isSelected: unit.isEmpty)
            }
            Divider()
            let units = IngredientUnit.allCases
            let symbols = MenuColumnPadding.padded(units.map(\.rawValue))
            ForEach(Array(zip(units, symbols)), id: \.0) { option, symbol in
                Button { unit = option.rawValue } label: {
                    MenuSelectionLabel("\(symbol) · \(option.label)", isSelected: unit == option.rawValue)
                }
            }
        } label: {
            PickerMenuRowLabel(
                title: "Unit",
                value: unit.isEmpty ? String(localized: "None") : unit,
                isPlaceholder: unit.isEmpty
            )
        }
        .tint(.primary)
    }

    private func link(_ match: Ingredient) {
        ingredient = match
        name = match.name
        unit = match.unit
    }

    private func save() {
        let model = ShoppingListViewModel(modelContext: modelContext)
        if let item {
            model.update(item, name: name, amount: amount, unit: unit, ingredient: ingredient, note: note)
        } else {
            model.addItem(name: name, amount: amount, unit: unit, ingredient: ingredient, note: note)
        }
        dismiss()
    }
}
