import Foundation

/// What the import screens read to decide what to offer: whether text can be
/// read, what it carries, and whether the review can be confirmed.
extension RecipeImportViewModel {
    var canExtract: Bool {
        !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && phase != .extracting
    }

    /// Whether the text in the box is an exact payload.
    ///
    /// Lets the input screen say what will happen before the user commits to it:
    /// pasting a SoapWiz recipe is about to be read exactly, not interpreted.
    var textCarriesExactPayload: Bool {
        if case .payload = RecipeTransferDecoder.scan(text: rawText) { return true }
        return false
    }

    /// Whether the text in the box is SoapWiz's own readable copy, which is
    /// read without the model.
    var textIsSoapWizCopy: Bool { RecipeTextExportReader.read(rawText) != nil }

    var isExtracting: Bool { phase == .extracting }

    var unresolvedCount: Int { rows.count { !$0.isResolved } }

    var canConfirm: Bool {
        phase == .review && unresolvedCount == 0 && rows.contains { $0.role == .oil && $0.ingredient != nil }
    }

    /// The reason confirming isn't possible yet, or `nil` when it is. An import
    /// with no resolved oil would produce a recipe with nothing to saponify.
    var confirmBlocker: String? {
        guard phase == .review else { return nil }
        if unresolvedCount > 0 {
            return unresolvedCount == 1
                ? "One ingredient still needs to be created or skipped."
                : "\(unresolvedCount) ingredients still need to be created or skipped."
        }
        if !rows.contains(where: { $0.role == .oil && $0.ingredient != nil }) {
            return "A recipe needs at least one oil from your inventory."
        }
        return nil
    }
}
