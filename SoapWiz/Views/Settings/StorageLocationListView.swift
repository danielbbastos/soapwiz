import SwiftUI
import SwiftData

struct StorageLocationListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.editMode) private var editMode
    @Query(sort: \StorageLocation.name) private var locations: [StorageLocation]

    @State private var model = StorageLocationListViewModel()

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if locations.isEmpty {
                    HoneyLedgerEmptyState(
                        "No Locations",
                        systemImage: "archivebox",
                        description: "Tap + to create your first storage location."
                    )
                } else {
                    List {
                        Section {
                            ForEach(Array(locations.enumerated()), id: \.element.id) { index, location in
                                Button {
                                    model.locationToEdit = location
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack {
                                            Text(location.name)
                                                .foregroundStyle(Color.ink)
                                            Spacer()
                                            Text("\(location.purchases.count)")
                                                .foregroundStyle(Color.inkSoft)
                                                .font(.subheadline)
                                                .monospacedDigit()
                                        }
                                        if !location.locationDescription.isEmpty {
                                            Text(location.locationDescription)
                                                .font(.caption)
                                                .foregroundStyle(Color.inkSoft)
                                        }
                                    }
                                }
                                .ledgerSheetRow(position: .position(index: index, count: locations.count))
                            }
                            .onDelete { model.delete(at: $0, in: locations, context: modelContext) }
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
            .navigationTitle("Storage Locations")
            .navigationBarTitleDisplayMode(.inline)
            .honeyLedgerInlineTitle("Storage Locations")
            .ledgerBackground()

            if editMode?.wrappedValue != .active {
                FloatingActionButton { model.showingAddLocation = true }
            }
        }
        .sheet(isPresented: $model.showingAddLocation) {
            StorageLocationFormView()
        }
        .sheet(item: $model.locationToEdit) { location in
            StorageLocationFormView(location: location)
        }
        .alert(
            "Cannot Delete Location",
            isPresented: Binding(
                get: { model.deleteBlockedLocation != nil },
                set: { if !$0 { model.deleteBlockedLocation = nil } }
            ),
            presenting: model.deleteBlockedLocation
        ) { _ in
            Button("OK", role: .cancel) { model.deleteBlockedLocation = nil }
        } message: { location in
            let count = location.purchases.count
            Text(
                "\"\(location.name)\" is assigned to \(count) purchase\(count == 1 ? "" : "s"). " +
                "Remove the location from those purchases first."
            )
        }
    }
}
