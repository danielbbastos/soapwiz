import SwiftUI

/// A whole-row action on a ledger sheet: `amberText` semibold when it is the
/// step forward, `ink` when it is the way back, and `inkFaint` while disabled.
/// It sets no button style, so the row's `ledgerSheetRow` lights it while
/// pressed.
struct HoneyLedgerActionRow: View {
    @Environment(\.isEnabled) private var isEnabled

    let title: String
    let systemImage: String?
    let isPrimary: Bool
    let action: () -> Void

    init(_ title: String, systemImage: String? = nil, isPrimary: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isPrimary = isPrimary
        self.action = action
    }

    /// What a plain button style dims a disabled label to, which this row drew
    /// before it took the row's own style.
    private static let disabledOpacity = 0.5

    private var color: Color {
        guard isEnabled else { return .inkFaint }
        return isPrimary ? .amberText : .ink
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .accessibilityHidden(true)
                }
                Text(title)
            }
            .fontWeight(isPrimary ? .semibold : .regular)
            .foregroundStyle(color)
            .opacity(isEnabled ? 1 : Self.disabledOpacity)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
    }
}
