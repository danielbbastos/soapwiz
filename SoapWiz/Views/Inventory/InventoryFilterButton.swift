import SwiftUI

/// The toolbar button that opens the filter sheet, badged with how many filters
/// are active.
struct InventoryFilterButton: View {
    let model: IngredientListViewModel

    var body: some View {
        Button {
            model.showingFilters = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: model.hasActiveFilters
                      ? "line.3.horizontal.decrease.circle.fill"
                      : "line.3.horizontal.decrease.circle")
                if model.hasActiveFilters {
                    Text("\(model.activeFilterCount)")
                        .font(.caption2.bold())
                        .foregroundStyle(Color.onAmber)
                        .padding(2)
                        .background(Color.amber, in: Circle())
                        .offset(x: 6, y: -6)
                }
            }
        }
        .foregroundStyle(model.hasActiveFilters ? Color.amberText : Color.ink)
    }
}
