import SwiftUI
import SwiftData

struct OilIngredientDraft: Identifiable {
    let id = UUID()
    let ingredient: Ingredient
    var amount: Double = 0
    var isLocked: Bool = false
}

struct IngredientAmountDraft: Identifiable {
    let id = UUID()
    let ingredient: Ingredient
    var amount: Double = 0
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
    var size: Double = 0
    var unitSymbol: String = ""
}

struct IngredientProductBreakdown {
    let ingredient: Ingredient
    let ingredientAmount: Double
    let cost: Double
}

struct ProductCostBreakdown {
    var oils: [IngredientProductBreakdown] = []
    var additives: [IngredientProductBreakdown] = []
    var fragrances: [IngredientProductBreakdown] = []
    var lye: [IngredientProductBreakdown] = []
    var total: Double = 0
    var exceedsBatchWeight: Bool = false
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
    var totalOilWeight: Double = 1000
    var oilWeightUnit: String = "g"
    var lyeType: String = "NaOH"
    var lyePurity: Double = 99
    var waterParts: Double = 1.5
    var superFat: Double = 5
    var oilDrafts: [OilIngredientDraft] = []
    var additiveDrafts: [IngredientAmountDraft] = []
    var fragranceDrafts: [IngredientAmountDraft] = []
    var productDrafts: [RecipeProductDraft] = []
    var fragrancePercentage: Double = 3
    var lyeIngredient: Ingredient?

    @ObservationIgnored
    private var editingRecipe: Recipe?

    init() {
        productDrafts = [Self.defaultProductDraft()]
    }

    private static func defaultProductDraft() -> RecipeProductDraft {
        RecipeProductDraft(size: 1, unitSymbol: ProductUnit.partsOfBatch.rawValue)
    }

    var weightUnitIsPercentage: Bool { weightUnit == "%" }

    var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var totalPercentage: Double {
        oilDrafts.reduce(0) { $0 + $1.amount }
    }

    var totalPercentageText: String { formatPercentage(totalPercentage) }

    var displayWeightUnit: String {
        weightUnitIsPercentage ? oilWeightUnit : weightUnit
    }

    var oilAmountCalculations: [OilAmountCalculation]? {
        guard !oilDrafts.isEmpty else { return nil }
        guard lyePurity > 0 && lyePurity <= 100 else { return nil }

        if weightUnitIsPercentage {
            guard totalOilWeight > 0 else { return nil }
            return oilDrafts.map { draft in
                let oilWeight = totalOilWeight * (draft.amount / 100)
                let sap = draft.ingredient.sapValue ?? 0
                let lye = oilWeight * sap * (1 - superFat / 100) / (lyePurity / 100)
                return OilAmountCalculation(id: draft.id, ingredient: draft.ingredient, weight: oilWeight, lye: lye)
            }
        } else {
            let calcs = oilDrafts.compactMap { draft -> OilAmountCalculation? in
                guard draft.amount > 0 else { return nil }
                let sap = draft.ingredient.sapValue ?? 0
                let lye = draft.amount * sap * (1 - superFat / 100) / (lyePurity / 100)
                return OilAmountCalculation(id: draft.id, ingredient: draft.ingredient, weight: draft.amount, lye: lye)
            }
            return calcs.isEmpty ? nil : calcs
        }
    }

    var calculatedLyeAmount: Double? {
        oilAmountCalculations.map { $0.reduce(0) { $0 + $1.lye } }
    }

    var calculatedWaterAmount: Double? {
        guard let lye = calculatedLyeAmount else { return nil }
        return lye * waterParts
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
        rows.append(CalculatedAmountRow(
            label: "\(lyeType) (\(formatPercentage(lyePurity))%, \(formatPercentage(superFat))% SF)",
            weight: totalLye, pct: batchPct(totalLye), isSummary: false
        ))
        rows.append(CalculatedAmountRow(
            label: "Water (\(formatPercentage(waterParts)):1)",
            weight: totalWater, pct: batchPct(totalWater), isSummary: false
        ))
        rows.append(CalculatedAmountRow(label: "Batch total", weight: batchTotal, pct: 100, isSummary: true))
        return rows
    }

    var fragranceTargetPercentage: Double { fragrancePercentage }

