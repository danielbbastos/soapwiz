import SwiftUI

struct IngredientRowView: View {
    let ingredient: Ingredient

    @State private var showingExpiryPopover = false
    @State private var showingLowStockPopover = false

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(ingredient.name)
                    .font(.headline)
                if let categoryName = ingredient.category?.name {
                    Text(categoryName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 6) {
                    if ingredient.hasExpiredBatch {
                        Button {
                            showingExpiryPopover = true
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.borderless)
                        .popover(isPresented: $showingExpiryPopover) {
                            Text("This ingredient has an expired batch.")
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
                    .font(.subheadline)
                    .foregroundStyle(ingredient.totalRemaining > 0 ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
            }
        }
        .padding(.vertical, 2)
    }
}
