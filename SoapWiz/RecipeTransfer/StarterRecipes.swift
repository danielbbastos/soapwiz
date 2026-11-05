import Foundation

/// The recipes bundled with the app for the user to copy from.
///
/// A `.soapwizrecipe` payload like any shared file, read by `StarterRecipeLibrary`
/// to show them and to copy one into the user's recipes. Nothing is installed
/// ahead of time: the recipes exist only in the bundle until the user copies one.
enum StarterRecipes {
    private static let resourceName = "StarterRecipes"
    private static let resourceExtension = "soapwizrecipe"

    static func payload(in bundle: Bundle = .main) throws -> RecipeTransferData {
        guard let url = bundle.url(forResource: resourceName, withExtension: resourceExtension) else {
            throw RecipeTransferError.malformedFile
        }
        return try RecipeTransferDecoder.payload(fromFile: Data(contentsOf: url))
    }
}
