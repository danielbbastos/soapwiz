import SwiftUI
import SwiftData

struct OilIngredientDraft: Identifiable {
    let id = UUID()
    let ingredient: Ingredient
    var amount: String = ""
    var isLocked: Bool = false
}

struct IngredientAmountDraft: Identifiable {
    let id = UUID()
    let ingredient: Ingredient
    var amount: String = ""
    var unit: String
    var isLocked: Bool = false
}

struct FragranceIndicator {
    let currentText: String
    let targetText: String?
    let isOverTarget: Bool
}

struct RecipeProductDraft: Identifiable {
    let id = UUID()
    var size: String = ""
    var unitSymbol: String = ""
}

struct IngredientProductBreakdown {
    let ingredient: Ingredient
    let ingredientAmount: Double
    let cost: Double
}

struct OilAmountCalculation: Identifiable {
    let id: UUID
    let ingredient: Ingredient
    let weight: Double
    let lye: Double
}

struct CalculatedAmountRow: Identifiable {
    let id = UUID()
    let label: String
    let weight: Double
    let pct: Double
    let isSummary: Bool
}

struct ExtraSectionARow: Identifiable {
    let id = UUID()
    let label: String
    let val1: Double
    let val2: Double
    let val3: Double
    let naohLyeSolution: (v1: Double, v2: Double, v3: Double)?

    init(label: String, val1: Double, val2: Double, val3: Double,
         naohLyeSolution: (v1: Double, v2: Double, v3: Double)? = nil) {
        self.label = label
        self.val1 = val1
        self.val2 = val2
        self.val3 = val3
        self.naohLyeSolution = naohLyeSolution
    }
}

struct ExtraSectionBRow: Identifiable {
    let id = UUID()
    let label: String
    let minValue: Double
    let maxValue: Double?
    let naohLyeSolution: Double?

    init(label: String, minValue: Double, maxValue: Double? = nil, naohLyeSolution: Double? = nil) {
        self.label = label
        self.minValue = minValue
        self.maxValue = maxValue
        self.naohLyeSolution = naohLyeSolution
    }
}

@Observable
final class RecipeFormViewModel {
    var name: String = ""
    var desc: String = ""
    var weightUnit: String = "%"
    var totalOilWeight: String = "1000"
    var oilWeightUnit: String = "g"
    var lyeType: String = "NaOH"
    var lyePurity: String = "99"
    var waterParts: String = "1.5"
    var superFat: String = "5"
    var oilDrafts: [OilIngredientDraft] = []
    var additiveDrafts: [IngredientAmountDraft] = []
    var fragranceDrafts: [IngredientAmountDraft] = []
    var productDrafts: [RecipeProductDraft] = []
    var fragrancePercentage: String = "3"

    @ObservationIgnored
    private var editingRecipe: Recipe?

    var weightUnitIsPercentage: Bool { weightUnit == "%" }

    var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var totalPercentage: Double {
        oilDrafts
            .compactMap { Double($0.amount.replacingOccurrences(of: ",", with: ".")) }
            .reduce(0, +)
    }

    var totalPercentageText: String { formatPercentage(totalPercentage) }

    var displayWeightUnit: String {
        weightUnitIsPercentage ? oilWeightUnit : weightUnit
    }

