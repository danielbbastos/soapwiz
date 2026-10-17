import SwiftUI
import SwiftData

/// What a view creates that the free tier counts.
enum FreeTierSlot {
    case recipe
    case customIngredient

    var limitReason: ProUpgradeReason {
        switch self {
        case .recipe: .recipeLimit
        case .customIngredient: .customIngredientLimit
        }
    }
}

/// A `FreeTierGate` together with the presenter that opens the upgrade sheet,
/// for views that act on the answer. The gate stays a plain value for the
/// view models and tests; the presenter is optional because the tour's
/// sandbox has none.
struct FreeTierAccess {
    let gate: FreeTierGate
    let presenter: ProUpgradePresenter?

    /// Runs `action` when a slot is free, otherwise opens the upgrade sheet
    /// with the limit that was hit.
    func ifAllowed(_ slot: FreeTierSlot, in context: ModelContext, perform action: () -> Void) {
        let allowed = switch slot {
        case .recipe: gate.canCreateRecipe(in: context)
        case .customIngredient: gate.canCreateCustomIngredient(in: context)
        }
        if allowed {
            action()
        } else {
            presentUpgrade(for: slot.limitReason)
        }
    }

    func presentUpgrade(for reason: ProUpgradeReason) {
        presenter?.present(reason: reason)
    }
}

/// The `FreeTierAccess` for whatever the environment says about Pro and the
/// tour's sandbox, so a view declares `@FreeTierGateEnvironment private var freeTier`
/// rather than reading all three itself. The Pro store is optional: the tour's
/// sandbox doesn't carry it.
@propertyWrapper
struct FreeTierGateEnvironment: DynamicProperty {
    @Environment(ProStore.self) private var proStore: ProStore?
    @Environment(ProUpgradePresenter.self) private var presenter: ProUpgradePresenter?
    @Environment(\.isTourSandbox) private var isTourSandbox

    var wrappedValue: FreeTierAccess {
        FreeTierAccess(
            gate: FreeTierGate(isPro: proStore?.isPro ?? false, isTourSandbox: isTourSandbox),
            presenter: presenter
        )
    }
}
