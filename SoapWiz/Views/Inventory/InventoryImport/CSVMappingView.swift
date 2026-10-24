import SwiftUI

/// Where the user says which spreadsheet column holds which inventory field.
///
/// The columns start out as the file's header row names them. Each shows a few
/// of its values, so a column without a useful header can still be told apart.
/// The flow that presents this screen owns the button that moves on.
struct CSVMappingView: View {
    @Bindable var model: CSVMappingViewModel

    var body: some View {
        Form {
            Section {
                Toggle("First row is a header", isOn: $model.hasHeaderRow)
                    .foregroundStyle(Color.ink)
                    .tint(Color.amber)
                    .ledgerSheetRow(position: .only)
            }
            Section {
                let columns = model.columns
                ForEach(Array(columns.enumerated()), id: \.element.id) { index, column in
                    columnRow(column)
                        .ledgerSheetRow(position: .position(index: index, count: columns.count))
                }
            } header: {
                HoneyLedgerSectionLabel("Columns")
            } footer: {
                footer
            }
        }
        .environment(\.defaultMinListRowHeight, 48)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HoneyLedgerFooter(rowCountText)
            if let problem {
                HoneyLedgerFieldNote(problem, tint: .danger)
            }
        }
    }

    private var rowCountText: String {
        model.dataRowCount == 1
            ? String(localized: "1 row to import")
            : String(localized: "\(model.dataRowCount) rows to import")
    }

    private var problem: String? {
        if model.canContinue { return nil }
        return model.dataRowCount == 0
            ? String(localized: "This file has no rows to import.")
            : String(localized: "Choose the column that holds the ingredient names.")
    }

    private func columnRow(_ column: CSVMappingColumn) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(column.title)
                    .font(.headline)
                    .foregroundStyle(Color.ink)
                Spacer()
                Picker(column.title, selection: fieldBinding(for: column.index)) {
                    Text("None").tag(InventoryImportField?.none)
                    ForEach(InventoryImportField.allCases, id: \.self) { field in
                        Text(field.label).tag(InventoryImportField?.some(field))
                    }
                }
                .labelsHidden()
                .tint(Color.amberText)
            }
            Text(column.samples.isEmpty ? String(localized: "No values") : column.samples.joined(separator: " · "))
                .font(.footnote)
                .foregroundStyle(Color.inkSoft)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }

    private func fieldBinding(for column: Int) -> Binding<InventoryImportField?> {
        Binding(
            get: { model.field(for: column) },
            set: { model.setField($0, for: column) }
        )
    }
}

#if DEBUG
#Preview("Header detected") {
    NavigationStack {
        CSVMappingView(model: CSVMappingViewModel(rows: [
            ["Ingredient", "Qty", "Price", "Notes"],
            ["Olive Oil", "500 g", "12.50", "organic"],
            ["Shea Butter", "200 g", "8", ""]
        ]))
        .ledgerBackground()
    }
}

#Preview("No header") {
    NavigationStack {
        CSVMappingView(model: CSVMappingViewModel(rows: [
            ["Olive Oil", "500 g"],
            ["Shea Butter", "200 g"]
        ]))
        .ledgerBackground()
    }
}
#endif
