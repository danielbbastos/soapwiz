import SwiftUI

struct RecipeRowView: View {
    let recipe: Recipe
    let onToggleFavorite: () -> Void

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.name)
                    .font(.body.weight(.medium))
                if !recipe.desc.isEmpty {
                    Text(recipe.desc)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            FavoriteStarButton(isFavorite: recipe.isFavorite, action: onToggleFavorite)
        }
        .padding(.vertical, 2)
    }
}
