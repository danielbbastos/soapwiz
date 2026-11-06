import Foundation

/// One kind of product a batch made: `count` of them, each of `size`. Recorded
/// by the maker and editable afterwards, so it sits beside the immutable
/// snapshot rather than in it. A recipe's sizes are pricing alternatives; this
/// is what was actually made.
struct BatchProduct: Codable, Hashable, Identifiable {
    var id = UUID()
    /// Greater than zero.
    var size: Double
    /// Raw value of a `ProductUnit`: a mass unit or parts of a batch, never a
    /// whole batch.
    var unitSymbol: String
    /// At least one.
    var count: Int

    /// "100 g × 18".
    var quantityLabel: String {
        Self.quantityLabel(size: size, unitSymbol: unitSymbol, count: count)
    }

    static func quantityLabel(size: Double, unitSymbol: String, count: Int) -> String {
        "\(label(size: size, unitSymbol: unitSymbol)) × \(count)"
    }

    /// "100 g", "14 parts".
    static func label(size: Double, unitSymbol: String) -> String {
        let number = size.formatted(.number.precision(.fractionLength(0...2)))
        if ProductUnit(rawValue: unitSymbol) == .partsOfBatch {
            return "\(number) parts"
        }
        return "\(number) \(unitSymbol)"
    }

    static func isValid(size: Double, unitSymbol: String, count: Int) -> Bool {
        guard size.isFinite, size > 0, count >= 1 else { return false }
        switch ProductUnit(rawValue: unitSymbol) {
        case .grams, .kilograms, .ounces, .pounds:
            return true
        case .partsOfBatch:
            return ProductUnit.isSeparateFromBatch(size: size, unitSymbol: unitSymbol)
        case .wholeBatch, nil:
            return false
        }
    }

    /// How many products of this size a run of `batchCount` batches makes, each
    /// batch weighing `oneBatchWeight` in `weightUnit`. Every batch goes in its
    /// own moulds, so the leftover of one never combines with the next: two
    /// batches of 950 g cut at 100 g make 18, not 19. Parts of a batch are the
    /// parts times the batch count. `nil` when the size is larger than one
    /// batch, the weight or size isn't usable, or the unit isn't a size to make.
    static func estimatedCount(
        size: Double,
        unitSymbol: String,
        oneBatchWeight: Double,
        weightUnit: String,
        batchCount: Int
    ) -> Int? {
        guard size.isFinite, size > 0, batchCount >= 1 else { return nil }
        let limit = Double(Int32.max)
        switch ProductUnit(rawValue: unitSymbol) {
        case .partsOfBatch:
            guard ProductUnit.isSeparateFromBatch(size: size, unitSymbol: unitSymbol), size < limit else { return nil }
            return Int(size) * batchCount
        case .grams, .kilograms, .ounces, .pounds:
            guard let sizeUnit = ProductUnit(rawValue: unitSymbol),
                  let sizeGrams = sizeUnit.gramsPerUnit,
                  let weightGrams = ProductUnit(rawValue: weightUnit)?.gramsPerUnit,
                  oneBatchWeight.isFinite, oneBatchWeight > 0 else { return nil }
            // The tolerance keeps an exact division, such as 1000 / 200,
            // from flooring to one less through floating-point error.
            let ratio = oneBatchWeight * weightGrams / (size * sizeGrams)
            guard ratio.isFinite, ratio < limit else { return nil }
            let perBatch = Int((ratio + 1e-9).rounded(.down))
            return perBatch >= 1 ? perBatch * batchCount : nil
        case .wholeBatch, nil:
            return nil
        }
    }
}
