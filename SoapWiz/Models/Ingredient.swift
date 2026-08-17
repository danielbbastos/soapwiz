import Foundation
import SwiftData

@Model
final class Ingredient {
    var name: String = ""
    var code: String = ""
    var category: IngredientCategory?
    var unit: String = ""
    var isFavorite: Bool = false

    /// A photo of the actual bottle or bag, already downscaled by
    /// `ImageDownscaler` before it is assigned. `.externalStorage` keeps it in a
    /// file beside the store rather than in the row, so fetching the inventory
    /// doesn't drag every photo into memory with it; CloudKit mirrors it as an
    /// asset for the same reason.
    @Attribute(.externalStorage) var imageData: Data?

    /// The list row's copy of `imageData`, derived from it on save and never set
    /// independently. Deliberately not external: it is small, and a row that had
    /// to fault in a file to draw its thumbnail would defeat the point of having
    /// one.
    var thumbnailData: Data?

    /// Raw value of `AvatarColor`, assigned at random in `init` and never
    /// changed afterwards. Empty on a row written before this attribute existed,
    /// or arriving from a device on an older build; `avatarColor` derives one
    /// from the name in that case rather than leaving the row uncoloured.
    var avatarColorName: String = ""

    var lowStockThreshold: Double?
    var sapValue: Double?
    var kohSapValue: Double?
    var density: Double?
    var fattyAcidProfile: FattyAcidProfile?

    /// Optional for CloudKit; read and write through `purchases`. Neither name is
    /// usable in `#Predicate` — see `ModelContainerFactory.schema`.
    @Relationship(deleteRule: .cascade, originalName: "purchases", inverse: \IngredientPurchase.ingredient)
    var purchasesStorage: [IngredientPurchase]? = []

    var purchases: [IngredientPurchase] {
        get { purchasesStorage ?? [] }
        set { purchasesStorage = newValue }
    }

    /// Optional for CloudKit; read and write through `recipeIngredients`. Neither
    /// name is usable in `#Predicate` — see `ModelContainerFactory.schema`.
    @Relationship(deleteRule: .cascade, originalName: "recipeIngredients", inverse: \RecipeIngredient.ingredient)
    var recipeIngredientsStorage: [RecipeIngredient]? = []

    var recipeIngredients: [RecipeIngredient] {
        get { recipeIngredientsStorage ?? [] }
        set { recipeIngredientsStorage = newValue }
    }

    /// Batch line items that consumed this ingredient. Deleting the ingredient
    /// nullifies the line item's back-link (`.nullify`) rather than deleting it —
    /// batch history is an immutable record that must outlive the ingredient.
    ///
    /// Optional for CloudKit; read and write through `batchLineItems`. Neither
    /// name is usable in `#Predicate` — see `ModelContainerFactory.schema`.
    @Relationship(deleteRule: .nullify, originalName: "batchLineItems", inverse: \BatchLineItem.ingredient)
    var batchLineItemsStorage: [BatchLineItem]? = []

    var batchLineItems: [BatchLineItem] {
        get { batchLineItemsStorage ?? [] }
        set { batchLineItemsStorage = newValue }
    }

    /// Recipes using this ingredient as their NaOH lye. Deleting the ingredient
    /// nullifies the recipe's link rather than deleting the recipe.
    ///
    /// Optional for CloudKit; read and write through `recipesUsingAsLye`. Neither
    /// name is usable in `#Predicate` — see `ModelContainerFactory.schema`.
    @Relationship(deleteRule: .nullify, originalName: "recipesUsingAsLye", inverse: \Recipe.lyeIngredient)
    var recipesUsingAsLyeStorage: [Recipe]? = []

    var recipesUsingAsLye: [Recipe] {
        get { recipesUsingAsLyeStorage ?? [] }
        set { recipesUsingAsLyeStorage = newValue }
    }

    /// Recipes using this ingredient as their KOH lye on the hybrid path.
    ///
    /// Optional for CloudKit; read and write through `recipesUsingAsKOHLye`.
    /// Neither name is usable in `#Predicate` — see `ModelContainerFactory.schema`.
    @Relationship(deleteRule: .nullify, originalName: "recipesUsingAsKOHLye", inverse: \Recipe.kohLyeIngredient)
    var recipesUsingAsKOHLyeStorage: [Recipe]? = []

    var recipesUsingAsKOHLye: [Recipe] {
        get { recipesUsingAsKOHLyeStorage ?? [] }
        set { recipesUsingAsKOHLyeStorage = newValue }
    }

    /// Recipes referencing this ingredient — as a line item, as the NaOH lye, or
    /// as the KOH lye. One recipe can reference it in more than one of those roles,
    /// so results are deduplicated.
    ///
    /// Batches are deliberately excluded: they snapshot the ingredient's name and
    /// cost, so history stays readable after the ingredient is gone. Recipes are
    /// live documents and would be silently miscalculated instead.
    var recipesUsingThis: [Recipe] {
        let referencing = recipeIngredients.compactMap(\.recipe) + recipesUsingAsLye + recipesUsingAsKOHLye
        var seen: Set<PersistentIdentifier> = []
        return referencing.filter { seen.insert($0.persistentModelID).inserted }
    }

    var isUsedInRecipes: Bool { !recipesUsingThis.isEmpty }

    var avatarColor: AvatarColor {
        AvatarColor.resolve(avatarColorName, fallbackSeed: name)
    }

    /// The initial drawn in place of a photo.
    var avatarLetter: String { name.avatarInitial }

    var totalRemaining: Double {
        purchases.reduce(0) { $0 + $1.remainingAmount }
    }

    var isLowStock: Bool {
        guard let threshold = lowStockThreshold else { return false }
        return totalRemaining <= threshold
    }

    var hasExpiredPurchase: Bool {
        let now = Date.now
        return purchases.contains { ($0.expiryDate ?? .distantFuture) < now }
    }

    var nearestUpcomingExpiry: Date? {
        let now = Date.now
        guard let cutoff = Calendar.current.date(byAdding: .month, value: 1, to: now) else { return nil }
        return purchases
            .compactMap(\.expiryDate)
            .filter { $0 > now && $0 <= cutoff }
            .min()
    }

    /// Every path that creates an ingredient — the form, the seeder, a bulk
    /// import, a restore — comes through here, so assigning the avatar colour
    /// once in the initialiser leaves no site that can forget it.
    init(name: String, category: IngredientCategory? = nil, unit: String = "") {
        self.name = name
        self.category = category
        self.unit = unit
        self.avatarColorName = AvatarColor.random().rawValue
    }
}
