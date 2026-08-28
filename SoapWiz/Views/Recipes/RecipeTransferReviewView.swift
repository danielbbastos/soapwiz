import SwiftUI
import SwiftData

/// What is about to be added to the library, shown before it is.
///
/// The exact path has nothing to proofread — the numbers are the sender's own,
/// not a reading of their prose — so this screen is not about catching a
/// misread percentage. It is about the two things an exact import decides on
/// the user's behalf: which ingredients it will create, and with whose
/// chemistry.
struct RecipeTransferReviewView: View {
    let plan: RecipeTransferPlan
    var onConfirm: () -> Void
    var onCancel: () -> Void

    var body: some View {
        Form {
            recipesSection
            if !plan.ingredientsToCreate.isEmpty {
                newIngredientsSection
            }
            if !plan.conflictingIngredients.isEmpty {
                conflictsSection
            }
            if !plan.unmatchedCollectionNames.isEmpty {
                collectionsSection
            }
            confirmSection
        }
    }

    // MARK: - Recipes

    private var recipesSection: some View {
        Section("Recipes") {
            ForEach(plan.recipeSummaries) { summary in
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.displayName)
                    Text(summary.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    // Said here rather than in an alert. The rename is a fact
                    // about one row, and a payload can hold fifteen — a prompt
                    // for each would be a wall of taps between the user and an
                    // import they already asked for.
                    if summary.isRenamed {
                        Text("You already have “\(summary.incomingName)”, so this one is renamed.")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .listRowBackground(Color.cardBackground)
    }

    // MARK: - Ingredients

    /// The sender's chemistry, spelled out rather than summarised.
    ///
    /// These values drive `LyeCalculator`, and a wrong saponification value
    /// produces a wrong lye weight — caustic soap is a burn risk, not a
    /// data-quality nit. Everywhere else in the app chemistry reaches a recipe
    /// only from the user's own inventory or their own typing; this is the one
    /// route where it arrives from someone else, so it is shown in full.
    private var newIngredientsSection: some View {
        Section {
            ForEach(plan.ingredientsToCreate) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                    Text(chemistryText(entry.incoming))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Will Be Added to Your Inventory")
        } footer: {
            Text(
                "These aren’t in your inventory yet. The values above came with the recipe, "
                + "from whoever shared it — check them before you make a batch."
            )
        }
        .listRowBackground(Color.cardBackground)
    }

    private var conflictsSection: some View {
        Section {
            ForEach(plan.conflictingIngredients) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                    Text(conflictText(entry))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Your Values Will Be Used")
        } footer: {
            Text(
                "You already have these, with different values from the sender’s. "
                + "Yours are kept, so these recipes may not work out exactly as they did for them."
            )
        }
        .listRowBackground(Color.cardBackground)
    }

    private func chemistryText(_ incoming: RecipeTransferIngredient) -> String {
        var parts: [String] = []
        if let sap = incoming.sapValue {
            parts.append("SAP \(number(sap, places: 4))")
        }
        if let koh = incoming.kohSapValue {
            parts.append("KOH SAP \(number(koh, places: 4))")
        }
        if let density = incoming.density {
            parts.append("density \(number(density, places: 3))")
        }
        if incoming.fattyAcidProfile != nil {
            parts.append("fatty acids included")
        }
        parts.append("measured in \(incoming.unit)")
        return parts.joined(separator: " · ")
    }

    /// Names what actually differs, and whose number is whose.
    ///
    /// Spelled out as "yours … theirs …" rather than "X not Y": the reader has
    /// to be able to tell a rounding difference from a substantive one, and
    /// which of the two their next batch will be mixed from.
    private func conflictText(_ entry: RecipeTransferIngredientPlan) -> String {
        guard let existing = entry.existing else { return "" }
        var parts: [String] = []
        if existing.sapValue != entry.incoming.sapValue {
            parts.append(comparison("SAP", yours: existing.sapValue, theirs: entry.incoming.sapValue, places: 4))
        }
        if existing.kohSapValue != entry.incoming.kohSapValue {
            parts.append(comparison("KOH SAP", yours: existing.kohSapValue, theirs: entry.incoming.kohSapValue, places: 4))
        }
        if existing.density != entry.incoming.density {
            parts.append(comparison("density", yours: existing.density, theirs: entry.incoming.density, places: 3))
        }
        if existing.fattyAcidProfile != entry.incoming.fattyAcidProfile {
            parts.append("fatty acids differ")
        }
        return parts.joined(separator: " · ")
    }

    private func comparison(_ label: String, yours: Double?, theirs: Double?, places: Int) -> String {
        "\(label) yours \(optionalNumber(yours, places: places)), theirs \(optionalNumber(theirs, places: places))"
    }

    // MARK: - Collections

    private var collectionsSection: some View {
        Section {
            ForEach(plan.unmatchedCollectionNames, id: \.self) { name in
                Text(name)
            }
        } header: {
            Text("Collections Not Added")
        } footer: {
            Text("You don’t have these collections, so the recipes arrive unfiled. Nothing new is created.")
        }
        .listRowBackground(Color.cardBackground)
    }

    // MARK: - Confirm

    private var confirmSection: some View {
        Section {
            Button(confirmTitle) { onConfirm() }
            Button("Cancel") { onCancel() }
        } footer: {
            Text("Nothing is added until you tap \(confirmTitle).")
        }
        .listRowBackground(Color.cardBackground)
    }

    private var confirmTitle: String {
        plan.recipeCount == 1 ? "Add Recipe" : "Add \(plan.recipeCount) Recipes"
    }

    // MARK: - Formatting

    private func number(_ value: Double, places: Int) -> String {
        value.formatted(.number.precision(.fractionLength(0...places)))
    }

    private func optionalNumber(_ value: Double?, places: Int) -> String {
        guard let value else { return "none" }
        return number(value, places: places)
    }
}
