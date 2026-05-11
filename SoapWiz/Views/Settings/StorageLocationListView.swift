import SwiftUI
import SwiftData

struct StorageLocationListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \StorageLocation.name) private var locations: [StorageLocation]

    @State private var showingAddLocation = false
    @State private var locationToEdit: StorageLocation?
    @State private var deleteBlockedLocation: StorageLocation?

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
                                locationToEdit = location
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(location.name)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        Text("\(location.batches.count)")
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
                        .onDelete(perform: deleteLocations)
                    }
                }
            }
            .navigationTitle("Storage Locations")
            .navigationBarTitleDisplayMode(.large)

            FloatingActionButton { showingAddLocation = true }
        }
        .sheet(isPresented: $showingAddLocation) {
            StorageLocationFormView()
        }
        .sheet(item: $locationToEdit) { location in
            StorageLocationFormView(location: location)
        }
        .alert(
            "Cannot Delete Location",
            isPresented: Binding(
                get: { deleteBlockedLocation != nil },
                set: { if !$0 { deleteBlockedLocation = nil } }
            ),
            presenting: deleteBlockedLocation
        ) { _ in
            Button("OK", role: .cancel) { deleteBlockedLocation = nil }
        } message: { location in
            let count = location.batches.count
            Text(
                "\"\(location.name)\" is assigned to \(count) batch\(count == 1 ? "" : "es"). " +
                "Remove the location from those batches first."
            )
        }
    }

    private func deleteLocations(at offsets: IndexSet) {
        for index in offsets {
            let location = locations[index]
            if location.batches.isEmpty {
                modelContext.delete(location)
            } else {
                deleteBlockedLocation = location
            }
        }
    }
}
