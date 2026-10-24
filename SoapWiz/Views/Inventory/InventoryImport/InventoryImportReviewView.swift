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
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(confirmTitle) {
                    model.confirm(in: modelContext)
                    if let result = model.result {
                        onFinished(result)
                    }
                }
                .disabled(!model.canConfirm)
            }
        }
        .sheet(item: $matchingEntry) { entry in
            InventoryImportMatchPickerView(
                current: currentMatch(of: entry),
                canCreateNew: model.canResetToNew(entry),
                onSelect: { model.rematch(entry: entry.id, to: $0) },
                onCreateNew: { model.resetMatch(entry: entry.id) }
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
                    blockedRow(item)
                        .ledgerSheetRow(position: .position(index: index, count: blocked.count))
                }
            } header: {
                HoneyLedgerSectionLabel("Can’t Import")
            } footer: {
                HoneyLedgerFooter("These rows are left out. Fix them in the source and import again.")
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

    private func blockedRow(_ item: InventoryImportBlockedLine) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.entryName ?? String(localized: "No name"))
                .foregroundStyle(item.entryName == nil ? Color.inkSoft : Color.ink)
            if let sourceLine = item.line.row.sourceLine {
                Text("Line \(sourceLine)")
                    .font(.footnote)
                    .foregroundStyle(Color.inkSoft)
            }
            ForEach(Array(item.line.issues.filter(\.isBlocking).enumerated()), id: \.offset) { _, issue in
                HoneyLedgerFieldNote(issue.reason, tint: .danger)
            }
            if item.offersMatchActions, let entry = item.entry {
                InventoryImportMatchActions(model: model, entry: entry) {
                    matchingEntry = entry
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
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
        case 1: String(localized: "Import 1 Row")
        case let count: String(localized: "Import \(count) Rows")
        }
    }
}

#if DEBUG
@MainActor
private struct InventoryImportPreviewData {
    let container: ModelContainer
    var plan: InventoryImportPlan

    /// Olive Oil takes two rows, Shea Butter is hidden, Coconut Oil comes from
    /// the library, and Soap Box can't take a weight.
    static func mixed() -> InventoryImportPreviewData {
        make(rows: [
            InventoryImportRow(
                sourceLine: 2, name: "Olive Oil", unit: .grams, quantity: 500,
                totalPrice: 8.5, supplier: "Acme Oils", purchaseDate: .now
            ),
            InventoryImportRow(sourceLine: 3, name: "Olive Oil", unit: .kilograms, quantity: 2, totalPrice: 15),
            InventoryImportRow(sourceLine: 4, name: "Shea Butter", unit: .grams, quantity: 200),
            InventoryImportRow(sourceLine: 5, name: "Coconut Oil", unit: .kilograms, quantity: 1, totalPrice: 6),
            InventoryImportRow(sourceLine: 6, name: "Zzyzx Butter", categoryName: "Butters", unit: .grams, quantity: 300),
            InventoryImportRow(sourceLine: 7, name: "Soap Box", unit: .grams, quantity: 5),
            InventoryImportRow(sourceLine: 8, name: "", quantity: 1),
            InventoryImportRow(sourceLine: 9, name: "Olive Oil", quantity: -1)
        ])
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
            InventoryImportReviewView(model: InventoryImportReviewViewModel(plan: plan)) { _ in }
                .ledgerBackground()
        }
        .modelContainer(container)
    }

    private static func make(rows: [InventoryImportRow]) -> InventoryImportPreviewData {
        let schema = ModelContainerFactory.schema
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        guard let container = try? ModelContainer(for: schema, configurations: [configuration]) else {
            fatalError("The preview container couldn't be made.")
        }
        let context = container.mainContext
        let inventory = [
            ("Olive Oil", IngredientUnit.grams, false),
            ("Shea Butter", .grams, true),
            ("Soap Box", .units, false)
        ].map { name, unit, isHidden in
            let ingredient = Ingredient(name: name, unit: unit.rawValue)
            ingredient.isHidden = isHidden
            context.insert(ingredient)
            return ingredient
        }
        return InventoryImportPreviewData(
            container: container,
            plan: InventoryImportMatcher.plan(for: rows, inventory: inventory)
        )
    }
}

#Preview("Mixed") { InventoryImportPreviewData.mixed().screen() }

#Preview("All blocked") { InventoryImportPreviewData.allBlocked().screen() }

#Preview("Everything off") { InventoryImportPreviewData.everythingOff().screen() }
#endif
