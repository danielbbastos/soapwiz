import SwiftUI
import SwiftData

/// Where an inventory import is checked before anything is written.
///
/// Rows are listed by what the import will do with them: add stock to an
/// ingredient already in the inventory, create a new ingredient, or nothing,
/// with the reason. The user can turn rows off and point an ingredient at
/// another match. Nothing is saved until the confirm button, which saves and
/// hands the result to `onFinished`; the flow that presents this screen owns
/// what is shown next.
struct InventoryImportReviewView: View {
    let model: InventoryImportReviewViewModel
    var onFinished: (InventoryImportResult) -> Void

    @Environment(\.modelContext) private var modelContext
    @Query(sort: \IngredientCategory.name) private var categories: [IngredientCategory]
    @State private var matchingEntry: InventoryImportEntry?

    var body: some View {
        Form {
            noticeSection
            matchedSection
            newSection
            blockedSection
        }
        .environment(\.defaultMinListRowHeight, 48)
        .readableWidth()
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    model.confirm(in: modelContext)
                    if let result = model.result {
                        onFinished(result)
                    }
                } label: {
                    Text(confirmTitle)
                        .contentTransition(.numericText(value: Double(model.importableCount)))
                }
                .disabled(!model.canConfirm)
            }
        }
        .sheet(item: $matchingEntry) { entry in
            InventoryImportMatchPickerView(
                current: currentMatch(of: entry),
                canCreateNew: model.canResetToNew(entry),
                onSelect: { ingredient in
                    InventoryImportMotion.animate {
                        model.rematch(entry: entry.id, to: ingredient)
                    }
                },
                onCreateNew: {
                    InventoryImportMotion.animate {
                        model.resetMatch(entry: entry.id)
                    }
                }
            )
        }
    }

    // MARK: - Sections

    /// At the top, where a disabled confirm button is explained, not under rows
    /// the user may have scrolled past.
    @ViewBuilder
    private var noticeSection: some View {
        let messages = [model.errorMessage, model.confirmBlocker].compactMap { $0 }
        if !messages.isEmpty {
            Section {
                ForEach(Array(messages.enumerated()), id: \.offset) { index, message in
                    HoneyLedgerFieldNote(message, tint: .danger)
                        .padding(.vertical, 4)
                        .ledgerSheetRow(position: .position(index: index, count: messages.count))
                }
            }
        }
    }

    @ViewBuilder
    private var matchedSection: some View {
        let entries = model.matchedEntries
        if !entries.isEmpty {
            Section {
                entryRows(entries)
            } header: {
                HoneyLedgerSectionLabel("In Your Inventory")
            } footer: {
                HoneyLedgerFooter(
                    "A match only adds a purchase. It never changes the ingredient, "
                    + "and a hidden ingredient stays hidden."
                )
            }
        }
    }

    @ViewBuilder
    private var newSection: some View {
        let entries = model.newEntries
        if !entries.isEmpty {
            Section {
                entryRows(entries)
            } header: {
                HoneyLedgerSectionLabel("Will Be Added")
            } footer: {
                HoneyLedgerFooter(
                    "These aren’t in your inventory yet. One from the library arrives with its "
                    + "saponification values and fatty acids."
                )
            }
        }
    }

    @ViewBuilder
    private var blockedSection: some View {
        let blocked = model.blockedLines
        if !blocked.isEmpty {
            Section {
                ForEach(Array(blocked.enumerated()), id: \.element.id) { index, item in
                    InventoryImportBlockedRow(model: model, item: item) { matchingEntry = $0 }
                        .ledgerSheetRow(position: .position(index: index, count: blocked.count))
                }
            } header: {
                HoneyLedgerSectionLabel("Can’t Import")
            } footer: {
                HoneyLedgerFooter(
                    "These rows are left out. Fix them in the source and import again. "
                    + "Where a unit can’t be converted, you can enter the amount by hand."
                )
            }
        }
    }

    private func entryRows(_ entries: [InventoryImportEntry]) -> some View {
        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
            InventoryImportEntryRow(model: model, entry: entry, categoryNames: categories.map(\.name)) {
                matchingEntry = entry
            }
            .ledgerSheetRow(position: .position(index: index, count: entries.count))
        }
    }

    // MARK: - Helpers

    private func currentMatch(of entry: InventoryImportEntry) -> InventoryImportMatch? {
        let latest = model.plan.entries.first { $0.id == entry.id } ?? entry
        if case .existing(let match) = latest.resolution { return match }
        return nil
    }

    private var confirmTitle: String {
        switch model.importableCount {
        case 0: String(localized: "Import")
        case 1: String(localized: "Import 1 row")
        case let count: String(localized: "Import \(count) rows")
        }
    }
}

