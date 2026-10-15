import Testing
import Foundation
import SwiftData
import SwiftUI
@testable import SoapWiz

/// What the tour guide's suites share: a sandbox, a guide on it, and stand-ins
/// for what the interface would report if one were up.
@MainActor
protocol TourGuideTestCase {}

extension TourGuideTestCase {
    func makeSandbox() throws -> TourSandbox {
        let components = DateComponents(year: 2026, month: 6, day: 15, hour: 10)
        let now = Calendar.current.date(from: components) ?? .distantPast
        return try TourSandbox(currencyCode: "EUR", now: now)
    }

    func makeGuide(
        for sandbox: TourSandbox,
        isPad: Bool,
        anchorTimeout: Duration? = nil,
        phase: TourPhase = .welcome
    ) -> TourGuide {
        TourGuide(
            navigation: sandbox.navigation,
            context: sandbox.container.mainContext,
            isPad: isPad,
            anchorTimeout: anchorTimeout,
            phase: phase
        )
    }

    func recipe(in sandbox: TourSandbox) throws -> Recipe {
        let recipes = try sandbox.container.mainContext.fetch(FetchDescriptor<Recipe>())
        return try #require(recipes.first)
    }

    func oliveOil(in sandbox: TourSandbox) throws -> Ingredient {
        let rows = try sandbox.container.mainContext.fetch(FetchDescriptor<Ingredient>())
        return try #require(rows.first { $0.name == TourSample.oliveOilName && !$0.librarySlug.isEmpty })
    }

    /// Stands in for the interface reporting its cover and sheet gone, which
    /// no view is here to do.
    func finishDismissals(in navigation: AppNavigation) {
        if navigation.recipeFormRequest == nil { navigation.recipeFormDidClose() }
        if navigation.detailSheetRequest == nil { navigation.detailSheetDidClose() }
    }

    func rowCounts(in context: ModelContext) throws -> [Int] {
        [
            try context.fetchCount(FetchDescriptor<Ingredient>()),
            try context.fetchCount(FetchDescriptor<IngredientPurchase>()),
            try context.fetchCount(FetchDescriptor<Recipe>()),
            try context.fetchCount(FetchDescriptor<RecipeIngredient>()),
            try context.fetchCount(FetchDescriptor<Batch>()),
            try context.fetchCount(FetchDescriptor<AppSettings>())
        ]
    }
}

/// What a step leaves the navigation and the guide's form state looking like.
struct NavigationSnapshot: Equatable {
    let tab: AppTab
    let hasInventorySelection: Bool
    let hasRecipeSelection: Bool
    let recipePathCount: Int
    let hasFormRequest: Bool
    let hasSheetRequest: Bool
    let formTab: RecipeTab
    let costPanelExpanded: Bool

    @MainActor
    init(_ navigation: AppNavigation, _ guide: TourGuide) {
        tab = navigation.selectedTab
        hasInventorySelection = navigation.inventory.selection != nil
        hasRecipeSelection = navigation.recipes.selection != nil
        recipePathCount = navigation.recipes.path.count
        hasFormRequest = navigation.recipeFormRequest != nil
        hasSheetRequest = navigation.detailSheetRequest != nil
        formTab = guide.formTab
        costPanelExpanded = guide.costPanelExpanded
    }
}
