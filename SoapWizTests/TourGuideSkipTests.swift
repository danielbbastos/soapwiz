import Testing
import Foundation
import SwiftData
@testable import SoapWiz

/// The tour guide (SW-292) giving up on steps whose targets never appear, and
/// leaving a real store alone through the whole tour.
@Suite("Tour guide skips")
@MainActor
struct TourGuideSkipTests: TourGuideTestCase {

    private let wait: Duration = .milliseconds(30)

    @Test func next_StepWhoseTargetsNeverAppear_IsSkippedForward() async throws {
        let sandbox = try makeSandbox()
        let guide = makeGuide(for: sandbox, isPad: false, anchorTimeout: wait, phase: .step(.library))
        guide.report([.recipeRow], in: .tabs)

        guide.next()
        await guide.settled()

        #expect(guide.phase == .step(.recipes))
    }

    @Test func next_ConsecutiveMissingSteps_AreAllSkipped() async throws {
        let sandbox = try makeSandbox()
        let guide = makeGuide(for: sandbox, isPad: false, anchorTimeout: wait, phase: .step(.recipes))
        guide.report([.qualityBars], in: .tabs)

        guide.next()
        await guide.settled()

        #expect(guide.phase == .step(.qualities))
    }

    @Test func next_MissingStepsToTheEnd_LandOnTheClosingCard() async throws {
        let sandbox = try makeSandbox()
        let guide = makeGuide(for: sandbox, isPad: false, anchorTimeout: wait, phase: .step(.batch))

        guide.next()
        await guide.settled()

        #expect(guide.phase == .finish)
    }

    @Test func back_StepWhoseTargetsNeverAppear_IsSkippedBackward() async throws {
        let sandbox = try makeSandbox()
        let guide = makeGuide(for: sandbox, isPad: false, anchorTimeout: wait, phase: .step(.basics))
        guide.report([.inventorySearch], in: .tabs)

        guide.back()
        await guide.settled()

        #expect(guide.phase == .step(.library))
    }

    @Test func back_MissingStepsToTheStart_LandOnWelcome() async throws {
        let sandbox = try makeSandbox()
        let guide = makeGuide(for: sandbox, isPad: false, anchorTimeout: wait, phase: .step(.recipes))

        guide.back()
        await guide.settled()

        #expect(guide.phase == .welcome)
    }

    @Test func next_TargetsReportedInTheStepsOwnLayer_ArePresent() async throws {
        let sandbox = try makeSandbox()
        let guide = makeGuide(for: sandbox, isPad: true, anchorTimeout: wait, phase: .step(.recipes))
        guide.report([.oilsCard], in: .form)
        guide.report([.configOilsCard], in: .form)

        guide.next()
        await guide.settled()

        #expect(guide.phase == .step(.basics))
    }

    @Test func next_TargetsReportedInAnotherLayer_DoNotCount() async throws {
        let sandbox = try makeSandbox()
        let guide = makeGuide(for: sandbox, isPad: true, anchorTimeout: wait, phase: .step(.recipes))
        guide.report([.configOilsCard], in: .tabs)
        guide.report([.oilsCard], in: .tabs)

        guide.next()
        await guide.settled()

        #expect(guide.phase != .step(.basics))
    }

    @Test func tour_RunThroughEveryStep_LeavesARealStoreUntouched() async throws {
        let real = try ModelContainer(
            for: ModelContainerFactory.schema,
            configurations: ModelConfiguration.inMemory(ModelContainerFactory.schema)
        )
        let realContext = real.mainContext
        realContext.insert(Ingredient(name: "My Oil", unit: "g"))
        realContext.insert(Recipe(name: "My Recipe", desc: ""))
        try realContext.save()
        let before = try rowCounts(in: realContext)
        let sandbox = try makeSandbox()
        let guide = makeGuide(for: sandbox, isPad: false)

        for _ in 0..<TourPhase.lastPosition {
            guide.next()
            await guide.settled()
            finishDismissals(in: sandbox.navigation)
        }
        for _ in 0..<TourPhase.lastPosition {
            guide.back()
            await guide.settled()
            finishDismissals(in: sandbox.navigation)
        }

        #expect(try rowCounts(in: realContext) == before)
        #expect(try rowCounts(in: sandbox.container.mainContext) != before)
        #expect(try realContext.fetch(FetchDescriptor<Recipe>()).map(\.name) == ["My Recipe"])
        #expect(guide.phase == .welcome)
    }
}
