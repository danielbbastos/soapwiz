import SwiftUI

/// A row of "Can't Import": its name with the match actions, its reasons, and,
/// for a row blocked only by its unit, "Enter amount in <unit>", which the
/// amount field replaces while it is open.
struct InventoryImportBlockedRow: View {
    let model: InventoryImportReviewViewModel
    let item: InventoryImportBlockedLine
    var onChange: (InventoryImportEntry) -> Void

    @State private var isEntering = false

    private var amountEntry: InventoryImportEntry? {
        item.line.canEnterQuantity ? item.entry : nil
    }

    private var actionEntry: InventoryImportEntry? {
        item.offersMatchActions ? item.entry : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            InventoryImportNameLine(
                model: model,
                name: item.entryName ?? String(localized: "No name"),
                nameColor: item.entryName == nil ? .inkSoft : .ink,
                entry: actionEntry
            ) {
                if let entry = actionEntry {
                    onChange(entry)
                }
            }
            if let sourceLine = item.line.row.sourceLine {
                Text("Line \(sourceLine)")
                    .font(.footnote)
                    .foregroundStyle(Color.inkSoft)
            }
            ForEach(Array(item.line.issues.filter(\.isBlocking).enumerated()), id: \.offset) { _, issue in
                HoneyLedgerFieldNote(issue.reason, tint: .danger)
            }
            if let entry = amountEntry {
                if isEntering {
                    InventoryImportEnterAmountView(model: model, line: item.line, unit: entry.unit) {
                        setEntering(false)
                    }
                    .padding(.top, 12)
                    .importTransition(.field)
                } else {
                    InventoryImportRowButton("Enter amount in \(entry.unit)") { setEntering(true) }
                        .padding(.top, 4)
                        .transition(.opacity)
                }
            }
        }
        .padding(.bottom, 2)
    }

    private func setEntering(_ entering: Bool) {
        InventoryImportMotion.animate {
            isEntering = entering
        }
    }
}
