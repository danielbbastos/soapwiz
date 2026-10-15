import Testing
import Foundation
@testable import SoapWiz

/// The tour's script (SW-292): what each step asks of the interface, where its
/// overlay is drawn, and how the tour moves through it.
@Suite("Tour steps")
@MainActor
struct TourStepTests {

    // MARK: - Script

    @Test func steps_AreTenNumberedFromOne() {
        #expect(TourStep.count == 10)
        #expect(TourStep.allCases.map(\.rawValue) == Array(1...10))
    }

    @Test func copy_EveryStepHasATitleAndABody() {
        for step in TourStep.allCases {
            #expect(!step.title.isEmpty)
            #expect(!step.body.isEmpty)
        }
        #expect(Set(TourStep.allCases.map(\.title)).count == 10)
    }

    @Test func copy_BasicsStepIsTheConfigOverview() {
        #expect(TourStep.basics.title == "Set up the basics")
        #expect(TourStep.basics.body == "Here’s a sample recipe we filled in. Set your oil weight, lye and superfat, "
            + "and the lye amount is calculated for you.")
    }

    @Test func overlayStep_CarriesTheStepsNumberCountAndTargets() {
        let overlay = TourStep.cost.overlayStep

        #expect(overlay.index == 6)
        #expect(overlay.count == 10)
        #expect(overlay.title == TourStep.cost.title)
        #expect(overlay.targets == [.costPanel])
    }

    @Test func targets_AreTheControlsEachStepNames() {
        #expect(TourStep.library.targets == [.inventorySearch, .inventoryAddButton])
        #expect(TourStep.purchase.targets == [.purchaseCard, .addPurchaseButton])
        #expect(TourStep.recipes.targets == [.recipeRow, .recipeAddButton])
        #expect(TourStep.basics.targets == [.formTabs, .configOilsCard])
        #expect(TourStep.ingredients.targets == [.oilsCard])
        #expect(TourStep.cost.targets == [.costPanel])
        #expect(TourStep.qualities.targets == [.qualityBars])
        #expect(TourStep.ready.targets == [.createBatchButton])
        #expect(TourStep.batch.targets == [.cureCard])
        #expect(TourStep.record.targets == [.batchRow])
    }

    // MARK: - Layers

    @Test(arguments: [true, false])
    func layer_InventoryRecipesReadyAndRecordAreAlwaysTheTabs(isPad: Bool) {
        for step in [TourStep.library, .purchase, .recipes, .ready, .record] {
            #expect(step.layer(isPad: isPad) == .tabs)
        }
    }

    @Test(arguments: [true, false])
    func layer_BatchStepIsTheSheet(isPad: Bool) {
        #expect(TourStep.batch.layer(isPad: isPad) == .sheet)
    }

    @Test func layer_FormStepsAreTheCoverOnIPad() {
        for step in [TourStep.basics, .ingredients, .cost, .qualities] {
            #expect(step.layer(isPad: true) == .form)
        }
    }

    @Test func layer_FormStepsAreTheTabsOnIPhone() {
        for step in [TourStep.basics, .ingredients, .cost, .qualities] {
            #expect(step.layer(isPad: false) == .tabs)
        }
    }

    // MARK: - Screens

    @Test(arguments: [true, false])
    func screen_LibraryIsTheInventoryTabWithNothingOpen(isPad: Bool) {
        #expect(TourStep.library.screen(isPad: isPad) == TourScreen())
    }

    @Test(arguments: [true, false])
    func screen_PurchaseOpensOliveOil(isPad: Bool) {
        let screen = TourStep.purchase.screen(isPad: isPad)

        #expect(screen.tab == .inventory)
        #expect(screen.showsOliveOil)
        #expect(!screen.showsRecipe)
    }

    @Test(arguments: [true, false])
    func screen_RecipesIsTheRecipesTabWithNothingSelected(isPad: Bool) {
        let screen = TourStep.recipes.screen(isPad: isPad)

        #expect(screen.tab == .recipes)
        #expect(!screen.showsRecipe)
        #expect(screen.form == .none)
    }

    @Test func screen_FormStepsPushTheFormOnIPhone() {
        for step in [TourStep.basics, .ingredients, .cost, .qualities] {
            let screen = step.screen(isPad: false)
            #expect(screen.tab == .recipes)
            #expect(screen.showsRecipe)
            #expect(screen.form == .pushed)
            #expect(!screen.createBatchSheet)
        }
    }

    @Test func screen_FormStepsCoverTheTabsOnIPad() {
        for step in [TourStep.basics, .ingredients, .cost, .qualities] {
            let screen = step.screen(isPad: true)
            #expect(screen.tab == .recipes)
            #expect(screen.showsRecipe)
            #expect(screen.form == .cover)
        }
    }

    @Test(arguments: [true, false])
    func screen_FormTabsFollowTheScript(isPad: Bool) {
        #expect(TourStep.basics.screen(isPad: isPad).formTab == .config)
        #expect(TourStep.ingredients.screen(isPad: isPad).formTab == .ingredients)
        #expect(TourStep.cost.screen(isPad: isPad).formTab == .ingredients)
        #expect(TourStep.qualities.screen(isPad: isPad).formTab == .stats)
    }

    @Test(arguments: [true, false])
    func screen_OnlyTheCostStepOpensTheCostPanel(isPad: Bool) {
        for step in TourStep.allCases {
            #expect(step.screen(isPad: isPad).costPanelExpanded == (step == .cost))
        }
    }

    @Test(arguments: [true, false])
    func screen_ReadyClosesTheFormOntoTheRecipePage(isPad: Bool) {
        let screen = TourStep.ready.screen(isPad: isPad)

        #expect(screen.tab == .recipes)
        #expect(screen.showsRecipe)
        #expect(screen.form == .none)
        #expect(!screen.createBatchSheet)
    }

    @Test(arguments: [true, false])
    func screen_BatchOpensTheCreateBatchSheetOverTheRecipe(isPad: Bool) {
        let screen = TourStep.batch.screen(isPad: isPad)

        #expect(screen.tab == .recipes)
        #expect(screen.showsRecipe)
        #expect(screen.createBatchSheet)
        #expect(screen.form == .none)
    }

    @Test(arguments: [true, false])
    func screen_RecordIsTheHistoryTabWithTheSheetClosed(isPad: Bool) {
        let screen = TourStep.record.screen(isPad: isPad)

        #expect(screen.tab == .history)
        #expect(!screen.createBatchSheet)
    }

    @Test(arguments: [true, false])
    func screen_OnlyTheBatchStepHasASheet(isPad: Bool) {
        for step in TourStep.allCases {
            #expect(step.screen(isPad: isPad).createBatchSheet == (step == .batch))
        }
    }

    @Test(arguments: [true, false])
    func screen_WelcomeShowsTheFirstStepsAndFinishTheLasts(isPad: Bool) {
        #expect(TourPhase.welcome.screen(isPad: isPad) == TourStep.library.screen(isPad: isPad))
        #expect(TourPhase.finish.screen(isPad: isPad) == TourStep.record.screen(isPad: isPad))
    }

    // MARK: - Phases

    @Test func position_RunsFromWelcomeToFinish() {
        #expect(TourPhase.welcome.position == 0)
        #expect(TourPhase.step(.library).position == 1)
        #expect(TourPhase.step(.record).position == 10)
        #expect(TourPhase.finish.position == 11)
        #expect(TourPhase.lastPosition == 11)
    }

    @Test func initPosition_RoundTripsAndClampsOutOfRange() {
        for position in 0...11 {
            #expect(TourPhase(position: position).position == position)
        }
        #expect(TourPhase(position: -3) == .welcome)
        #expect(TourPhase(position: 40) == .finish)
    }

    @Test func neighbour_WelcomeForwardIsTheFirstStep() {
        #expect(TourPhase.welcome.neighbour(.forward) == .step(.library))
    }

    @Test func neighbour_LastStepForwardIsFinish() {
        #expect(TourPhase.step(.record).neighbour(.forward) == .finish)
    }

    @Test func neighbour_FirstStepBackIsWelcome() {
        #expect(TourPhase.step(.library).neighbour(.backward) == .welcome)
    }

    @Test func neighbour_FinishBackIsTheLastStep() {
        #expect(TourPhase.finish.neighbour(.backward) == .step(.record))
    }

    @Test func neighbour_EndsStayPutBeyondTheirEdge() {
        #expect(TourPhase.welcome.neighbour(.backward) == .welcome)
        #expect(TourPhase.finish.neighbour(.forward) == .finish)
    }

    @Test func back_IsTheExactReverseOfNextAcrossTheWholeTour() {
        for position in 0..<TourPhase.lastPosition {
            let phase = TourPhase(position: position)
            #expect(phase.neighbour(.forward).neighbour(.backward) == phase)
        }
    }
}
