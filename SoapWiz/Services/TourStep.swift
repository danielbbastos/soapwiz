import Foundation

/// Which of the tour's three overlay hosts draws a step. Each presentation
/// (the tabs, the iPad recipe form's cover, the detail sheet) is its own
/// hierarchy, and an overlay can only dim and cut out what is in its own.
enum TourLayer: Hashable {
    case tabs
    case form
    case sheet
}

enum TourDirection {
    case forward
    case backward
}

/// How the recipe form is up in a step: not at all, pushed onto the Recipes
/// stack (iPhone), or full screen over the tabs (iPad). See
/// `RecipeFormRequest.opensFullScreen`.
enum TourFormPresentation: Equatable {
    case none
    case pushed
    case cover
}

/// Everything about the interface a step needs to be true, as plain values.
/// Applying a step sets the whole of it, so going back is applying the
/// previous step's screen again; nothing has to be undone.
struct TourScreen: Equatable {
    var tab: AppTab = .inventory
    var showsOliveOil = false
    var showsRecipe = false
    var form: TourFormPresentation = .none
    var formTab: RecipeTab = .config
    var costPanelExpanded = false
    var createBatchSheet = false
}

/// The ten steps of the tour, numbered from 1 as the card shows them.
enum TourStep: Int, CaseIterable {
    case library = 1
    case purchase
    case recipes
    case basics
    case ingredients
    case cost
    case qualities
    case ready
    case batch
    case record

    static var count: Int { allCases.count }

    var title: String {
        switch self {
        case .library: "Start with your ingredients"
        case .purchase: "Log what you buy"
        case .recipes: "Your recipes"
        case .basics: "Set up the basics"
        case .ingredients: "Add your oils"
        case .cost: "See what it costs"
        case .qualities: "How the bar will turn out"
        case .ready: "Ready to make it"
        case .batch: "Make a batch"
        case .record: "Every batch you make"
        }
    }

    var body: String {
        switch self {
        case .library:
            "We’ve already added over 200 oils, butters, lyes and additives, with their SAP values. "
                + "Search for yours, or tap + to add something new."
        case .purchase:
            "Each time you buy more, add it here with the price. "
                + "When you make soap, the oldest stock gets used first."
        case .recipes:
            "Recipes you write or import end up here. Tap + to start one."
        case .basics:
            "Here’s a sample recipe we filled in. Set your oil weight, lye and superfat, "
                + "and the lye amount is calculated for you."
        case .ingredients:
            "Pick oils from your library and set them by percentage or weight. The lye and water change as you go."
        case .cost:
            "Every ingredient is priced from your purchases, with a suggested retail price. "
                + "Tap the bar to open it, and drag to see more."
        case .qualities:
            "See how hard, bubbly and gentle it’ll be. "
                + "The shaded bands show where a good bar usually sits."
        case .ready:
            "Saved recipes open here with every amount calculated. "
                + "When you’re ready to make soap, tap Create Batch."
        case .batch:
            "Choose cold or hot process and you’ll get a suggested cure time. "
                + "Making the batch takes the ingredients out of your stock."
        case .record:
            "Each batch keeps its code, its cost and a countdown until it’s ready. "
                + "Open one to add notes and photos while it cures."
        }
    }

    /// The controls the step lights. The step is skipped when none of them is
    /// on screen.
    var targets: [TourAnchorID] {
        switch self {
        case .library: [.inventorySearch, .inventoryAddButton]
        case .purchase: [.purchaseCard, .addPurchaseButton]
        case .recipes: [.recipeRow, .recipeAddButton]
        case .basics: [.formTabs, .configOilsCard]
        case .ingredients: [.oilsCard]
        case .cost: [.costPanel]
        case .qualities: [.qualityBars]
        case .ready: [.createBatchButton]
        case .batch: [.cureCard]
        case .record: [.batchRow]
        }
    }

    /// Where the overlay for the step is drawn. The recipe form is a cover
    /// above the tabs on iPad, so the tabs' own overlay can't reach it there;
    /// on iPhone it is just a screen in the stack.
    func layer(isPad: Bool) -> TourLayer {
        switch self {
        case .basics, .ingredients, .cost, .qualities: isPad ? .form : .tabs
        case .batch: .sheet
        case .library, .purchase, .recipes, .ready, .record: .tabs
        }
    }

    func screen(isPad: Bool) -> TourScreen {
        let form: TourFormPresentation = isPad ? .cover : .pushed
        switch self {
        case .library:
            return TourScreen()
        case .purchase:
            return TourScreen(showsOliveOil: true)
        case .recipes:
            return TourScreen(tab: .recipes)
        case .basics:
            return TourScreen(tab: .recipes, showsRecipe: true, form: form, formTab: .config)
        case .ingredients:
            return TourScreen(tab: .recipes, showsRecipe: true, form: form, formTab: .ingredients)
        case .cost:
            return TourScreen(
                tab: .recipes, showsRecipe: true, form: form, formTab: .ingredients, costPanelExpanded: true
            )
        case .qualities:
            return TourScreen(tab: .recipes, showsRecipe: true, form: form, formTab: .stats)
        case .ready:
            return TourScreen(tab: .recipes, showsRecipe: true)
        case .batch:
            return TourScreen(tab: .recipes, showsRecipe: true, createBatchSheet: true)
        case .record:
            return TourScreen(tab: .history)
        }
    }

    var overlayStep: TourOverlayStep {
        TourOverlayStep(index: rawValue, count: Self.count, title: title, body: body, targets: targets)
    }
}

/// Where the tour is: the welcome card, one of the ten steps, or the closing
/// card. `position` runs 0 for the welcome card to 11 for the closing one.
enum TourPhase: Equatable {
    case welcome
    case step(TourStep)
    case finish

    static let lastPosition = TourStep.count + 1

    var position: Int {
        switch self {
        case .welcome: 0
        case .step(let step): step.rawValue
        case .finish: Self.lastPosition
        }
    }

    /// Positions outside the tour are held to its ends.
    init(position: Int) {
        if position <= 0 {
            self = .welcome
        } else if let step = TourStep(rawValue: position) {
            self = .step(step)
        } else {
            self = .finish
        }
    }

    /// The phase next to this one, which is this one at either end.
    func neighbour(_ direction: TourDirection) -> TourPhase {
        switch direction {
        case .forward: TourPhase(position: position + 1)
        case .backward: TourPhase(position: position - 1)
        }
    }

    /// The screen the phase needs: the first step's behind the welcome card,
    /// the last's behind the closing one.
    func screen(isPad: Bool) -> TourScreen {
        switch self {
        case .welcome: TourStep.library.screen(isPad: isPad)
        case .step(let step): step.screen(isPad: isPad)
        case .finish: TourStep.record.screen(isPad: isPad)
        }
    }
}
