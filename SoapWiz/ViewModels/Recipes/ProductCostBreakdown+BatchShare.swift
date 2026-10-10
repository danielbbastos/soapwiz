import Foundation

extension ProductCostBreakdown {
    /// How many whole products of this size one batch yields, or nil when the
    /// size isn't a weight or is larger than the batch.
    var sizesPerBatch: Int? {
        guard let batchShare, batchShare > 0 else { return nil }
        // The tolerance keeps an exact division, such as 1 / 0.2, from
        // flooring to one less through floating-point error.
        let count = Int((1 / batchShare + 1e-9).rounded(.down))
        return count >= 1 ? count : nil
    }
}
