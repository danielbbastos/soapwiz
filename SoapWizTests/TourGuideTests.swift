import Testing
import Foundation
import SwiftData
import SwiftUI
@testable import SoapWiz

/// The tour guide (SW-292) driving a sandbox's navigation, without any
/// interface: the state each step leaves behind, how moves and skips settle,
/// and that none of it reaches a real store.
@Suite("Tour guide")
@MainActor
struct TourGuideTests: TourGuideTestCase {

    // MARK: - Applying a screen

    @Test func apply_Purchase_OpensOliveOilOnTheInventoryTab() async throws {
        let sandbox = try makeSandbox()
        let guide = makeGuide(for: sandbox, isPad: false)

        await guide.apply(TourStep.purchase.screen(isPad: false))

        #expect(sandbox.navigation.selectedTab == .inventory)
        #expect(sandbox.navigation.inventory.selection == (try oliveOil(in: sandbox)))
    }

    @Test func apply_Library_ClosesTheOpenIngredient() async throws {
        let sandbox = try makeSandbox()
        let guide = makeGuide(for: sandbox, isPad: false)
        await guide.apply(TourStep.purchase.screen(isPad: false))

        await guide.apply(TourStep.library.screen(isPad: false))

        #expect(sandbox.navigation.inventory.selection == nil)
        #expect(sandbox.navigation.inventory.path.isEmpty)
    }

    @Test func apply_Recipes_ShowsTheListWithNothingSelected() async throws {
        let sandbox = try makeSandbox()
        let guide = makeGuide(for: sandbox, isPad: false)

        await guide.apply(TourStep.recipes.screen(isPad: false))

        #expect(sandbox.navigation.selectedTab == .recipes)
        #expect(sandbox.navigation.recipes.selection == nil)
    }

    @Test func apply_LyeOnIPhone_PushesTheEditFormOntoTheRecipePage() async throws {
        let sandbox = try makeSandbox()
        let guide = makeGuide(for: sandbox, isPad: false)

        await guide.apply(TourStep.basics.screen(isPad: false))

        #expect(sandbox.navigation.recipes.selection == (try recipe(in: sandbox)))
        #expect(sandbox.navigation.recipes.path.count == 2)
        #expect(sandbox.navigation.recipeFormRequest == nil)
        #expect(guide.formTab == .config)
    }

    @Test func apply_FormStepsOnIPhone_PushTheFormOnlyOnce() async throws {
        let sandbox = try makeSandbox()
        let guide = makeGuide(for: sandbox, isPad: false)

        for step in [TourStep.basics, .ingredients, .cost, .qualities] {
            await guide.apply(step.screen(isPad: false))
            #expect(sandbox.navigation.recipes.path.count == 2)
        }
        #expect(guide.formTab == .stats)
    }

    @Test func apply_ReadyOnIPhone_PopsTheFormBackToTheRecipePage() async throws {
        let sandbox = try makeSandbox()
        let guide = makeGuide(for: sandbox, isPad: false)
        await guide.apply(TourStep.qualities.screen(isPad: false))

        await guide.apply(TourStep.ready.screen(isPad: false))

        #expect(sandbox.navigation.recipes.selection == (try recipe(in: sandbox)))
        #expect(sandbox.navigation.recipes.path.count == 1)
    }

    @Test func apply_LyeOnIPad_RequestsTheFullScreenEditForm() async throws {
        let sandbox = try makeSandbox()
        let guide = makeGuide(for: sandbox, isPad: true)

        await guide.apply(TourStep.basics.screen(isPad: true))

        let request = try #require(sandbox.navigation.recipeFormRequest)
        guard case .edit(let edited, _) = request else {
            Issue.record("Expected an edit request, got \(request)")
            return
        }
        #expect(edited == (try recipe(in: sandbox)))
        #expect(sandbox.navigation.recipes.selection == edited)
    }

