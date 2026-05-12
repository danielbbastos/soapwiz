import SwiftUI

struct IngredientRowView: View {
    let ingredient: Ingredient

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
                if let expiry = ingredient.nearestUpcomingExpiry {
                    Text("Expires \(expiry.formatted(.dateTime.day().month(.abbreviated)))")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Text("\(ingredient.totalRemaining.formatted(.number.precision(.fractionLength(0...2)))) \(ingredient.unit?.symbol ?? "")")
                    .font(.subheadline)
                    .foregroundStyle(ingredient.totalRemaining > 0 ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
            }
        }
        .padding(.vertical, 2)
    }
}
