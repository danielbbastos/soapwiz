import Foundation
import OSLog
import SwiftData

/// Loading an existing recipe into the form and persisting the form back to a
/// `Recipe`. Kept apart from the view-model's live editing state for clarity.
extension RecipeFormViewModel {
    private static let log = Logger(subsystem: "pt.tachyon.SoapWiz", category: "recipe")

    func load(from recipe: Recipe) {
        editingRecipe = recipe
        name = recipe.name
        desc = recipe.desc
        imageData = recipe.imageData
        weightUnit = recipe.weightUnit
        recipeKind = RecipeKind.resolve(recipe.recipeKind)
        totalOilWeight = recipe.totalOilWeight
        oilWeightUnit = recipe.oilWeightUnit
        lyeType = recipe.lyeType
        lyePurity = recipe.lyePurity
        waterParts = recipe.waterParts
        superFat = recipe.superFat
        fragrancePercentage = recipe.fragrancePercentage
        useHybrid = recipe.useHybrid
        kohPercentage = recipe.kohPercentage
        naohPercentage = recipe.naohPercentage
        kohPurity = recipe.kohPurity
        naohPurity = recipe.naohPurity
        isCreamSoap = recipe.isCreamSoap
        useCFM = recipe.useCFM
        cfmNeutralizer = CFMNeutralizer.resolve(recipe.cfmNeutralizer)
        lyeIngredient = recipe.lyeIngredient
        kohLyeIngredient = recipe.kohLyeIngredient
        neutralizerIngredient = recipe.neutralizerIngredient
        selectedCollections = recipe.collections.sortedByName

        unresolvedLineItemCount = recipe.ingredients.count { $0.ingredient == nil }

        oilDrafts = recipe.ingredients
            .filter { $0.ingredientRole == .oil }
            .compactMap { line -> OilIngredientDraft? in
                guard let ingredient = line.ingredient else { return nil }
                return OilIngredientDraft(ingredient: ingredient, amount: line.percentage, isLocked: true)
            }
        additiveDrafts = recipe.ingredients
            .filter { $0.ingredientRole == .additive }
            .compactMap(Self.amountDraft)
        fragranceDrafts = recipe.ingredients
            .filter { $0.ingredientRole == .fragrance }
            .compactMap(Self.amountDraft)

        lockLoadedFragranceRows(with: FragranceUnit.resolve(recipe.fragranceUnit))

        productDrafts = recipe.products.map {
            RecipeProductDraft(size: $0.size, unitSymbol: $0.unitSymbol, modelID: $0.persistentModelID)
        }
        if productDrafts.isEmpty {
            productDrafts = [.seededPlaceholder()]
        }

        // Before the form captures its clean baseline, so a recipe stored under
        // one kind opens coherent under the one it now has.
        reconcileAdditiveUnits()
        reconcileFragranceUnit()
    }

    @discardableResult
    func save(context: ModelContext) -> Recipe {
        let recipe = editingRecipe ?? {
            let new = Recipe(name: "", desc: "")
            context.insert(new)
            return new
        }()
        recipe.name = name.trimmingCharacters(in: .whitespaces)
        recipe.desc = desc.trimmingCharacters(in: .whitespaces)
        applyImage(to: recipe)
        recipe.weightUnit = weightUnit
        recipe.recipeKind = recipeKind.rawValue
        recipe.totalOilWeight = totalOilWeight
        recipe.oilWeightUnit = oilWeightUnit
        recipe.lyeType = lyeType
        recipe.lyePurity = lyePurity
        recipe.waterParts = waterParts
        recipe.superFat = superFat
        recipe.fragrancePercentage = fragrancePercentage
        recipe.fragranceUnit = fragranceUnit.rawValue
        recipe.useHybrid = useHybrid
        recipe.kohPercentage = kohPercentage
        recipe.naohPercentage = naohPercentage
        recipe.kohPurity = kohPurity
        recipe.naohPurity = naohPurity
        recipe.isCreamSoap = isCreamSoap
        recipe.useCFM = useCFM
        recipe.cfmNeutralizer = cfmNeutralizer.rawValue
        // Resolved for the same reason the line-item drafts are. The merge
        // repoints `recipe.lyeIngredient` onto the survivor before deleting the
        // copy this form captured, so writing the captured reference back would
        // undo that repoint and leave the recipe's lye pointing at a detached
        // row. `Recipe.lyeIngredient` nullifies, so a lye that resolves to
        // nothing is cleared rather than dangling.
        recipe.lyeIngredient = lyeIngredient.flatMap {
            LiveIngredient.resolve($0, slug: lyeIngredientSlug, in: context)
        }
        recipe.kohLyeIngredient = kohLyeIngredient.flatMap {
            LiveIngredient.resolve($0, slug: kohLyeIngredientSlug, in: context)
        }
        recipe.neutralizerIngredient = neutralizerIngredient.flatMap {
            LiveIngredient.resolve($0, slug: neutralizerIngredientSlug, in: context)
        }
        recipe.collections = selectedCollections

        // Line items with no ingredient survive the rebuild: the ingredient may
        // simply not have synced yet, and deleting the row would destroy it for
        // every device.
        recipe.ingredients.filter { $0.ingredient != nil }.forEach { context.delete($0) }
        insertIngredients(into: recipe, context: context)

        applyProducts(to: recipe, context: context)

        // Deleted line items linger in `recipe.ingredients` until the context
        // processes them, so a caller that re-reads the recipe the moment this
        // returns would see every row twice.
        context.processPendingChanges()
        return recipe
    }

