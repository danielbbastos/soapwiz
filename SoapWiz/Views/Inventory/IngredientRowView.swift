import SwiftUI

struct IngredientRowView: View {
    let ingredient: Ingredient
    let onToggleFavorite: () -> Void

    @Environment(\.editMode) private var editMode

    @State private var showingExpiryPopover = false
    @State private var showingLowStockPopover = false

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(ingredient.name)
                    .font(.body.weight(.medium))
                if let categoryName = ingredient.category?.name {
                    Text(categoryName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 6) {
                    if ingredient.hasExpiredPurchase {
                        Button {
                            showingExpiryPopover = true
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                        .popover(isPresented: $showingExpiryPopover) {
                            Text("This ingredient has an expired purchase.")
                                .padding()
                                .presentationCompactAdaptation(.popover)
                        }
                    } else if let expiry = ingredient.nearestUpcomingExpiry {
                        Button {
                            showingExpiryPopover = true
                        } label: {
                            Image(systemName: "calendar.badge.exclamationmark")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                        .popover(isPresented: $showingExpiryPopover) {
                            Text("Expires on \(expiry.formatted(.dateTime.day().month(.wide)))")
                                .padding()
                                .presentationCompactAdaptation(.popover)
                        }
                    }
                    if ingredient.isLowStock {
                        Button {
                            showingLowStockPopover = true
                        } label: {
                            Image(systemName: "gauge.low")
                                .foregroundStyle(.orange)
                        }
                        .buttonStyle(.borderless)
                        .popover(isPresented: $showingLowStockPopover) {
                            Text("Low stock")
                                .padding()
                                .presentationCompactAdaptation(.popover)
                        }
                    }
                }
                Text("\(ingredient.totalRemaining.formatted(.number.precision(.fractionLength(0...2)))) \(ingredient.unit)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(ingredient.totalRemaining > 0 ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
            }
            // Beside the warnings-and-quantity column rather than stacked above it.
            // Inside it, the star adds a line to every row — including the many
            // rows with no warning icon, whose icon row is otherwise empty and
            // zero-height — and makes the whole list taller.
            //
            // Hidden while selecting, the same way the FAB is: the star would
            // otherwise consume the tap meant to select the row for a bulk delete.
            if editMode?.wrappedValue != .active {
                FavoriteStarButton(isFavorite: ingredient.isFavorite, action: onToggleFavorite)
            }
        }
        .padding(.vertical, 2)
    }
}
