import SwiftUI

/// One ingredient of an inventory import and the rows going onto it: its name
/// with Change, what the file says on each row with a check at the trailing
/// edge, and for a new ingredient its category. At accessibility text sizes
/// the actions stack rather than squeezing together.
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

    private var categoryLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            InventoryImportNameLine(model: model, name: entry.name, entry: entry, onChange: onChange) {
                stamp
            }
            if lines.count > 1 {
                entryToggle
                    .padding(.top, 4)
            }
            ForEach(lines) { line in
                VStack(alignment: .leading, spacing: 0) {
                    lineToggle(line)
                    if line.enteredQuantity != nil {
                        InventoryImportRowButton("Undo amount", color: .inkSoft, growsUp: false) {
                            InventoryImportMotion.animate { model.clearEnteredAmount(line: line.id) }
                        }
                        .importTransition(.reveal)
                    }
                }
                .padding(.top, lines.count == 1 ? 4 : 0)
            }
            if entry.isNew {
                categoryRow
                    .importTransition(.reveal)
            }
        }
        .padding(.bottom, 2)
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
            InventoryImportMotion.animate { model.setIncluded(!isIncluded, entry: entry.id) }
        } label: {
            HoneyLedgerPickerRow(state: isIncluded ? .selected : .unselected, glyphEdge: .trailing) {
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
            InventoryImportMotion.animate { model.setIncluded(!line.isIncluded, line: line.id) }
        } label: {
            HoneyLedgerPickerRow(state: line.isIncluded ? .selected : .unselected, glyphEdge: .trailing) {
                lineDetails(line)
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(line.isIncluded ? .isSelected : [])
    }

    private func lineDetails(_ line: InventoryImportLine) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            quantityText(line)
                .foregroundStyle(line.isIncluded ? Color.ink : Color.inkFaint)
            ForEach(Array(warnings(of: line).enumerated()), id: \.offset) { _, issue in
                HoneyLedgerFieldNote(issue.reason, tint: .warning)
            }
            if let detail = detailText(line.row) {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(Color.inkSoft)
            }
        }
    }

    private func quantityText(_ line: InventoryImportLine) -> Text {
        guard let quantity = line.quantity else {
            return Text("No quantity")
        }
        return Text.honeyLedgerFigure(
            quantity.formatted(.number.precision(.fractionLength(0...2))),
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

    // MARK: - Category

    private var categoryRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(Color.rule)
                .frame(height: 1)
                .accessibilityHidden(true)
            categoryMenu
        }
    }

    private var categoryMenu: some View {
        let selection = Binding<String?>(
            get: { selectedOption },
            set: { name in InventoryImportMotion.animate { model.setCategory(name, entry: entry.id) } }
        )
        return Menu {
            Picker("Category", selection: selection) {
                ForEach(options, id: \.self) { name in
                    Text(name).tag(Optional(name))
                }
                Text(IngredientCategory.Name.others).tag(String?.none)
            }
        } label: {
            categoryLayout {
                Text("Category")
                    .foregroundStyle(Color.ink)
                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer(minLength: 0)
                }
                HStack(spacing: 4) {
                    Text(selectedOption ?? IngredientCategory.Name.others)
                    Image(systemName: "chevron.up.chevron.down")
                        .imageScale(.small)
                        .accessibilityHidden(true)
                }
                .foregroundStyle(Color.amberText)
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
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