    var fragranceIndicator: FragranceIndicator? {
        guard !fragranceDrafts.isEmpty else { return nil }

        let units = Set(fragranceDrafts.map(\.unit))
        let unit = units.count == 1 ? fragranceDrafts[0].unit : nil

        let percentageUnits: Set<String> = ["% of oils", "% of batch", "% of liquids"]

        if let unit, percentageUnits.contains(unit) {
            let sumPct = fragranceDrafts.reduce(0) { $0 + $1.amount }
            let targetPct = fragranceTargetPercentage

            let base: Double?
            switch unit {
            case "% of oils":
                base = totalOilWeight > 0 ? totalOilWeight : nil
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
            guard totalOilWeight > 0 else { return nil }
            let target = totalOilWeight * fragranceTargetPercentage / 100
            let sum = fragranceDrafts.reduce(0) { $0 + $1.amount }
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
        1.0 / (1.0 + waterParts)
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
        totalOilWeight = recipe.totalOilWeight
        oilWeightUnit = recipe.oilWeightUnit
        lyeType = recipe.lyeType
        lyePurity = recipe.lyePurity
        waterParts = recipe.waterParts
        superFat = recipe.superFat
        fragrancePercentage = recipe.fragrancePercentage
        lyeIngredient = recipe.lyeIngredient

        oilDrafts = recipe.ingredients
            .filter { $0.ingredientRole == .oil }
            .map {
                return OilIngredientDraft(ingredient: $0.ingredient, amount: $0.percentage, isLocked: true)
            }
        additiveDrafts = recipe.ingredients
            .filter { $0.ingredientRole == .additive }
            .map { IngredientAmountDraft(ingredient: $0.ingredient, amount: $0.additiveAmount, unit: $0.additiveUnit) }
        fragranceDrafts = recipe.ingredients
            .filter { $0.ingredientRole == .fragrance }
            .map { IngredientAmountDraft(ingredient: $0.ingredient, amount: $0.additiveAmount, unit: $0.additiveUnit) }

        productDrafts = recipe.products.map {
            RecipeProductDraft(size: $0.size, unitSymbol: $0.unitSymbol)
        }
        if productDrafts.isEmpty {
            productDrafts = [Self.defaultProductDraft()]
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

    func userEdited(id: UUID, amount: Double) {
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

    func updateAdditive(id: UUID, amount: Double? = nil, unit: String? = nil) {
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

    func updateFragrance(id: UUID, amount: Double? = nil, unit: String? = nil) {
        guard let idx = fragranceDrafts.firstIndex(where: { $0.id == id }) else { return }
        if let amount { fragranceDrafts[idx].amount = amount }
        if let unit {
            fragranceDrafts[idx].unit = unit
            fragranceDrafts.indices.forEach { fragranceDrafts[$0].isLocked = false }
            if unit == "% of oils" { redistributeFragrancePercentages() }
        }
    }

    func userEditedFragrance(id: UUID, amount: Double) {
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
        let lockedSum = fragranceDrafts.filter(\.isLocked).reduce(0) { $0 + $1.amount }
        let remaining = max(0, target - lockedSum)
        let unlockedIndices = fragranceDrafts.indices.filter { !fragranceDrafts[$0].isLocked }
        guard !unlockedIndices.isEmpty else { return }
        let share = (remaining / Double(unlockedIndices.count) * 10).rounded() / 10
        for (enumIdx, idx) in unlockedIndices.enumerated() {
            if enumIdx == unlockedIndices.count - 1 {
                let assignedSum = unlockedIndices.dropLast().reduce(0.0) { $0 + fragranceDrafts[$1].amount }
                fragranceDrafts[idx].amount = max(0, remaining - assignedSum)
            } else {
                fragranceDrafts[idx].amount = share
            }
        }
    }

    func addProduct(defaultUnitSymbol: String) {
        productDrafts.append(RecipeProductDraft(unitSymbol: defaultUnitSymbol))
    }

    func breakdownAndCost(for product: RecipeProductDraft) -> ProductCostBreakdown {
        let batch = wholeBatchBreakdown
        let unit = ProductUnit(rawValue: product.unitSymbol)
        if unit == .wholeBatch {
            return scaleBreakdown(batch, by: 1)
        }
        let size = product.size
        guard size > 0 else { return ProductCostBreakdown() }

        if unit == .partsOfBatch {
            return scaleBreakdown(batch, by: 1 / size)
        }
        guard let unit, let perUnit = unit.gramsPerUnit else { return ProductCostBreakdown() }
        let productGrams = perUnit * size
        let batchGrams = batchTotalGrams(from: batch)
        let rawShare = batchGrams > 0 ? productGrams / batchGrams : 0
        var result = scaleBreakdown(batch, by: min(rawShare, 1))
        result.exceedsBatchWeight = rawShare > 1
        return result
    }

    var wholeBatchBreakdown: ProductCostBreakdown {
        let oils = oilBatchBreakdown
        let additives = additiveBatchBreakdown
        let fragrances = fragranceBatchBreakdown
        let lye = lyeBatchBreakdown
        let total = (oils + additives + fragrances + lye).reduce(0) { $0 + $1.cost }
        return ProductCostBreakdown(oils: oils, additives: additives, fragrances: fragrances, lye: lye, total: total)
    }

    var batchTotalCost: Double { wholeBatchBreakdown.total }

    var hasIngredients: Bool {
        !oilDrafts.isEmpty || !additiveDrafts.isEmpty || !fragranceDrafts.isEmpty
    }

    private var oilBatchBreakdown: [IngredientProductBreakdown] {
        guard let calcs = oilAmountCalculations else { return [] }
        return calcs.map { calc in
            let costPer = weightedCostPerUnit(for: calc.ingredient)
            return IngredientProductBreakdown(
                ingredient: calc.ingredient,
                ingredientAmount: calc.weight,
                cost: calc.weight * costPer
            )
        }
    }

    private var additiveBatchBreakdown: [IngredientProductBreakdown] {
        additiveDrafts.compactMap { draft in
            guard draft.amount > 0, let grams = massGrams(amount: draft.amount, unitSymbol: draft.unit) else { return nil }
            let costPer = weightedCostPerUnit(for: draft.ingredient)
            return IngredientProductBreakdown(
                ingredient: draft.ingredient,
                ingredientAmount: grams,
                cost: grams * costPer
            )
        }
    }

    private var fragranceBatchBreakdown: [IngredientProductBreakdown] {
        fragranceDrafts.compactMap { draft in
            guard draft.amount > 0, let grams = fragranceGrams(amount: draft.amount, unit: draft.unit) else { return nil }
            let costPer = weightedCostPerUnit(for: draft.ingredient)
            return IngredientProductBreakdown(
                ingredient: draft.ingredient,
                ingredientAmount: grams,
                cost: grams * costPer
            )
        }
    }

    private var lyeBatchBreakdown: [IngredientProductBreakdown] {
        guard let ingredient = lyeIngredient, let grams = calculatedLyeAmount, grams > 0 else { return [] }
        let costPer = weightedCostPerUnit(for: ingredient)
        return [IngredientProductBreakdown(ingredient: ingredient, ingredientAmount: grams, cost: grams * costPer)]
    }

    private var totalOilGrams: Double {
        oilAmountCalculations?.reduce(0) { $0 + $1.weight } ?? 0
    }

    private func batchTotalGrams(from batch: ProductCostBreakdown) -> Double {
        let additives = batch.additives.reduce(0) { $0 + $1.ingredientAmount }
        let fragrances = batch.fragrances.reduce(0) { $0 + $1.ingredientAmount }
        let lye = calculatedLyeAmount ?? 0
        let water = calculatedWaterAmount ?? 0
        return totalOilGrams + additives + fragrances + lye + water
    }

    private func scaleBreakdown(_ source: ProductCostBreakdown, by factor: Double) -> ProductCostBreakdown {
        func scale(_ rows: [IngredientProductBreakdown]) -> [IngredientProductBreakdown] {
            rows.map {
                IngredientProductBreakdown(
                    ingredient: $0.ingredient,
                    ingredientAmount: $0.ingredientAmount * factor,
                    cost: $0.cost * factor
                )
            }
        }
        let oils = scale(source.oils)
        let additives = scale(source.additives)
        let fragrances = scale(source.fragrances)
        let lye = scale(source.lye)
        let total = (oils + additives + fragrances + lye).reduce(0) { $0 + $1.cost }
        return ProductCostBreakdown(oils: oils, additives: additives, fragrances: fragrances, lye: lye, total: total)
    }

    private func massGrams(amount: Double, unitSymbol: String) -> Double? {
        switch unitSymbol {
        case "g": amount
        case "kg": amount * 1000
        case "oz": amount * 28.3495
        case "lb": amount * 453.592
        default: nil
        }
    }

    private func fragranceGrams(amount: Double, unit: String) -> Double? {
        if let grams = massGrams(amount: amount, unitSymbol: unit) { return grams }
        let pct = amount / 100
        switch unit {
        case "% of oils":
            return totalOilGrams > 0 ? totalOilGrams * pct : nil
        case "% of batch":
            guard let lye = calculatedLyeAmount, let water = calculatedWaterAmount else { return nil }
            return (totalOilGrams + lye + water) * pct
        case "% of liquids":
            guard let lye = calculatedLyeAmount, let water = calculatedWaterAmount else { return nil }
            return (lye + water) * pct
        default: return nil
        }
    }

    func resolveDefaultLyeIngredient(from inventory: [Ingredient]) {
        guard lyeIngredient == nil else { return }
        let lyeName: String
        switch lyeType {
        case "NaOH": lyeName = "sodium hydroxide"
        case "KOH": lyeName = "potassium hydroxide"
        default: return
        }
        let candidates = inventory.filter { $0.category?.name == IngredientCategory.Name.lyes }
        lyeIngredient = candidates.first { $0.name.lowercased().contains(lyeName) }
            ?? candidates.first
    }

    private func weightedCostPerUnit(for ingredient: Ingredient) -> Double {
        let batches = ingredient.batches.filter { $0.quantity > 0 }
        guard !batches.isEmpty else { return 0 }
        let totalCost = batches.reduce(0.0) { $0 + $1.totalPrice }
        let totalQty = batches.reduce(0.0) { $0 + $1.quantity }
        return totalQty > 0 ? totalCost / totalQty : 0
    }

    private func redistributePercentages() {
        let lockedSum = oilDrafts.filter(\.isLocked).reduce(0) { $0 + $1.amount }
        let remaining = max(0, 100 - lockedSum)
        let unlockedIndices = oilDrafts.indices.filter { !oilDrafts[$0].isLocked }
        guard !unlockedIndices.isEmpty else { return }
        let share = (remaining / Double(unlockedIndices.count) * 10).rounded() / 10
        for (enumIdx, idx) in unlockedIndices.enumerated() {
            if enumIdx == unlockedIndices.count - 1 {
                let assignedSum = unlockedIndices.dropLast().reduce(0.0) { $0 + oilDrafts[$1].amount }
                oilDrafts[idx].amount = max(0, remaining - assignedSum)
            } else {
                oilDrafts[idx].amount = share
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
        recipe.totalOilWeight = totalOilWeight
        recipe.oilWeightUnit = oilWeightUnit
        recipe.lyeType = lyeType
        recipe.lyePurity = lyePurity
        recipe.waterParts = waterParts
        recipe.superFat = superFat
        recipe.fragrancePercentage = fragrancePercentage
        recipe.lyeIngredient = lyeIngredient

        recipe.ingredients.forEach { context.delete($0) }

        for draft in oilDrafts {
            let ri = RecipeIngredient(ingredient: draft.ingredient, percentage: draft.amount, role: .oil)
            ri.recipe = recipe
            context.insert(ri)
        }
        for draft in additiveDrafts {
            let ri = RecipeIngredient(ingredient: draft.ingredient, percentage: 0, role: .additive)
            ri.additiveAmount = draft.amount
            ri.additiveUnit = draft.unit
            ri.recipe = recipe
            context.insert(ri)
        }
        for draft in fragranceDrafts {
            let ri = RecipeIngredient(ingredient: draft.ingredient, percentage: 0, role: .fragrance)
            ri.additiveAmount = draft.amount
            ri.additiveUnit = draft.unit
            ri.recipe = recipe
            context.insert(ri)
        }

        recipe.products.forEach { context.delete($0) }
        for draft in productDrafts {
            let rp = RecipeProduct(size: draft.size, unitSymbol: draft.unitSymbol)
            rp.recipe = recipe
            context.insert(rp)
        }
        return recipe
    }
}
