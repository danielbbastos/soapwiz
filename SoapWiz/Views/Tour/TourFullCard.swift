import SwiftUI

/// The tour's welcome and closing cards. The view draws its own dim, full
/// screen and over everything beneath, so a caller only overlays it on the
/// root view; nothing underneath can be tapped while it is up.
struct TourFullCard: View {
    enum Kind {
        case welcome
        case finish
    }

    let kind: Kind
    let onPrimary: () -> Void
    let onSkip: () -> Void

    var body: some View {
        GeometryReader { proxy in
            let width = TourCardPlacement.cardWidth(for: proxy.size.width)
            ZStack {
                Color.tourDim
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {}
                    .accessibilityHidden(true)
                // The card as it is when it fits; when it doesn't, the text
                // scrolls and the buttons stay pinned, and the card takes the
                // room it is given.
                ViewThatFits(in: .vertical) {
                    card(scrollsText: false)
                    card(scrollsText: true)
                }
                .frame(width: width)
                .frame(maxHeight: max(0, proxy.size.height - 2 * TourCardPlacement.margin))
            }
        }
        .accessibilityAddTraits(.isModal)
    }

    private func card(scrollsText: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if scrollsText {
                ScrollView {
                    text
                }
                .scrollBounceBehavior(.basedOnSize)
            } else {
                text
            }
            buttons
        }
        .foregroundStyle(Color.ink)
        .padding(.top, 28)
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .background {
            TourCardSurface(cornerRadius: 28)
        }
        .accessibilityElement(children: .contain)
    }

    private var text: some View {
        VStack(alignment: .leading, spacing: 0) {
            HoneyLedgerDiamondRule()
                .accessibilityHidden(true)
            switch kind {
            case .welcome:
                welcomeText
            case .finish:
                finishText
            }
        }
    }

    private var buttons: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch kind {
            case .welcome:
                welcomeButtons
            case .finish:
                finishButtons
            }
        }
    }

    private var welcomeText: some View {
        VStack(alignment: .leading, spacing: 0) {
            title("Welcome to SoapWiz")
            Text(
                "A ledger for your soap making: what you have, what you make, and what it costs. "
                    + "Here’s the usual flow, on a sample recipe."
            )
                .font(.callout)
                .foregroundStyle(Color.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 14) {
                numberedRow(1, name: "Inventory.", detail: " Your ingredients, and what you paid for them.")
                numberedRow(2, name: "Recipes.", detail: " Lye, qualities and cost, worked out as you type.")
                numberedRow(3, name: "Batches.", detail: " Stock goes down, and History keeps the record.")
            }
            .padding(.top, 20)
            Text("Nothing in the tour is saved to your data.")
                .font(.footnote)
                .foregroundStyle(Color.inkSoft)
                .padding(.top, 18)
        }
    }

    private var welcomeButtons: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button("Show me around", action: onPrimary)
                .buttonStyle(.honeyLedgerPrimary)
                .padding(.top, 20)
            Button("Skip tour", action: onSkip)
                .buttonStyle(.plain)
                .font(.body)
                .foregroundStyle(Color.inkSoft)
                .frame(maxWidth: .infinity, minHeight: 44)
                .padding(.top, 6)
        }
    }

    private var finishText: some View {
        VStack(alignment: .leading, spacing: 0) {
            title("Over to you")
            Text("Your ingredient library is ready. Record what you have on hand, then write your first recipe.")
                .font(.callout)
                .foregroundStyle(Color.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            Text("Replay this tour any time from Settings › About.")
                .font(.footnote)
                .foregroundStyle(Color.inkSoft)
                .padding(.top, 12)
        }
    }

    private var finishButtons: some View {
        Button("Start using SoapWiz", action: onPrimary)
            .buttonStyle(.honeyLedgerPrimary)
            .padding(.top, 28)
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.system(.title, design: .serif, weight: .semibold))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 16)
            .padding(.bottom, 8)
            .accessibilityAddTraits(.isHeader)
    }

    private func numberedRow(_ number: Int, name: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.amberText)
                .frame(width: 28, height: 28)
                .background(Color.honey, in: Circle())
                .accessibilityHidden(true)
            Text("\(Text(name).bold().foregroundStyle(Color.ink))\(Text(detail).foregroundStyle(Color.inkSoft))")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Previews

#Preview("Welcome light") {
    Color.clear.ledgerBackground()
        .overlay { TourFullCard(kind: .welcome, onPrimary: {}, onSkip: {}) }
        .preferredColorScheme(.light)
}

#Preview("Welcome dark") {
    Color.clear.ledgerBackground()
        .overlay { TourFullCard(kind: .welcome, onPrimary: {}, onSkip: {}) }
        .preferredColorScheme(.dark)
}

#Preview("Finish light") {
    Color.clear.ledgerBackground()
        .overlay { TourFullCard(kind: .finish, onPrimary: {}, onSkip: {}) }
        .preferredColorScheme(.light)
}

#Preview("Finish dark") {
    Color.clear.ledgerBackground()
        .overlay { TourFullCard(kind: .finish, onPrimary: {}, onSkip: {}) }
        .preferredColorScheme(.dark)
}
