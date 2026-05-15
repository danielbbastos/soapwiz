import SwiftUI

struct RecipeRowView: View {
    let recipe: Recipe

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(recipe.name)
                .font(.headline)
            if !recipe.desc.isEmpty {
                Text(recipe.desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
    }
}
