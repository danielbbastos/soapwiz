import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// The view model's side of choosing recipes: toggling, confirming, and keeping
/// the choice (and the user's ingredient matches) across a plan rebuilt after
/// the duplicate merge.
@MainActor
@Suite
struct RecipeImportSelectionTests {

    private let fixture: RecipeTransferFixture

    init() throws {
        fixture = try RecipeTransferFixture()
    }

    private func recipe(_ name: String, oil: String) -> Recipe {
        let recipe = fixture.recipe(named: name)
        fixture.addOil(fixture.oil(oil), percentage: 100, to: recipe)
        return recipe
    }

    private func makeModelContext() throws -> (ModelContainer, ModelContext) {
        let schema = ModelContainerFactory.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration.inMemory(schema)])
        return (container, container.mainContext)
    }

    private func adoptedModel(_ recipes: [Recipe]) throws -> RecipeImportViewModel {
        let model = RecipeImportViewModel()
        model.rawText = try fixture.pastedFile(fixture.payload(recipes))
        model.adoptPayloadFromText(inventory: [], collections: [])
        return model
    }

    @Test func toggleRecipe_UnticksThenTicksAgain() throws {
        let model = try adoptedModel([recipe("A", oil: "Oil A"), recipe("B", oil: "Oil B")])

        model.toggleRecipe(0)
        #expect(model.transferPlan?.selectedRecipeIDs == [1])

        model.toggleRecipe(0)
        #expect(model.transferPlan?.selectedRecipeIDs == [0, 1])
    }

    @Test func confirmExactImport_NothingTicked_ReturnsNilAndWritesNothing() throws {
        let (container, ctx) = try makeModelContext()
        _ = container
        let model = try adoptedModel([recipe("A", oil: "Oil A")])
        model.toggleRecipe(0)

        let result = model.confirmExactImport(context: ctx, categories: [], gate: FreeTierGate(isPro: true))

        #expect(result == nil)
        #expect(try ctx.fetch(FetchDescriptor<Recipe>()).isEmpty)
        #expect(try ctx.fetch(FetchDescriptor<Ingredient>()).isEmpty)
    }

    @Test func confirmExactImport_PartialSelection_ImportsOnlyTheTicked() throws {
        let (container, ctx) = try makeModelContext()
        _ = container
        let model = try adoptedModel([recipe("A", oil: "Oil A"), recipe("B", oil: "Oil B")])
        model.toggleRecipe(0)

        let result = try #require(
            model.confirmExactImport(context: ctx, categories: [], gate: FreeTierGate(isPro: true))
        )

        #expect(result.map(\.name) == ["B"])
        #expect(try ctx.fetch(FetchDescriptor<Ingredient>()).map(\.name) == ["Oil B"])
    }

    @Test func resolveMergedRows_KeepsTheSelection() throws {
        let (container, ctx) = try makeModelContext()
        _ = container
        let model = try adoptedModel([
            recipe("A", oil: "Oil A"), recipe("B", oil: "Oil B"), recipe("C", oil: "Oil C")
        ])
        model.toggleRecipe(1)

        model.resolveMergedRows(in: ctx)

        #expect(model.transferPlan?.selectedRecipeIDs == [0, 2])
    }

    @Test func returnToInput_ForgetsTheSelection() throws {
        let model = try adoptedModel([recipe("A", oil: "Oil A"), recipe("B", oil: "Oil B")])
        model.toggleRecipe(0)

        model.returnToInput()
        model.adoptPayloadFromText(inventory: [], collections: [])

        #expect(model.transferPlan?.selectedRecipeIDs == [0, 1])
    }
}
