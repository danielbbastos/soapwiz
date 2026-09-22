#if DEBUG
import Foundation

/// Debug-only escape hatch for exercising the import UI where the on-device
/// model cannot run — the simulator, or a device without Apple Intelligence.
///
/// Opt-in via a launch argument rather than on whenever `DEBUG` is set. A debug
/// build on an eligible iPad has to keep using the real model, otherwise the one
/// thing that can only be tested on a device silently stops being tested there.
///
/// Set it in a scheme's run arguments, or pass it to `simctl launch`.
enum RecipeImportDebugOverride {
    static let launchArgument = "-SoapWizStubRecipeImport"

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(launchArgument)
    }
}

/// A fixed draft, so the paste → review → recipe flow can be walked end to end
/// without Apple Intelligence.
///
/// The contents are chosen to reach every branch of the review screen against
/// the seeded inventory: three oils and a fragrance that resolve, plus an oil
/// and an additive that do not, so the create-or-skip path is reachable.
/// `Kokum Butter` and `Sodium Citrate` are deliberately absent from
/// `TestIngredients.json` — check there before changing either name, or the
/// unmatched branch stops being reachable.
struct CannedRecipeExtractor: RecipeDraftExtracting {
    func extract(from text: SanitizedRecipeText) async throws -> RecipeImportDraft {
        guard !text.isEmpty else { throw RecipeImportError.nothingRecognised }
        // Long enough that the progress state is visible rather than a flicker.
        try? await Task.sleep(for: .milliseconds(800))
        return RecipeImportDraft(
            name: "Stubbed Import",
            desc: "",
            oils: [
                ImportedIngredient(name: "Olive Oil", amount: 55, unit: nil),
                ImportedIngredient(name: "Coconut Oil", amount: 25, unit: nil),
                ImportedIngredient(name: "Castor Oil", amount: 5, unit: nil),
                ImportedIngredient(name: "Kokum Butter", amount: 15, unit: nil)
            ],
            additives: [ImportedIngredient(name: "Sodium Citrate", amount: 15, unit: "g")],
            fragrances: [ImportedIngredient(name: "Lavender Essential Oil", amount: 3, unit: "% of oils")],
            amountsArePercentages: true,
            batchSize: 1_000,
            batchUnit: "g",
            lyeType: "NaOH",
            superFat: 5,
            waterParts: 2,
            fragrancePercentage: 3
        )
    }
}
#endif
