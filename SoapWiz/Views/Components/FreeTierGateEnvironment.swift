import SwiftUI
import SwiftData

extension ProFeature {
    var upgradeReason: ProUpgradeReason {
        switch self {
        case .collections: .collections
        case .reminders: .reminders
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

    /// Runs `action` when a recipe slot is free, otherwise opens the upgrade
    /// sheet naming the recipe limit.
    func ifMayCreateRecipe(in context: ModelContext, perform action: () -> Void) {
        if gate.canCreateRecipe(in: context) {
            action()
        } else {
            presentUpgrade(for: .recipeLimit)
        }
    }

    /// Runs `action` when the feature is included, otherwise opens the upgrade
    /// sheet naming it.
    func ifAvailable(_ feature: ProFeature, perform action: () -> Void) {
        if gate.allows(feature) {
            action()
        } else {
            presentUpgrade(for: feature.upgradeReason)
        }
    }

    /// Runs `action` for a filing change the free tier allows (unfiling always),
    /// otherwise opens the upgrade sheet for collections.
    func ifMayToggleCollection(isFiled: Bool, perform action: () -> Void) {
        if gate.mayToggleCollection(isFiled: isFiled) {
            action()
        } else {
            presentUpgrade(for: ProFeature.collections.upgradeReason)
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
