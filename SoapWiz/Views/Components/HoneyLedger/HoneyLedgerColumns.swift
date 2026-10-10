import SwiftUI

/// Two labelled sheets side by side in one list row, for blocks whose rows are
/// short enough that a full-width sheet each leaves most of the width empty.
/// Falls back to one above the other when they don't fit beside each other, as
/// in a narrow Slide Over window or at the largest text sizes.
///
/// Meant for iPad: on iPhone the two never fit, and the fallback is drawn
/// inside one row rather than as the list's own sections.
struct HoneyLedgerColumns<Leading: View, Trailing: View>: View {
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                leading
                trailing
            }
            VStack(spacing: 24) {
                leading
                trailing
            }
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

/// One column of `HoneyLedgerColumns`: a section label over a sheet of its
/// own. The sheet is left out while `isExpanded` is false, so a collapsible
/// label can fold it away.
struct HoneyLedgerColumn<Label: View, Rows: View>: View {
    /// The inset-grouped list's own row and header margin on iPad, so the
    /// columns line up with the sections above and below them.
    private static var margin: CGFloat { 20 }

    var isExpanded: Bool = true
    @ViewBuilder let label: Label
    @ViewBuilder let rows: Rows

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            label
                .padding(.horizontal, Self.margin)
            if isExpanded {
                VStack(spacing: 10) { rows }
                    .padding(.horizontal, Self.margin)
                    .padding(.vertical, 15)
                    .background(LedgerSheetRowBackground(position: .only, isSelected: false))
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }
}