    @Test func apply_StepsFourToEightOnIPad_EndWithTheRecipeSelectedAndNoFormRequest() async throws {
        let sandbox = try makeSandbox()
        let guide = makeGuide(for: sandbox, isPad: true)
        await guide.apply(TourStep.recipes.screen(isPad: true))

        for step in [TourStep.basics, .ingredients, .cost, .qualities, .ready] {
            await guide.apply(step.screen(isPad: true))
        }

        #expect(sandbox.navigation.recipes.selection == (try recipe(in: sandbox)))
        #expect(sandbox.navigation.recipeFormRequest == nil)
        #expect(sandbox.navigation.detailSheetRequest == nil)
        #expect(sandbox.navigation.selectedTab == .recipes)
    }

    @Test func apply_RecipesAfterTheFormOnIPad_ClosesTheFormAndTheDetail() async throws {
        let sandbox = try makeSandbox()
        let guide = makeGuide(for: sandbox, isPad: true)
        await guide.apply(TourStep.basics.screen(isPad: true))

        await guide.apply(TourStep.recipes.screen(isPad: true))

        #expect(sandbox.navigation.recipeFormRequest == nil)
        #expect(sandbox.navigation.recipes.selection == nil)
    }

    @Test func apply_BatchThenRecord_OpensAndClosesTheSheet() async throws {
        let sandbox = try makeSandbox()
        let guide = makeGuide(for: sandbox, isPad: false)
        await guide.apply(TourStep.ready.screen(isPad: false))

        await guide.apply(TourStep.batch.screen(isPad: false))
        let request = try #require(sandbox.navigation.detailSheetRequest)
        guard case .createBatch(let target) = request.kind else {
            Issue.record("Expected a Create Batch request, got \(request.kind)")
            return
        }
        #expect(target == (try recipe(in: sandbox)))

        await guide.apply(TourStep.record.screen(isPad: false))
        #expect(sandbox.navigation.detailSheetRequest == nil)
        #expect(sandbox.navigation.selectedTab == .history)
    }

    @Test func apply_SetsTheFormTabAndCostPanelTheFormFollows() async throws {
        let sandbox = try makeSandbox()
        let guide = makeGuide(for: sandbox, isPad: false)

        await guide.apply(TourStep.cost.screen(isPad: false))
        #expect(guide.formTab == .ingredients)
        #expect(guide.costPanelExpanded)

        await guide.apply(TourStep.qualities.screen(isPad: false))
        #expect(guide.formTab == .stats)
        #expect(!guide.costPanelExpanded)
    }

    // MARK: - Moving

    @Test func next_FromWelcome_ShowsTheFirstStep() async throws {
        let sandbox = try makeSandbox()
        let guide = makeGuide(for: sandbox, isPad: false)

        guide.next()
        await guide.settled()

        #expect(guide.phase == .step(.library))
    }

    @Test func back_FromTheFirstStep_ReturnsToWelcome() async throws {
        let sandbox = try makeSandbox()
        let guide = makeGuide(for: sandbox, isPad: false, phase: .step(.library))

        guide.back()
        await guide.settled()

        #expect(guide.phase == .welcome)
    }

    @Test func back_FromWelcome_DoesNothing() async throws {
        let sandbox = try makeSandbox()
        let guide = makeGuide(for: sandbox, isPad: false)

        guide.back()
        await guide.settled()

        #expect(guide.phase == .welcome)
    }

    @Test func next_FromTheLastStep_ShowsTheClosingCard() async throws {
        let sandbox = try makeSandbox()
        let guide = makeGuide(for: sandbox, isPad: false, phase: .step(.record))

        guide.next()
        await guide.settled()

        #expect(guide.phase == .finish)
    }

    @Test(arguments: [true, false])
    func back_RetracesEveryNextAcrossTheTour(isPad: Bool) async throws {
        let sandbox = try makeSandbox()
        let guide = makeGuide(for: sandbox, isPad: isPad)
        var forward: [Int: NavigationSnapshot] = [0: NavigationSnapshot(sandbox.navigation, guide)]

        for position in 1...TourPhase.lastPosition {
            guide.next()
            await guide.settled()
            finishDismissals(in: sandbox.navigation)
            #expect(guide.phase == TourPhase(position: position))
            forward[position] = NavigationSnapshot(sandbox.navigation, guide)
        }

        for position in stride(from: TourPhase.lastPosition - 1, through: 0, by: -1) {
            guide.back()
            await guide.settled()
            finishDismissals(in: sandbox.navigation)
            #expect(guide.phase == TourPhase(position: position))
            #expect(NavigationSnapshot(sandbox.navigation, guide) == forward[position])
        }
    }