    var oilAmountCalculations: [OilAmountCalculation]? {
        guard !oilDrafts.isEmpty else { return nil }
        let purity = Double(lyePurity.replacingOccurrences(of: ",", with: ".")) ?? 99
        guard purity > 0 && purity <= 100 else { return nil }
        let sf = Double(superFat.replacingOccurrences(of: ",", with: ".")) ?? 5

        if weightUnitIsPercentage {
            let totalWeight = Double(totalOilWeight.replacingOccurrences(of: ",", with: ".")) ?? 0
            guard totalWeight > 0 else { return nil }
            return oilDrafts.map { draft in
                let pct = Double(draft.amount.replacingOccurrences(of: ",", with: ".")) ?? 0
                let oilWeight = totalWeight * (pct / 100)
                let sap = draft.ingredient.sapValue ?? 0
                let lye = oilWeight * sap * (1 - sf / 100) / (purity / 100)
                return OilAmountCalculation(id: draft.id, ingredient: draft.ingredient, weight: oilWeight, lye: lye)
            }
        } else {
            let calcs = oilDrafts.compactMap { draft -> OilAmountCalculation? in
                let oilWeight = Double(draft.amount.replacingOccurrences(of: ",", with: ".")) ?? 0
                guard oilWeight > 0 else { return nil }
                let sap = draft.ingredient.sapValue ?? 0
                let lye = oilWeight * sap * (1 - sf / 100) / (purity / 100)
                return OilAmountCalculation(id: draft.id, ingredient: draft.ingredient, weight: oilWeight, lye: lye)
            }
            return calcs.isEmpty ? nil : calcs
        }
    }

    var calculatedLyeAmount: Double? {
        oilAmountCalculations.map { $0.reduce(0) { $0 + $1.lye } }
    }

    var calculatedWaterAmount: Double? {
        guard let lye = calculatedLyeAmount else { return nil }
        let water = Double(waterParts.replacingOccurrences(of: ",", with: ".")) ?? 1.5
        return lye * water
    }

    var calculatedAmountRows: [CalculatedAmountRow]? {
        guard let calculations = oilAmountCalculations,
              let totalLye = calculatedLyeAmount,
              let totalWater = calculatedWaterAmount else { return nil }

        let totalOil = calculations.reduce(0.0) { $0 + $1.weight }
        let batchTotal = totalOil + totalLye + totalWater

        func batchPct(_ value: Double) -> Double { batchTotal > 0 ? value / batchTotal * 100 : 0 }

        var rows: [CalculatedAmountRow] = calculations.map { calc in
            let pct = totalOil > 0 ? calc.weight / totalOil * 100 : 0
            return CalculatedAmountRow(label: calc.ingredient.name, weight: calc.weight, pct: pct, isSummary: false)
        }
        rows.append(CalculatedAmountRow(label: "Oils total (batch)", weight: totalOil, pct: batchPct(totalOil), isSummary: true))
        rows.append(CalculatedAmountRow(label: "\(lyeType) (\(lyePurity)%, \(superFat)% SF)", weight: totalLye, pct: batchPct(totalLye), isSummary: false))
        rows.append(CalculatedAmountRow(label: "Water (\(waterParts):1)", weight: totalWater, pct: batchPct(totalWater), isSummary: false))
        rows.append(CalculatedAmountRow(label: "Batch total", weight: batchTotal, pct: 100, isSummary: true))
        return rows
    }

    var fragranceTargetPercentage: Double {
        Double(fragrancePercentage.replacingOccurrences(of: ",", with: ".")) ?? 3
    }

