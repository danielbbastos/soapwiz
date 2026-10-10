import SwiftUI
import SwiftData

struct ProviderListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.editMode) private var editMode
    @Query(sort: \Provider.name) private var providers: [Provider]

    @State private var model = ProviderListViewModel()

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if providers.isEmpty {
                    HoneyLedgerEmptyState(
                        "No Providers",
                        systemImage: "shippingbox",
                        description: "Tap + to add your first provider."
                    )
                } else {
                    List {
                        Section {
                            ForEach(Array(providers.enumerated()), id: \.element.id) { index, provider in
                                Button {
                                    model.providerToEdit = provider
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack {
                                            Text(provider.name)
                                                .foregroundStyle(Color.ink)
                                            Spacer()
                                            Text("\(provider.purchases.count)")
                                                .foregroundStyle(Color.inkSoft)
                                                .font(.subheadline)
                                                .monospacedDigit()
                                        }
                                        if !provider.website.isEmpty {
                                            Text(provider.website)
                                                .font(.caption)
                                                .foregroundStyle(Color.inkSoft)
                                        }
                                    }
                                }
                                .ledgerSheetRow(position: .position(index: index, count: providers.count))
                            }
                            .onDelete { model.delete(at: $0, in: providers, context: modelContext) }
                        } header: {
                            // The List's first-header inset leaves the ornament lower than
                            // centred; it clamps this negative padding to about 7pt up.
                            HoneyLedgerOrnament()
                                .padding(.top, -10)
                        }
                    }
                }
            }
            .readableWidth()
            .navigationTitle("Providers")
            .navigationBarTitleDisplayMode(.inline)
            .honeyLedgerInlineTitle("Providers")
            .ledgerBackground()

            if editMode?.wrappedValue != .active {
                FloatingActionButton { model.showingAddProvider = true }
            }
        }
        .sheet(isPresented: $model.showingAddProvider) {
            ProviderFormView()
        }
        .sheet(item: $model.providerToEdit) { provider in
            ProviderFormView(provider: provider)
        }
        .alert(
            "Cannot Delete Provider",
            isPresented: Binding(
                get: { model.deleteBlockedProvider != nil },
                set: { if !$0 { model.deleteBlockedProvider = nil } }
            ),
            presenting: model.deleteBlockedProvider
        ) { _ in
            Button("OK", role: .cancel) { model.deleteBlockedProvider = nil }
        } message: { provider in
            let count = provider.purchases.count
            Text(
                "\"\(provider.name)\" is assigned to \(count) purchase\(count == 1 ? "" : "s"). " +
                "Remove the provider from those purchases first."
            )
        }
    }
}
