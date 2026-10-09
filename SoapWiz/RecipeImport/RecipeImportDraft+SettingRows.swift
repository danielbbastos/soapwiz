import Foundation

/// One setting the source stated, as the import screens list it: its name and
/// its value, formatted the way the recipe form shows it.
struct RecipeImportSettingRow: Equatable {
    let title: String
    let value: String
}

extension RecipeImportDraft {
    /// The lye settings the source stated, in the order the recipe form lists
    /// them. Only what was said: a setting the text never mentioned has no row,
    /// rather than a default passed off as something read.
    var statedLyeSettingRows: [RecipeImportSettingRow] {
        var rows: [RecipeImportSettingRow] = []
        if let lyeType {
            rows.append(RecipeImportSettingRow(title: "Lye", value: lyeType))
        }
        if let superFat {
            rows.append(RecipeImportSettingRow(title: "Super Fat", value: "\(PercentageFormatter.string(superFat))%"))
        }
        if let waterParts {
            rows.append(RecipeImportSettingRow(title: "Water : Lye", value: "\(PercentageFormatter.string(waterParts)) : 1"))
        }
        return rows
    }
}