    var fragranceIndicator: FragranceIndicator? {
        guard !fragranceDrafts.isEmpty else { return nil }

        let units = Set(fragranceDrafts.map(\.unit))
        let unit = units.count == 1 ? fragranceDrafts[0].unit : nil

        let percentageUnits: Set<String> = ["% of oils", "% of batch", "% of liquids"]

        if let unit, percentageUnits.contains(unit) {
            let sumPct = fragranceDrafts
                .compactMap { Double($0.amount.replacingOccurrences(of: ",", with: ".")) }
                .reduce(0, +)
            let targetPct = fragranceTargetPercentage

            let base: Double?
            switch unit {
            case "% of oils":
                let totalOil = Double(totalOilWeight.replacingOccurrences(of: ",", with: ".")) ?? 0
                base = totalOil > 0 ? totalOil : nil
            case "% of batch":
                if let calcs = oilAmountCalculations,
                   let lye = calculatedLyeAmount,
                   let water = calculatedWaterAmount {
                    base = calcs.reduce(0.0) { $0 + $1.weight } + lye + water
                } else { base = nil }
            case "% of liquids":
                if let lye = calculatedLyeAmount, let water = calculatedWaterAmount {
                    base = lye + water
                } else { base = nil }
            default: base = nil
            }

            if let base, base > 0 {
                let fmt = { (v: Double) -> String in
                    "\(v.formatted(.number.precision(.fractionLength(0...2)))) g"
                }
                let currentGrams = sumPct / 100 * base
                if unit == "% of oils" {
                    let targetGrams = targetPct / 100 * base
                    return FragranceIndicator(
                        currentText: fmt(currentGrams),
                        targetText: fmt(targetGrams),
                        isOverTarget: currentGrams > targetGrams * 1.005
                    )
                } else {
                    return FragranceIndicator(currentText: fmt(currentGrams), targetText: nil, isOverTarget: false)
                }
            } else {
                let sumText = formatPercentage(sumPct) + "%"
                return FragranceIndicator(currentText: sumText, targetText: nil, isOverTarget: false)
            }
        }

        let absoluteUnits: Set<String> = ["g", "kg", "oz"]
        if let unit, absoluteUnits.contains(unit), unit == oilWeightUnit {
            let totalOil = Double(totalOilWeight.replacingOccurrences(of: ",", with: ".")) ?? 0
            guard totalOil > 0 else { return nil }
            let target = totalOil * fragranceTargetPercentage / 100
            let sum = fragranceDrafts
                .compactMap { Double($0.amount.replacingOccurrences(of: ",", with: ".")) }
                .reduce(0, +)
            let fmt = { (v: Double) -> String in
                v.formatted(.number.precision(.fractionLength(0...2)))
            }
            return FragranceIndicator(
                currentText: fmt(sum),
                targetText: "\(fmt(target)) \(unit)",
                isOverTarget: sum > target * 1.005
            )
        }

        return nil
    }

    private var lyeConcentration: Double {
        let wp = Double(waterParts.replacingOccurrences(of: ",", with: ".")) ?? 1.5
        return 1.0 / (1.0 + wp)
    }

    var extraIngredientData: (sectionA: [ExtraSectionARow], sectionB: [ExtraSectionBRow])? {
        guard let calculations = oilAmountCalculations,
              let totalLye = calculatedLyeAmount,
              let totalWater = calculatedWaterAmount else { return nil }

        let oils = calculations.reduce(0.0) { $0 + $1.weight }
        guard oils > 0 else { return nil }

        let lyeConc = lyeConcentration
        let batchTotal = oils + totalLye + totalWater

        let citric1 = oils * 0.01
        let citric2 = oils * 0.02
        let citric3 = oils * 0.03
        let sectionA: [ExtraSectionARow] = [
            ExtraSectionARow(label: "Sodium Lactate (60%)", val1: oils * 0.01, val2: oils * 0.02, val3: oils * 0.03),
            ExtraSectionARow(
                label: "Citric Acid Powder",
                val1: citric1, val2: citric2, val3: citric3,
                naohLyeSolution: (
                    v1: citric1 * 0.625 / lyeConc,
                    v2: citric2 * 0.625 / lyeConc,
                    v3: citric3 * 0.625 / lyeConc
                )
            ),
        ]

        let ascorbic = oils * 0.01
        let lactic = oils * 0.0075
        let sectionB: [ExtraSectionBRow] = [
            ExtraSectionBRow(label: "EO / Fragrance Oil", minValue: oils * fragranceTargetPercentage / 100),
            ExtraSectionBRow(label: "Ascorbic Acid", minValue: ascorbic, naohLyeSolution: ascorbic * 0.2020 / lyeConc),
            ExtraSectionBRow(label: "Lactic Acid", minValue: lactic, naohLyeSolution: lactic * 0.5920 / lyeConc),
            ExtraSectionBRow(label: "Tetrasodium EDTA", minValue: batchTotal * 0.005),
            ExtraSectionBRow(label: "Sodium Citrate", minValue: oils * 0.013, maxValue: oils * 0.039),
            ExtraSectionBRow(label: "Potassium Citrate", minValue: oils * 0.016, maxValue: oils * 0.048),
            ExtraSectionBRow(label: "Rosemary Oleoresin (ROE)", minValue: oils * 0.0004, maxValue: oils * 0.0005),
        ]

        return (sectionA, sectionB)
    }

