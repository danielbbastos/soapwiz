import SwiftUI

/// One block of Home: a section label over a ledger sheet holding the card's
/// rows.
struct HomeCard<Content: View>: View {
    let title: String
    let tourAnchor: TourAnchorID?
    let content: Content

    init(_ title: String, tourAnchor: TourAnchorID? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.tourAnchor = tourAnchor
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HoneyLedgerSectionLabel(title)
            VStack(spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .ledgerSheet()
        }
        .tourAnchor(tourAnchor, cornerRadius: 30, outset: CGSize(width: 8, height: 8))
        .preference(key: HomeCardShownKey.self, value: true)
    }
}

struct HomeCardShownKey: PreferenceKey {
    static let defaultValue: Bool? = nil

    static func reduce(value: inout Bool?, nextValue: () -> Bool?) {
        guard let next = nextValue() else { return }
        value = (value ?? false) || next
    }
}

#Preview {
    HomeCard("Curing") {
        Text(verbatim: "Row")
            .padding(16)
    }
    .padding()
}
