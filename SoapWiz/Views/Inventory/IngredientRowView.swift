import SwiftUI

struct IngredientRowView: View {
    let ingredient: Ingredient

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ingredient.name)
                .font(.headline)
            HStack {
                if let categoryName = ingredient.category?.name {
                    Text(categoryName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(ingredient.totalRemaining.formatted(.number.precision(.fractionLength(0...2)))) \(ingredient.unit?.symbol ?? "")")
                    .font(.subheadline)
                    .foregroundStyle(ingredient.totalRemaining > 0 ? AnyShapeStyle(.secondary) : AnyShapeStyle(.red))
            }
        }
        .padding(.vertical, 2)
    }
}
