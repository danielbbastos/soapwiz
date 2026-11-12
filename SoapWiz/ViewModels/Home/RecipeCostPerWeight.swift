import Foundation
import SwiftData

/// The weight unit Home's cost card quotes its figures per.
enum CostWeightUnit {
    case kilogram
    case pound

    var symbol: String {
        switch self {
        case .kilogram: "kg"
        case .pound: "lb"
        }
    }

    static func preferred(for locale: Locale) -> CostWeightUnit {
        locale.measurementSystem == .us ? .pound : .kilogram
    }
}

/// One recipe's cost row in the cost card.
struct RecipeCostRow: Identifiable {
    let id: AnyHashable
    let name: String
    let costPerUnit: Double
    /// The cost as a share of the dearest row's.
    let fraction: Double
    /// The recipe the row opens; nil for a deleted recipe's batches, grouped by name.
    var recipe: Recipe?
}

/// What each recipe cost per kilogram or pound over the heatmap's window: the
/// cost of its batches divided by their recorded weight. Computed from the
/// batches, never stored.
struct RecipeCostPerWeight {
    static let rowLimit = 5

    /// One batch, reduced to what the figure needs. `groupKey` is what batches
    /// of one recipe share.
    struct Entry {
        let groupKey: AnyHashable
        let name: String
        let date: Date
        let cost: Double
        let weight: Double
        let weightUnit: String
        let tracksInventory: Bool
        var recipe: Recipe?
    }

    let rows: [RecipeCostRow]

    var isEmpty: Bool { rows.isEmpty }

    init(entries: [Entry], window: DateInterval, unit: CostWeightUnit) {
        struct Total {
            var name: String
            var recipe: Recipe?
            var cost = 0.0
            var weight = 0.0
        }

        var order: [AnyHashable] = []
        var totals: [AnyHashable: Total] = [:]
        for entry in entries {
            guard entry.date >= window.start, entry.date < window.end,
                  entry.tracksInventory,
                  entry.cost > 0,
                  entry.weight > 0,
                  let weight = MassUnitConverter.convert(entry.weight, from: entry.weightUnit, to: unit.symbol)
            else { continue }
            if totals[entry.groupKey] == nil {
                order.append(entry.groupKey)
                totals[entry.groupKey] = Total(name: entry.name, recipe: entry.recipe)
            }
            totals[entry.groupKey]?.cost += entry.cost
            totals[entry.groupKey]?.weight += weight
        }

        struct Ranked {
            let key: AnyHashable
            let name: String
            let recipe: Recipe?
            let value: Double
        }

        let ranked = order.compactMap { key -> Ranked? in
            guard let total = totals[key] else { return nil }
            return Ranked(key: key, name: total.name, recipe: total.recipe, value: total.cost / total.weight)
        }
        .sorted { lhs, rhs in
            lhs.value != rhs.value ? lhs.value > rhs.value : lhs.name < rhs.name
        }
        let highest = ranked.first?.value ?? 0
        rows = ranked.prefix(Self.rowLimit).map {
            RecipeCostRow(
                id: $0.key,
                name: $0.name,
                costPerUnit: $0.value,
                fraction: highest > 0 ? $0.value / highest : 0,
                recipe: $0.recipe
            )
        }
    }

    init(batches: [Batch], now: Date = .now, calendar: Calendar = .current, unit: CostWeightUnit) {
        let entries = batches.map { batch -> Entry in
            let key: AnyHashable = batch.recipe.map { AnyHashable($0.persistentModelID) } ?? AnyHashable(batch.recipeName)
            return Entry(
                groupKey: key,
                name: batch.recipe?.name ?? batch.recipeName,
                date: batch.dateCreated,
                cost: batch.totalCost,
                weight: batch.totalWeight,
                weightUnit: batch.totalWeightUnit,
                tracksInventory: batch.tracksInventory,
                recipe: batch.recipe
            )
        }
        self.init(
            entries: entries,
            window: BatchHeatmap.window(now: now, calendar: calendar),
            unit: unit
        )
    }
}
