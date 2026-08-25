import Foundation
import SwiftData

/// Builds the document the share sheet hands over.
///
/// The one place that decides what a shared file is called, so a recipe shared
/// from the detail screen and the same recipe shared from a selection in the
/// list arrive under the same name.
@MainActor
enum RecipeTransferExport {
    static let fileExtension = "soapwizrecipe"

    /// Writes the payload to a temporary file for the system share sheet.
    ///
    /// A real file on disk rather than bytes held in memory, matching how a
    /// backup is shared from Settings. It is also what makes the share sheet
    /// useful: handed a URL, the system reads the extension, resolves it through
    /// the declared `UTType` and shows "SoapWiz Recipe · 3 KB" above a document
    /// icon. Handed bytes, it can only show whatever preview image the caller
    /// invented for it.
    ///
    /// Called when the user taps Share rather than ahead of time, so viewing a
    /// recipe never writes a file the user didn't ask for.
    static func file(for recipes: [Recipe]) throws -> ExportFile {
        let data = try RecipeTransferEncoder.fileData(for: recipes)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(filename(for: recipes)).\(fileExtension)")
        try data.write(to: url, options: .atomic)
        return ExportFile(url: url)
    }

    /// One recipe travels under its own name; several travel under a count.
    ///
    /// Naming a multi-recipe file after the first recipe in it would be a small
    /// lie the recipient only discovers after importing fifteen.
    static func filename(for recipes: [Recipe]) -> String {
        guard recipes.count == 1, let only = recipes.first else {
            return "\(recipes.count) SoapWiz Recipes"
        }
        let name = sanitized(only.name)
        return name.isEmpty ? "SoapWiz Recipe" : name
    }

    /// Strips what a file name cannot carry.
    ///
    /// `/` is a path separator and `:` is one historically, so both are rewritten
    /// rather than dropped — "Lemon/Lime Bar" losing its slash would read as one
    /// word. A leading dot is removed too: it would hide the file.
    private static func sanitized(_ name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return cleaned.hasPrefix(".") ? String(cleaned.dropFirst()) : cleaned
    }
}
