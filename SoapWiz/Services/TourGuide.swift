import Foundation
import OSLog
import SwiftData
import SwiftUI

/// Runs the onboarding tour: which card is up, and the sandbox's interface put
/// into the state each step points at.
///
/// A step is applied as a whole `TourScreen` through the sandbox's
/// `AppNavigation`, never by tapping anything, so Back is the previous step's
/// screen applied again. The two pieces of state the form owns itself, its tab
/// and the cost panel, are held here for it to follow.
///
/// A step whose targets never appear (a control a later version moved, a row
/// the sample doesn't have) is skipped in the direction of travel, so the tour
/// loses a step rather than showing a card pointing at nothing.
@Observable
@MainActor
final class TourGuide {
    private static let log = Logger(subsystem: "pt.tachyon.SoapWiz", category: "tour")

    /// How long a step waits for its targets before it is given up on.
    nonisolated static let defaultAnchorTimeout: Duration = .seconds(1)

    /// How long a presentation waits for the one before it to finish leaving.
    private static let presentationTimeout: Duration = .seconds(1)

    private static let pollInterval: Duration = .milliseconds(40)

    private(set) var phase: TourPhase

    /// The tab the recipe form is asked to show.
    private(set) var formTab: RecipeTab = .config

    /// Whether the form's cost panel is asked to be open.
    private(set) var costPanelExpanded = false

    let isPad: Bool

    /// Called with whether the tour was finished (true) or skipped (false).
    var onClose: (Bool) -> Void

    private let navigation: AppNavigation
    private let context: ModelContext

    /// Nil to give no step up, for tests that have no overlay to report anchors.
    private let anchorTimeout: Duration?

    /// The anchors each layer's host last reported. Not observed: the guide
    /// polls it, and a view reading it would redraw on every layout.
    @ObservationIgnored private var reported: [TourLayer: Set<TourAnchorID>] = [:]

    @ObservationIgnored private var applied: TourScreen?
    @ObservationIgnored private var movement: Task<Void, Never>?

    init(
        navigation: AppNavigation,
        context: ModelContext,
        isPad: Bool? = nil,
        anchorTimeout: Duration? = TourGuide.defaultAnchorTimeout,
        phase: TourPhase = .welcome,
        onClose: @escaping (Bool) -> Void = { _ in }
    ) {
        self.navigation = navigation
        self.context = context
        self.isPad = isPad ?? RecipeFormRequest.opensFullScreen
        self.anchorTimeout = anchorTimeout
        self.phase = phase
        self.onClose = onClose
    }

    // MARK: - What the overlays draw

    /// The step to draw in `layer`, nil for every other layer and for the
    /// welcome and closing cards.
    func overlayStep(for layer: TourLayer) -> TourOverlayStep? {
        guard case .step(let step) = phase, step.layer(isPad: isPad) == layer else { return nil }
        return step.overlayStep
    }

    /// Whether `layer` is to draw a plain dim, because the step on show belongs
    /// to another one. The tabs dim under a sheet or the iPad form's cover that
    /// has the step, so the whole screen reads as dimmed; and the sheet or cover
    /// stays dimmed while it closes for a step on the tabs.
    func dims(_ layer: TourLayer) -> Bool {
        guard case .step(let step) = phase else { return false }
        return step.layer(isPad: isPad) != layer
    }

    var fullCardKind: TourFullCard.Kind? {
        switch phase {
        case .welcome: .welcome
        case .finish: .finish
        case .step: nil
        }
    }

    /// Called by each layer's overlay host with the anchors it can see.
    func report(_ anchors: Set<TourAnchorID>, in layer: TourLayer) {
        reported[layer] = anchors
    }

    // MARK: - Moving

    /// Puts the tour at `phase` without a move from anywhere, for a launch
    /// that opens mid-tour.
    func start(at phase: TourPhase = .welcome) {
        run(toward: phase, direction: .forward)
    }

    func next() {
        move(.forward)
    }

    func back() {
        move(.backward)
    }

    func skip() {
        movement?.cancel()
        onClose(false)
    }

    /// The welcome card's button starts the tour; the closing card's ends it.
    func primaryAction() {
        switch phase {
        case .welcome, .step:
            next()
        case .finish:
            movement?.cancel()
            onClose(true)
        }
    }

    /// Returns once the move in progress, skips included, has settled.
    func settled() async {
        await movement?.value
    }

    private func move(_ direction: TourDirection) {
        let target = phase.neighbour(direction)
        guard target != phase else { return }
        run(toward: target, direction: direction)
    }