    func load(from recipe: Recipe) {
        editingRecipe = recipe
        name = recipe.name
        desc = recipe.desc
        weightUnit = recipe.weightUnit
        totalOilWeight = recipe.totalOilWeight > 0 ? format(recipe.totalOilWeight) : ""
        oilWeightUnit = recipe.oilWeightUnit
        lyeType = recipe.lyeType
        lyePurity = format(recipe.lyePurity)
        waterParts = format(recipe.waterParts)
        superFat = format(recipe.superFat)
        fragrancePercentage = format(recipe.fragrancePercentage)

        oilDrafts = recipe.ingredients
            .filter { $0.ingredientRole == .oil }
            .map {
                let amount = recipe.weightUnit == "%" ? formatPercentage($0.percentage) : format($0.percentage)
                return OilIngredientDraft(ingredient: $0.ingredient, amount: amount, isLocked: true)
            }
        additiveDrafts = recipe.ingredients
            .filter { $0.ingredientRole == .additive }
            .map { IngredientAmountDraft(ingredient: $0.ingredient, amount: format($0.additiveAmount), unit: $0.additiveUnit) }
        fragranceDrafts = recipe.ingredients
            .filter { $0.ingredientRole == .fragrance }
            .map { IngredientAmountDraft(ingredient: $0.ingredient, amount: format($0.additiveAmount), unit: $0.additiveUnit) }

        productDrafts = recipe.products.map {
            RecipeProductDraft(size: format($0.size), unitSymbol: $0.unitSymbol)
        }
    }

    func addOil(_ ingredient: Ingredient) {
        guard !oilDrafts.contains(where: {
            $0.ingredient.persistentModelID == ingredient.persistentModelID
        }) else { return }
        oilDrafts.append(OilIngredientDraft(ingredient: ingredient))
        if weightUnitIsPercentage { redistributePercentages() }
    }

    func removeOil(at offsets: IndexSet) {
        oilDrafts.remove(atOffsets: offsets)
        if weightUnitIsPercentage { redistributePercentages() }
    }

    func userEdited(id: UUID, amount: String) {
        guard let idx = oilDrafts.firstIndex(where: { $0.id == id }) else { return }
        oilDrafts[idx].amount = amount
        if weightUnitIsPercentage {
            oilDrafts[idx].isLocked = true
            redistributePercentages()
        }
    }

    func addAdditive(_ ingredient: Ingredient) {
        guard !additiveDrafts.contains(where: {
            $0.ingredient.persistentModelID == ingredient.persistentModelID
        }) else { return }
        additiveDrafts.append(IngredientAmountDraft(ingredient: ingredient, unit: "g"))
    }

    func removeAdditive(at offsets: IndexSet) {
        additiveDrafts.remove(atOffsets: offsets)
    }

    func updateAdditive(id: UUID, amount: String? = nil, unit: String? = nil) {
        guard let idx = additiveDrafts.firstIndex(where: { $0.id == id }) else { return }
        if let amount { additiveDrafts[idx].amount = amount }
        if let unit { additiveDrafts[idx].unit = unit }
    }

    func addFragrance(_ ingredient: Ingredient) {
        guard !fragranceDrafts.contains(where: {
            $0.ingredient.persistentModelID == ingredient.persistentModelID
        }) else { return }
        let unit = fragranceUnitIsPercentageOfOils ? "% of oils" : "g"
        fragranceDrafts.append(IngredientAmountDraft(ingredient: ingredient, unit: unit))
        if fragranceUnitIsPercentageOfOils { redistributeFragrancePercentages() }
    }

    func removeFragrance(at offsets: IndexSet) {
        fragranceDrafts.remove(atOffsets: offsets)
        if fragranceUnitIsPercentageOfOils { redistributeFragrancePercentages() }
    }

