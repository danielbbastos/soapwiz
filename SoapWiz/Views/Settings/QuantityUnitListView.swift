import SwiftUI
import SwiftData

struct QuantityUnitListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.editMode) private var editMode
    @Query(sort: \QuantityUnit.name) private var units: [QuantityUnit]

    @State private var model = QuantityUnitListViewModel()

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if units.isEmpty {
                    ContentUnavailableView(
                        "No Units",
                        systemImage: "ruler",
                        description: Text("Tap + to add your first quantity unit.")
                    )
                } else {
                    List {
                        ForEach(units) { unit in
                            Button {
                                model.unitToEdit = unit
                            } label: {
                                HStack {
                                    Text(unit.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text(unit.symbol)
                                        .foregroundStyle(.secondary)
                                        .font(.subheadline)
                                }
                            }
                        }
                        .onDelete { model.delete(at: $0, in: units, context: modelContext) }
                    }
                }
            }
            .navigationTitle("Quantity Units")
            .navigationBarTitleDisplayMode(.large)

            if editMode?.wrappedValue != .active {
                FloatingActionButton { model.showingAddUnit = true }
            }
        }
        .sheet(isPresented: $model.showingAddUnit) {
            QuantityUnitFormView()
        }
        .sheet(item: $model.unitToEdit) { unit in
            QuantityUnitFormView(unit: unit)
        }
        .alert(
            "Cannot Delete Unit",
            isPresented: Binding(
                get: { model.deleteBlockedUnit != nil },
                set: { if !$0 { model.deleteBlockedUnit = nil } }
            ),
            presenting: model.deleteBlockedUnit
        ) { _ in
            Button("OK", role: .cancel) { model.deleteBlockedUnit = nil }
        } message: { unit in
            let count = unit.ingredients.count
            Text("\"\(unit.name)\" is assigned to \(count) ingredient\(count == 1 ? "" : "s"). Change the unit on those ingredients first.")
        }
    }
}
