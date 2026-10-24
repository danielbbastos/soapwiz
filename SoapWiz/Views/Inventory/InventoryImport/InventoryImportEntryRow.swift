import SwiftUI

/// One ingredient of an inventory import and the rows going onto it. At
/// accessibility text sizes the stamps and the actions move under the name
/// rather than squeezing beside it.
///
/// Rows the import can't take aren't listed here; "Can't Import" lists them.
/// Several buttons share this list row, so the toggles set `.plain` and keep
/// the row from lighting as one.
struct InventoryImportEntryRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.currencyCode) private var currencyCode

    let model: InventoryImportReviewViewModel
    let entry: InventoryImportEntry
    let categoryNames: [String]
    var onChange: () -> Void

    private var lines: [InventoryImportLine] {
        entry.lines.filter(\.isImportable)
    }

    private var headerLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if lines.count > 1 {
                entryToggle
            }
            ForEach(lines) { line in
                lineToggle(line)
            }
            actions
        }
        .padding(.vertical, 4)
    }

    // MARK: - Header

    private var header: some View {
        headerLayout {
            Text(entry.name)
                .foregroundStyle(Color.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            stamp
        }
    }

    @ViewBuilder
    private var stamp: some View {
        if entry.isHidden {
            StatusStamp(word: "Hidden", tone: .neutral)
        } else if case .newIngredient(let new) = entry.resolution {
            if new.libraryEntry != nil {
                StatusStamp(word: "Library", tone: .amber)
            } else {
                StatusStamp(word: "New", tone: .success)
            }
        }
    }

    // MARK: - Toggles

    private var entryToggle: some View {
        let isIncluded = model.isIncluded(entry)
        return Button {
            model.setIncluded(!isIncluded, entry: entry.id)
        } label: {
            HoneyLedgerPickerRow(state: isIncluded ? .selected : .unselected) {
                Text("All \(lines.count) rows")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.ink)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isIncluded ? .isSelected : [])
    }

    private func lineToggle(_ line: InventoryImportLine) -> some View {
        Button {
            model.setIncluded(!line.isIncluded, line: line.id)
        } label: {
            HoneyLedgerPickerRow(state: line.isIncluded ? .selected : .unselected) {
                lineDetails(line)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(line.isIncluded ? .isSelected : [])
        .padding(.leading, lines.count > 1 ? 20 : 0)
    }

    private func lineDetails(_ line: InventoryImportLine) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            quantityText(line)
                .foregroundStyle(line.isIncluded ? Color.ink : Color.inkFaint)
            if let detail = detailText(line.row) {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Color.inkSoft)
            }
            ForEach(Array(warnings(of: line).enumerated()), id: \.offset) { _, issue in
                HoneyLedgerFieldNote(issue.reason, tint: .warning)
            }
        }
    }

    private func quantityText(_ line: InventoryImportLine) -> Text {
        guard let quantity = line.quantity else {
            return Text("No quantity")
        }
        return Text.honeyLedgerFigure(
            quantity.formatted(.number.precision(.fractionLength(0...3))),
            unit: entry.unit,
            numberColor: line.isIncluded ? .ink : .inkFaint
        )
    }

    private func warnings(of line: InventoryImportLine) -> [InventoryImportIssue] {
        line.issues.filter { $0.severity == .warning }
    }

    private func detailText(_ row: InventoryImportRow) -> String? {
        var parts: [String] = []
        if let price = row.totalPrice {
            parts.append(price.formatted(.currency(code: currencyCode)))
        }
        if let supplier = row.supplier?.trimmingCharacters(in: .whitespacesAndNewlines), !supplier.isEmpty {
            parts.append(supplier)
        }
        if let date = row.purchaseDate {
            parts.append(date.formatted(date: .abbreviated, time: .omitted))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Actions

    private var actions: some View {
        headerLayout {
            InventoryImportMatchActions(model: model, entry: entry, onChange: onChange)
            if entry.isNew {
                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: 0)
                }
                categoryMenu
            }
        }
    }

    private var categoryMenu: some View {
        let selection = Binding<String?>(
            get: { selectedOption },
            set: { model.setCategory($0, entry: entry.id) }
        )
        return Menu {
            Picker("Category", selection: selection) {
                ForEach(options, id: \.self) { name in
                    Text(name).tag(Optional(name))
                }
                Text(IngredientCategory.Name.others).tag(String?.none)
            }
        } label: {
            HStack(spacing: 4) {
                Text(selectedOption ?? IngredientCategory.Name.others)
                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Color.amberText)
        }
        .menuStyle(.automatic)
        .buttonStyle(.borderless)
        .accessibilityLabel(Text("Category"))
        .accessibilityValue(Text(selectedOption ?? IngredientCategory.Name.others))
    }

    private var options: [String] {
        model.categoryOptions(for: entry, existing: categoryNames)
    }

    /// The option matching the entry's category, which may differ from it in
    /// case; the picker only marks an exact match.
    private var selectedOption: String? {
        guard let current = model.categoryName(of: entry) else { return nil }
        return options.first { $0.lookupKey == current.lookupKey } ?? current
    }
}
