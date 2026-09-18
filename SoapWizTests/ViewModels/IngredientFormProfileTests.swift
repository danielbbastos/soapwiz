import Testing
import Foundation
import SwiftData
@testable import SoapWiz

@Suite("IngredientForm – KOH SAP & fatty-acid profile", .serialized)
@MainActor
struct IngredientFormProfileTests: IngredientFormTestHelpers {

    private func oilModel(_ ctx: ModelContext) -> IngredientFormViewModel {
        let cat = IngredientCategory(name: IngredientCategory.Name.oils)
        ctx.insert(cat)
        let model = IngredientFormViewModel()
        model.name = "Olive Oil"
        model.selectedUnit = .grams
        model.selectedCategory = cat
        return model
    }

    // MARK: - KOH SAP

    @Test func saveKohSap_PersistsValue() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let model = oilModel(ctx)
        model.kohSapValue = "0.188"

        let ingredient = try #require(model.save(context: ctx))

        #expect(ingredient.kohSapValue == 0.188)
    }

    @Test func saveKohSap_EmptyString_StoresNil() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let model = oilModel(ctx)
        model.kohSapValue = ""

        let ingredient = try #require(model.save(context: ctx))

        #expect(ingredient.kohSapValue == nil)
    }

    // MARK: - Fatty-acid profile

    @Test func saveProfile_PersistsAllAcids() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let model = oilModel(ctx)
        let profile = FattyAcidProfile(palmitic: 3.5, stearic: 3, oleic: 61, linoleic: 20)
        model.fattyAcidProfile = profile

        let ingredient = try #require(model.save(context: ctx))

        #expect(ingredient.fattyAcidProfile == profile)
    }

    @Test func saveProfile_AllZero_StoresNil() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let model = oilModel(ctx)
        model.fattyAcidProfile = .zero

        let ingredient = try #require(model.save(context: ctx))

        #expect(ingredient.fattyAcidProfile == nil)
    }

    @Test func saveProfile_NonOilCategory_PreservesExisting() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let oil = Ingredient(name: "Olive Oil", category: IngredientCategory(name: IngredientCategory.Name.oils), unit: "g")
        oil.fattyAcidProfile = FattyAcidProfile(oleic: 70, linoleic: 30)
        ctx.insert(oil)
        try ctx.save()

        // Recategorised to a non-oil, which hides the profile field — the stored
        // profile must survive rather than being nulled by an unrelated edit.
        let model = IngredientFormViewModel(ingredient: oil)
        model.selectedCategory = IngredientCategory(name: IngredientCategory.Name.additives)
        model.save(context: ctx)

        #expect(oil.fattyAcidProfile == FattyAcidProfile(oleic: 70, linoleic: 30))
    }

    // MARK: - Dirty tracking

    @Test func isDirty_KohSapChanged_IsTrue() {
        let model = IngredientFormViewModel()
        model.kohSapValue = "0.19"

        #expect(model.isDirty)
    }

    @Test func isDirty_ProfileChanged_IsTrue() {
        let model = IngredientFormViewModel()
        model.fattyAcidProfile = FattyAcidProfile(oleic: 100)

        #expect(model.isDirty)
    }

    @Test func isDirty_EditedOilWithProfileUntouched_IsFalse() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let oil = Ingredient(name: "Olive Oil", category: IngredientCategory(name: IngredientCategory.Name.oils), unit: "g")
        oil.sapValue = 0.1345
        oil.kohSapValue = 0.1885
        oil.fattyAcidProfile = FattyAcidProfile(palmitic: 10, oleic: 70, linoleic: 20)
        ctx.insert(oil)
        try ctx.save()

        let model = IngredientFormViewModel(ingredient: oil)

        #expect(model.isDirty == false)
    }

    // MARK: - FattyAcidProfile helpers

    @Test func fattyAcidProfile_Total_SumsAllAcids() {
        let profile = FattyAcidProfile(palmitic: 3.5, stearic: 3, oleic: 61, linoleic: 20)
        #expect(profile.total == 87.5)
    }

    @Test func fattyAcidProfile_IsEmpty_TrueOnlyForZero() {
        #expect(FattyAcidProfile.zero.isEmpty)
        #expect(FattyAcidProfile(oleic: 1).isEmpty == false)
    }
}
