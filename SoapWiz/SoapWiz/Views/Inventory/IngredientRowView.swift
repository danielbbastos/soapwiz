import SwiftUI

struct IngredientRowView: View {
    let ingredient: Ingredient

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ingredient.name)
                .font(.headline)
            HStack {
                if !ingredient.category.isEmpty {
                    Text(ingredient.category)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(ingredient.totalRemaining.formatted(.number.precision(.fractionLength(0...2)))) \(ingredient.unit)")
                    .font(.subheadline)
                    .foregroundStyle(ingredient.totalRemaining > 0 ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
            }
        }
        .padding(.vertical, 2)
    }
}
