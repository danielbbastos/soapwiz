import SwiftUI

/// Change, and Undo Change once the user has re-pointed an entry. Shared by
/// the entry rows and by "Can't Import", where a rematch that blocked every
/// row must stay undoable.
struct InventoryImportMatchActions: View {
    let model: InventoryImportReviewViewModel
    let entry: InventoryImportEntry
    var onChange: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            button(entry.isNew ? "Match to Existing" : "Change", color: .amberText, action: onChange)
            if model.canResetToNew(entry) || model.canResetMatch(entry) {
                button("Undo Change", color: .inkSoft) {
                    model.resetMatch(entry: entry.id)
                }
            }
        }
    }

    private func button(_ title: LocalizedStringKey, color: Color, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(color)
            .buttonStyle(.borderless)
    }
}