    func updateFragrance(id: UUID, amount: String? = nil, unit: String? = nil) {
        guard let idx = fragranceDrafts.firstIndex(where: { $0.id == id }) else { return }
        if let amount { fragranceDrafts[idx].amount = amount }
        if let unit {
            fragranceDrafts[idx].unit = unit
            fragranceDrafts.indices.forEach { fragranceDrafts[$0].isLocked = false }
            if unit == "% of oils" { redistributeFragrancePercentages() }
        }
    }

    func userEditedFragrance(id: UUID, amount: String) {
        guard let idx = fragranceDrafts.firstIndex(where: { $0.id == id }) else { return }
        fragranceDrafts[idx].amount = amount
        fragranceDrafts[idx].isLocked = true
        redistributeFragrancePercentages()
    }

    private var fragranceUnitIsPercentageOfOils: Bool {
        fragranceDrafts.first?.unit == "% of oils"
    }

    private func redistributeFragrancePercentages() {
        let target = fragranceTargetPercentage
        let lockedSum = fragranceDrafts
            .filter(\.isLocked)
            .compactMap { Double($0.amount.replacingOccurrences(of: ",", with: ".")) }
            .reduce(0, +)
        let remaining = max(0, target - lockedSum)
        let unlockedIndices = fragranceDrafts.indices.filter { !fragranceDrafts[$0].isLocked }
        guard !unlockedIndices.isEmpty else { return }
        let share = remaining / Double(unlockedIndices.count)
        for (enumIdx, idx) in unlockedIndices.enumerated() {
            if enumIdx == unlockedIndices.count - 1 {
                let assignedSum = unlockedIndices.dropLast()
                    .compactMap { Double(fragranceDrafts[$0].amount.replacingOccurrences(of: ",", with: ".")) }
                    .reduce(0, +)
                fragranceDrafts[idx].amount = formatPercentage(max(0, remaining - assignedSum))
            } else {
                fragranceDrafts[idx].amount = formatPercentage(share)
            }
        }
    }

    func addProduct(defaultUnitSymbol: String) {
        productDrafts.append(RecipeProductDraft(unitSymbol: defaultUnitSymbol))
    }

    func breakdownAndCost(for product: RecipeProductDraft) -> (breakdown: [IngredientProductBreakdown], total: Double) {
        let size = Double(product.size.replacingOccurrences(of: ",", with: ".")) ?? 0
        let breakdown: [IngredientProductBreakdown]
        if weightUnitIsPercentage {
            breakdown = oilDrafts.map { draft in
                let pct = Double(draft.amount.replacingOccurrences(of: ",", with: ".")) ?? 0
                let ingredientAmount = size * (pct / 100)
                let costPer = weightedCostPerUnit(for: draft.ingredient)
                return IngredientProductBreakdown(ingredient: draft.ingredient, ingredientAmount: ingredientAmount, cost: ingredientAmount * costPer)
            }
        } else {
            let totalOilWeight = oilDrafts
                .compactMap { Double($0.amount.replacingOccurrences(of: ",", with: ".")) }
                .reduce(0, +)
            breakdown = oilDrafts.map { draft in
                let oilWeight = Double(draft.amount.replacingOccurrences(of: ",", with: ".")) ?? 0
                let share = totalOilWeight > 0 ? oilWeight / totalOilWeight : 0
                let ingredientAmount = size * share
                let costPer = weightedCostPerUnit(for: draft.ingredient)
                return IngredientProductBreakdown(ingredient: draft.ingredient, ingredientAmount: ingredientAmount, cost: ingredientAmount * costPer)
            }
        }
        return (breakdown, breakdown.reduce(0) { $0 + $1.cost })
    }

    private func weightedCostPerUnit(for ingredient: Ingredient) -> Double {
        let batches = ingredient.batches.filter { $0.quantity > 0 }
        guard !batches.isEmpty else { return 0 }
        let totalCost = batches.reduce(0.0) { $0 + $1.totalPrice }
        let totalQty = batches.reduce(0.0) { $0 + $1.quantity }
        return totalQty > 0 ? totalCost / totalQty : 0
    }

