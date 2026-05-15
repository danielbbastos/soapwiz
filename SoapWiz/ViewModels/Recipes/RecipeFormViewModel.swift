import SwiftData
import Foundation

@Observable
final class RecipeFormViewModel {
    var name: String
    var desc: String

    init() {
        self.name = ""
        self.desc = ""
    }

    var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    @discardableResult
    func save(context: ModelContext) -> Recipe {
        let recipe = Recipe(name: name.trimmingCharacters(in: .whitespaces),
                            desc: desc.trimmingCharacters(in: .whitespaces))
        context.insert(recipe)
        return recipe
    }
}