    @Test func primaryAction_OnWelcome_StartsTheTour() async throws {
        let sandbox = try makeSandbox()
        let guide = makeGuide(for: sandbox, isPad: false)

        guide.primaryAction()
        await guide.settled()

        #expect(guide.phase == .step(.library))
    }

    @Test func primaryAction_OnFinish_ClosesAsFinished() async throws {
        let sandbox = try makeSandbox()
        let guide = makeGuide(for: sandbox, isPad: false, phase: .finish)
        var closed: Bool?
        guide.onClose = { closed = $0 }

        guide.primaryAction()

        #expect(closed == true)
    }

    @Test func skip_ClosesAsNotFinished() async throws {
        let sandbox = try makeSandbox()
        let guide = makeGuide(for: sandbox, isPad: false, phase: .step(.cost))
        var closed: Bool?
        guide.onClose = { closed = $0 }

        guide.skip()

        #expect(closed == false)
    }

    @Test func start_OpensMidTourAtTheStepsScreen() async throws {
        let sandbox = try makeSandbox()
        let guide = makeGuide(for: sandbox, isPad: false)

        guide.start(at: .step(.ready))
        await guide.settled()

        #expect(guide.phase == .step(.ready))
        #expect(sandbox.navigation.recipes.selection == (try recipe(in: sandbox)))
        #expect(sandbox.navigation.recipes.path.count == 1)
    }

    // MARK: - Overlay

    @Test func overlayStep_OnlyTheStepsLayerDrawsIt() async throws {
        let sandbox = try makeSandbox()
        let guide = makeGuide(for: sandbox, isPad: true, phase: .step(.basics))

        #expect(guide.overlayStep(for: .form)?.index == 4)
        #expect(guide.overlayStep(for: .tabs) == nil)
        #expect(guide.overlayStep(for: .sheet) == nil)
    }

    @Test func overlayStep_WelcomeAndFinishDrawNoStep() async throws {
        let sandbox = try makeSandbox()

        for phase in [TourPhase.welcome, .finish] {
            let guide = makeGuide(for: sandbox, isPad: false, phase: phase)
            for layer in [TourLayer.tabs, .form, .sheet] {
                #expect(guide.overlayStep(for: layer) == nil)
            }
        }
    }

    @Test func dimsTabs_OnlyForStepsDrawnOverAPresentation() async throws {
        let sandbox = try makeSandbox()

        let sheet = makeGuide(for: sandbox, isPad: false, phase: .step(.batch))
        let phoneForm = makeGuide(for: sandbox, isPad: false, phase: .step(.cost))
        let padForm = makeGuide(for: sandbox, isPad: true, phase: .step(.cost))
        let tabsStep = makeGuide(for: sandbox, isPad: true, phase: .step(.ready))
        let welcome = makeGuide(for: sandbox, isPad: false, phase: .welcome)

        #expect(sheet.dims(.tabs))
        #expect(!phoneForm.dims(.tabs))
        #expect(padForm.dims(.tabs))
        #expect(!tabsStep.dims(.tabs))
        #expect(!welcome.dims(.tabs))
        #expect(!sheet.dims(.sheet))
        #expect(tabsStep.dims(.sheet))
        #expect(tabsStep.dims(.form))
        #expect(!welcome.dims(.sheet))
    }

    @Test func fullCardKind_FollowsThePhase() async throws {
        let sandbox = try makeSandbox()

        #expect(makeGuide(for: sandbox, isPad: false, phase: .welcome).fullCardKind == .welcome)
        #expect(makeGuide(for: sandbox, isPad: false, phase: .finish).fullCardKind == .finish)
        #expect(makeGuide(for: sandbox, isPad: false, phase: .step(.cost)).fullCardKind == nil)
    }

}