    /// Writes the photo and the thumbnail derived from it. The two always move
    /// together: a stale thumbnail beside a replaced photo would show the old
    /// picture in the list and the new one on the detail screen, and a thumbnail
    /// left behind by a removed photo would show a recipe that no longer has one.
    ///
    /// The image is only rewritten when it actually changed, so re-saving an
    /// untouched recipe doesn't rewrite the external file and hand CloudKit an
    /// asset to re-upload.
    private func applyImage(to recipe: Recipe) {
        guard recipe.imageData != imageData else { return }
        recipe.imageData = imageData
        recipe.thumbnailData = imageData.flatMap(ImageDownscaler.thumbnail(from:))
    }

    /// Writes only the recipe's `RecipeProduct` rows, leaving ingredients and
    /// every other field alone. The recipe detail screen adds and deletes
    /// products without opening the form, and a full `save(context:)` there
    /// would rewrite the whole ingredient graph as a side effect.
    func saveProducts(context: ModelContext) throws {
        guard let recipe = editingRecipe else { return }
        let inserted = applyProducts(to: recipe, context: context)

        // An inserted model keeps a temporary `persistentModelID` until the
        // context is saved, so the new drafts are stamped only afterwards:
        // holding a temporary id would make the next diff miss its match and
        // delete the product it should have updated. The surrounding drafts are
        // left as they are, so the detail screen's rows keep their identity.
        do {
            try context.save()
        } catch {
            // The reconcile is already applied to the model graph, so the
            // context is rolled back to keep it aligned with the drafts the
            // caller restores. The ids are left unstamped — stamping a
            // temporary id is what makes the following reconcile destructive —
            // and the error is rethrown so the caller can tell the user.
            Self.log.error("Saving recipe products failed: \(error, privacy: .public)")
            context.rollback()
            throw error
        }
        for (index, product) in inserted {
            productDrafts[index].modelID = product.persistentModelID
        }
    }

    /// Reconciles the recipe's products with the current drafts, matched on
    /// `RecipeProductDraft.modelID`. Untouched products keep their identity
    /// rather than being deleted and reinserted on every save. Returns the
    /// products inserted for drafts that had none, paired with their draft
    /// index, so the caller can stamp the ids back once they are permanent.
    @discardableResult
    private func applyProducts(to recipe: Recipe, context: ModelContext) -> [(index: Int, product: RecipeProduct)] {
        let draftedIDs = Set(productDrafts.compactMap(\.modelID))
        for product in recipe.products where !draftedIDs.contains(product.persistentModelID) {
            context.delete(product)
        }

        let existing = Dictionary(
            recipe.products.map { ($0.persistentModelID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        var inserted: [(index: Int, product: RecipeProduct)] = []
        for (index, draft) in productDrafts.enumerated() {
            if let modelID = draft.modelID, let product = existing[modelID] {
                product.size = draft.size
                product.unitSymbol = draft.unitSymbol
            } else if !draft.isSeededPlaceholder {
                let product = RecipeProduct(size: draft.size, unitSymbol: draft.unitSymbol)
                product.recipe = recipe
                context.insert(product)
                inserted.append((index, product))
            }
        }
        return inserted
    }

    /// Recreates the recipe's ingredient line items from the current drafts.
    ///
    /// A draft's ingredient can have been merged away while the form was open, so
    /// each is resolved back to the row actually in the store. When nothing
    /// resolves, the line item is written with no ingredient rather than pointing
    /// at a detached one: a link to a deleted row can't be saved (before SW-165
    /// a cascade took the line item with it). A row with no
    /// ingredient is a shape the recipe already has to tolerate from sync, and
    /// `load(from:)` counts it into `unresolvedLineItemCount` where the form
    /// shows it.
    private func insertIngredients(into recipe: Recipe, context: ModelContext) {
        for draft in oilDrafts {
            let ingredient = LiveIngredient.resolve(draft.ingredient, slug: draft.ingredientSlug, in: context)
            let recipeIngredient = RecipeIngredient(ingredient: ingredient, percentage: draft.amount, role: .oil)
            recipeIngredient.recipe = recipe
            context.insert(recipeIngredient)
        }
        for (drafts, role) in [(additiveDrafts, RecipeIngredientRole.additive), (fragranceDrafts, .fragrance)] {
            for draft in drafts {
                let ingredient = LiveIngredient.resolve(draft.ingredient, slug: draft.ingredientSlug, in: context)
                let recipeIngredient = RecipeIngredient(ingredient: ingredient, percentage: 0, role: role)
                recipeIngredient.additiveAmount = draft.amount
                recipeIngredient.additiveUnit = draft.unit
                recipeIngredient.recipe = recipe
                context.insert(recipeIngredient)
            }
        }
    }

    /// Skips line items whose ingredient is missing — a row pointing at nothing
    /// can't be edited or costed, so it has no draft representation. They are
    /// counted into `unresolvedLineItemCount` and kept on the recipe.
    private static func amountDraft(from line: RecipeIngredient) -> IngredientAmountDraft? {
        guard let ingredient = line.ingredient else { return nil }
        return IngredientAmountDraft(ingredient: ingredient, amount: line.additiveAmount, unit: line.additiveUnit)
    }
}
