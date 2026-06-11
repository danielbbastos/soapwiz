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
                    ContentUnavailableView(
                        "No Locations",
                        systemImage: "archivebox",
                        description: Text("Tap + to create your first storage location.")
                    )
                } else {
                    List {
                        ForEach(locations) { location in
                            Button {
                                model.locationToEdit = location
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(location.name)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        Text("\(location.purchases.count)")
                                            .foregroundStyle(.secondary)
                                            .font(.subheadline)
                                    }
                                    if !location.locationDescription.isEmpty {
                                        Text(location.locationDescription)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .onDelete { model.delete(at: $0, in: locations, context: modelContext) }
                        .listRowBackground(Color.cardBackground)
                    }
                }
            }
            .navigationTitle("Storage Locations")
            .navigationBarTitleDisplayMode(.inline)
            .warmNavigationTitle("Storage Locations")
            .warmBackground()

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
