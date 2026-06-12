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
                    ContentUnavailableView(
                        "No Providers",
                        systemImage: "shippingbox",
                        description: Text("Tap + to add your first provider.")
                    )
                } else {
                    List {
                        ForEach(providers) { provider in
                            Button {
                                model.providerToEdit = provider
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(provider.name)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        Text("\(provider.purchases.count)")
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
                        .onDelete { model.delete(at: $0, in: providers, context: modelContext) }
                        .listRowBackground(Color.cardBackground)
                    }
                }
            }
            .navigationTitle("Providers")
            .navigationBarTitleDisplayMode(.inline)
            .warmNavigationTitle("Providers")
            .warmBackground()

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