#if DEBUG
@MainActor
private struct InventoryImportPreviewData {
    let container: ModelContainer
    var plan: InventoryImportPlan

    /// Olive Oil takes two rows, the second turned off, Shea Butter is hidden,
    /// Coconut Oil comes from the library, Palm Oil was pointed at Palm Kernel
    /// Oil, and Soap Box can't take a weight.
    static func mixed() -> InventoryImportPreviewData {
        make(rows: [
            InventoryImportRow(
                sourceLine: 2, name: "Olive Oil", unit: .grams, quantity: 500,
                totalPrice: 8.5, supplier: "Acme Oils", purchaseDate: .now
            ),
            InventoryImportRow(sourceLine: 3, name: "Olive Oil", unit: .kilograms, quantity: 2, totalPrice: 15),
            InventoryImportRow(sourceLine: 4, name: "Shea Butter", unit: .grams, quantity: 200),
            InventoryImportRow(sourceLine: 5, name: "Coconut Oil", categoryName: "Oils", unit: .kilograms, quantity: 1, totalPrice: 6),
            InventoryImportRow(sourceLine: 6, name: "Zzyzx Butter", categoryName: "Butters", unit: .grams, quantity: 300),
            InventoryImportRow(sourceLine: 7, name: "Soap Box", unit: .grams, quantity: 5),
            InventoryImportRow(sourceLine: 8, name: "", quantity: 1),
            InventoryImportRow(sourceLine: 9, name: "Olive Oil", quantity: -1),
            InventoryImportRow(sourceLine: 10, name: "Castor Oil", unit: .milliliters, quantity: 500, totalPrice: 9),
            InventoryImportRow(sourceLine: 11, name: "Palm Oil", unit: .grams, quantity: 300)
        ]) { plan, inventory in
            if let line = plan.entries.flatMap(\.lines).first(where: { $0.row.sourceLine == 3 }) {
                plan.setIncluded(false, forLine: line.id)
            }
            if let entry = plan.entries.first(where: { $0.name == "Palm Oil" }),
               let kernel = inventory.first(where: { $0.name == "Palm Kernel Oil" }) {
                plan.rematch(entry: entry.id, to: kernel)
            }
        }
    }

    static func allBlocked() -> InventoryImportPreviewData {
        make(rows: [
            InventoryImportRow(sourceLine: 2, name: "Soap Box", unit: .grams, quantity: 5),
            InventoryImportRow(sourceLine: 3, name: "", quantity: 1)
        ])
    }

    static func everythingOff() -> InventoryImportPreviewData {
        var data = mixed()
        for entry in data.plan.entries {
            data.plan.setIncluded(false, forEntry: entry.id)
        }
        return data
    }

    func screen() -> some View {
        NavigationStack {
            InventoryImportReviewView(model: InventoryImportReviewViewModel(plan: plan), onFinished: { _ in })
                .ledgerBackground()
        }
        .modelContainer(container)
    }

    private static func make(
        rows: [InventoryImportRow],
        adjust: (inout InventoryImportPlan, [Ingredient]) -> Void = { _, _ in }
    ) -> InventoryImportPreviewData {
        let schema = ModelContainerFactory.schema
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        guard let container = try? ModelContainer(for: schema, configurations: [configuration]) else {
            fatalError("The preview container couldn't be made.")
        }
        let context = container.mainContext
        let inventory = [
            ("Olive Oil", IngredientUnit.grams, false),
            ("Shea Butter", .grams, true),
            ("Castor Oil", .grams, false),
            ("Soap Box", .units, false),
            ("Palm Oil", .grams, false),
            ("Palm Kernel Oil", .grams, false)
        ].map { name, unit, isHidden in
            let ingredient = Ingredient(name: name, unit: unit.rawValue)
            ingredient.isHidden = isHidden
            context.insert(ingredient)
            return ingredient
        }
        var plan = InventoryImportMatcher.plan(for: rows, inventory: inventory)
        adjust(&plan, inventory)
        return InventoryImportPreviewData(container: container, plan: plan)
    }
}

#Preview("Mixed") { InventoryImportPreviewData.mixed().screen() }

#Preview("All blocked") { InventoryImportPreviewData.allBlocked().screen() }

#Preview("Everything off") { InventoryImportPreviewData.everythingOff().screen() }
#endif