    private func redistributePercentages() {
        let lockedSum = oilDrafts
            .filter(\.isLocked)
            .compactMap { Double($0.amount.replacingOccurrences(of: ",", with: ".")) }
            .reduce(0, +)
        let remaining = max(0, 100 - lockedSum)
        let unlockedIndices = oilDrafts.indices.filter { !oilDrafts[$0].isLocked }
        guard !unlockedIndices.isEmpty else { return }
        let share = remaining / Double(unlockedIndices.count)
        for (enumIdx, idx) in unlockedIndices.enumerated() {
            if enumIdx == unlockedIndices.count - 1 {
                let assignedSum = unlockedIndices.dropLast()
                    .compactMap { Double(oilDrafts[$0].amount.replacingOccurrences(of: ",", with: ".")) }
                    .reduce(0, +)
                oilDrafts[idx].amount = formatPercentage(max(0, remaining - assignedSum))
            } else {
                oilDrafts[idx].amount = formatPercentage(share)
            }
        }
    }

    private static let percentageFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = .autoupdatingCurrent
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 1
        return f
    }()

    func formatPercentage(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return Self.percentageFormatter.string(from: NSNumber(value: rounded)) ?? "0"
    }

    @discardableResult
    func save(context: ModelContext) -> Recipe {
        let recipe: Recipe
        if let existing = editingRecipe {
            recipe = existing
        } else {
            recipe = Recipe(name: "", desc: "")
            context.insert(recipe)
        }
        recipe.name = name.trimmingCharacters(in: .whitespaces)
        recipe.desc = desc.trimmingCharacters(in: .whitespaces)
        recipe.weightUnit = weightUnit
        recipe.totalOilWeight = Double(totalOilWeight.replacingOccurrences(of: ",", with: ".")) ?? 0
        recipe.oilWeightUnit = oilWeightUnit
        recipe.lyeType = lyeType
        recipe.lyePurity = Double(lyePurity.replacingOccurrences(of: ",", with: ".")) ?? 99
        recipe.waterParts = Double(waterParts.replacingOccurrences(of: ",", with: ".")) ?? 1.5
        recipe.superFat = Double(superFat.replacingOccurrences(of: ",", with: ".")) ?? 5
        recipe.fragrancePercentage = Double(fragrancePercentage.replacingOccurrences(of: ",", with: ".")) ?? 3

        recipe.ingredients.forEach { context.delete($0) }

        for draft in oilDrafts {
            let pct = Double(draft.amount.replacingOccurrences(of: ",", with: ".")) ?? 0
            let ri = RecipeIngredient(ingredient: draft.ingredient, percentage: pct, role: .oil)
            ri.recipe = recipe
            context.insert(ri)
        }
        for draft in additiveDrafts {
            let ri = RecipeIngredient(ingredient: draft.ingredient, percentage: 0, role: .additive)
            ri.additiveAmount = Double(draft.amount.replacingOccurrences(of: ",", with: ".")) ?? 0
            ri.additiveUnit = draft.unit
            ri.recipe = recipe
            context.insert(ri)
        }
        for draft in fragranceDrafts {
            let ri = RecipeIngredient(ingredient: draft.ingredient, percentage: 0, role: .fragrance)
            ri.additiveAmount = Double(draft.amount.replacingOccurrences(of: ",", with: ".")) ?? 0
            ri.additiveUnit = draft.unit
            ri.recipe = recipe
            context.insert(ri)
        }

        recipe.products.forEach { context.delete($0) }
        for draft in productDrafts {
            let size = Double(draft.size.replacingOccurrences(of: ",", with: ".")) ?? 0
            let rp = RecipeProduct(size: size, unitSymbol: draft.unitSymbol)
            rp.recipe = recipe
            context.insert(rp)
        }
        return recipe
    }

    private func format(_ value: Double) -> String {
        Self.percentageFormatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
