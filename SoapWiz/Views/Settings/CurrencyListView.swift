import SwiftUI

/// Every common currency, one tap to choose. Picking one goes back to Settings.
struct CurrencyListView: View {
    @Environment(\.currencyCode) private var currencyCode
    @Environment(\.dismiss) private var dismiss
    let settings: AppSettings

    @State private var searchText = ""

    var body: some View {
        let choices = CurrencyChoice.filter(
            CurrencyChoice.all(including: currencyCode),
            matching: searchText
        )
        Group {
            if choices.isEmpty {
                HoneyLedgerEmptyState(
                    "No Matches",
                    systemImage: "magnifyingglass",
                    description: "No currency matches your search."
                )
            } else {
                List {
                    // The selected currency leads, so it never sits far down a
                    // list of ~150; while searching, only the results show.
                    if !isSearching, let current = choices.first(where: { $0.code == currencyCode }) {
                        Section {
                            row(current)
                                .ledgerSheetRow(position: .only)
                        } header: {
                            ornament
                        }
                        Section {
                            choiceRows(choices)
                        } header: {
                            HoneyLedgerSectionLabel("All currencies")
                        }
                    } else {
                        Section {
                            choiceRows(choices)
                        } header: {
                            ornament
                        }
                    }
                }
            }
        }
        .readableWidth()
        .navigationTitle("Currency")
        .navigationBarTitleDisplayMode(.inline)
        .honeyLedgerInlineTitle("Currency")
        .ledgerBackground()
        .searchable(text: $searchText, prompt: "Search currencies")
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The List's first-header inset leaves the ornament lower than centred;
    /// it clamps this negative padding to about 7pt up.
    private var ornament: some View {
        HoneyLedgerOrnament()
            .padding(.top, -10)
    }

    private func choiceRows(_ choices: [CurrencyChoice]) -> some View {
        ForEach(Array(choices.enumerated()), id: \.element.id) { index, choice in
            row(choice)
                .ledgerSheetRow(position: .position(index: index, count: choices.count))
        }
    }

    private func row(_ choice: CurrencyChoice) -> some View {
        let isSelected = choice.code == currencyCode
        return Button {
            settings.currencyCode = choice.code
            dismiss()
        } label: {
            HStack {
                Text(choice.label)
                    .foregroundStyle(Color.ink)
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.amberText)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
