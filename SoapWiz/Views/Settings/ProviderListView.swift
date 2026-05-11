import SwiftUI
import SwiftData

struct ProviderListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Provider.name) private var providers: [Provider]

    @State private var showingAddProvider = false
    @State private var providerToEdit: Provider?
    @State private var deleteBlockedProvider: Provider?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if providers.isEmpty {
                    ContentUnavailableView(
                        "No Providers",
                        systemImage: "shippingbox",
                        description: Text("Tap + to add your first provider.")
                    )
                } else {
                    List {
                        ForEach(providers) { provider in
                            Button {
                                providerToEdit = provider
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(provider.name)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        Text("\(provider.batches.count)")
                                            .foregroundStyle(.secondary)
                                            .font(.subheadline)
                                    }
                                    if !provider.website.isEmpty {
                                        Text(provider.website)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .onDelete(perform: deleteProviders)
                    }
                }
            }
            .navigationTitle("Providers")
            .navigationBarTitleDisplayMode(.large)

            FloatingActionButton { showingAddProvider = true }
        }
        .sheet(isPresented: $showingAddProvider) {
            ProviderFormView()
        }
        .sheet(item: $providerToEdit) { provider in
            ProviderFormView(provider: provider)
        }
        .alert(
            "Cannot Delete Provider",
            isPresented: Binding(
                get: { deleteBlockedProvider != nil },
                set: { if !$0 { deleteBlockedProvider = nil } }
            ),
            presenting: deleteBlockedProvider
        ) { _ in
            Button("OK", role: .cancel) { deleteBlockedProvider = nil }
        } message: { provider in
            let count = provider.batches.count
            Text(
                "\"\(provider.name)\" is assigned to \(count) batch\(count == 1 ? "" : "es"). " +
                "Remove the provider from those batches first."
            )
        }
    }

    private func deleteProviders(at offsets: IndexSet) {
        for index in offsets {
            let provider = providers[index]
            if provider.batches.isEmpty {
                modelContext.delete(provider)
            } else {
                deleteBlockedProvider = provider
            }
        }
    }
}