    private func run(toward target: TourPhase, direction: TourDirection) {
        movement?.cancel()
        movement = Task { await settle(on: target, direction: direction) }
    }

    /// Shows `target`, or the first step past it in `direction` that has
    /// something to point at.
    private func settle(on target: TourPhase, direction: TourDirection) async {
        var candidate = target
        while !Task.isCancelled {
            phase = candidate
            await apply(candidate.screen(isPad: isPad))
            guard case .step(let step) = candidate else { return }
            if await targetsAppear(for: step) || Task.isCancelled { return }
            Self.log.notice("Tour step \(step.rawValue) skipped, none of its targets appeared")
            candidate = candidate.neighbour(direction)
        }
    }

    private func targetsAppear(for step: TourStep) async -> Bool {
        guard let anchorTimeout else { return true }
        let clock = ContinuousClock()
        let deadline = clock.now + anchorTimeout
        let targets = Set(step.targets)
        let layer = step.layer(isPad: isPad)
        while clock.now < deadline {
            if !targets.isDisjoint(with: reported[layer] ?? []) { return true }
            try? await Task.sleep(for: Self.pollInterval)
            if Task.isCancelled { return true }
        }
        return !targets.isDisjoint(with: reported[layer] ?? [])
    }

    // MARK: - Applying a screen

    /// Sets the sandbox's navigation to `screen`. Closing comes first, and each
    /// presentation waits for any other to finish leaving before it goes up:
    /// SwiftUI can present one thing at a time, and a request made over one
    /// that is still closing is dropped.
    func apply(_ screen: TourScreen) async {
        let previous = applied
        applied = screen
        formTab = screen.formTab
        costPanelExpanded = screen.costPanelExpanded

        if !screen.createBatchSheet, let request = navigation.detailSheetRequest {
            navigation.closeDetailSheet(request.id)
        }
        if screen.form != .cover, navigation.recipeFormRequest != nil {
            navigation.recipeFormRequest = nil
        }

        navigation.selectedTab = screen.tab
        applyInventory(screen)
        navigation.history.reset()
        let recipe = screen.showsRecipe ? sampleRecipe : nil
        applyRecipes(screen, recipe: recipe, previous: previous)

        guard let recipe else { return }
        if screen.form == .cover, navigation.recipeFormRequest == nil {
            await waitForPresentations()
            guard !Task.isCancelled else { return }
            navigation.recipeFormRequest = .edit(recipe)
        }
        if screen.createBatchSheet, navigation.detailSheetRequest == nil {
            await waitForPresentations()
            guard !Task.isCancelled else { return }
            navigation.detailSheetRequest = .createBatch(recipe)
        }
    }

    private func applyInventory(_ screen: TourScreen) {
        if screen.showsOliveOil, let oliveOil = sampleOliveOil {
            if navigation.inventory.selection != oliveOil {
                navigation.inventory.show(oliveOil)
            }
        } else {
            navigation.inventory.reset()
        }
    }

    private func applyRecipes(_ screen: TourScreen, recipe: Recipe?, previous: TourScreen?) {
        guard let recipe else {
            navigation.recipes.reset()
            return
        }
        switch screen.form {
        case .none, .cover:
            // Popping the form off an iPhone stack is showing the recipe again.
            if previous?.form == .pushed || navigation.recipes.selection != recipe {
                navigation.recipes.show(recipe)
            }
        case .pushed:
            if previous?.form != .pushed {
                navigation.recipes.show(recipe)
                navigation.recipes.path.append(RecipeEditRoute(recipe: recipe))
            }
        }
    }

    /// Waits until neither the form's cover nor the detail sheet is on screen,
    /// closing included, or the timeout runs out.
    private func waitForPresentations() async {
        let clock = ContinuousClock()
        let deadline = clock.now + Self.presentationTimeout
        while clock.now < deadline, !Task.isCancelled {
            if !navigation.isRecipeFormOnScreen && !navigation.isDetailSheetOnScreen { return }
            try? await Task.sleep(for: Self.pollInterval)
        }
    }

    // MARK: - Sample rows

    private var sampleOliveOil: Ingredient? {
        let name = TourSample.oliveOilName
        let rows = (try? context.fetch(FetchDescriptor<Ingredient>(predicate: #Predicate { $0.name == name }))) ?? []
        return rows.first { !$0.librarySlug.isEmpty }
    }

    private var sampleRecipe: Recipe? {
        let name = TourSample.recipeName
        return (try? context.fetch(FetchDescriptor<Recipe>(predicate: #Predicate { $0.name == name })))?.first
    }
}
