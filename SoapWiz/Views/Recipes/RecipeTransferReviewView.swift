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
    let fit: FreeTierImportFit
    var onUpgrade: (ProUpgradeReason) -> Void
    var onUseExisting: (Int, Ingredient) -> Void
    var onToggleRecipe: (Int) -> Void
    var onConfirm: () -> Void

    @FreeTierGateEnvironment private var freeTier
    @State private var pickingEntry: RecipeTransferIngredientPlan?

    var body: some View {
        Form {
            recipesSection
            if !fit.fits {
                limitSection
            }
            if !plan.ingredientsToCreate.isEmpty {
                newIngredientsSection
            }
            if !plan.conflictingIngredients.isEmpty {
                conflictsSection
            }
            if !plan.unmatchedCollectionNames.isEmpty {
                collectionsSection
            }
        }
        .environment(\.defaultMinListRowHeight, 48)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(confirmTitle) { onConfirm() }
                    .disabled(!fit.fits || !plan.hasSelection)
            }
        }
        .sheet(item: $pickingEntry) { entry in
            IngredientPickerView(
                config: .useExisting,
                addedIDs: [],
                allowedRoles: [entry.role],
                isSinglePick: true
            ) { picked in
                guard let ingredient = picked.first else { return }
                onUseExisting(entry.id, ingredient)
            }
        }
    }

    // MARK: - Free limit

    /// Why the ticked recipes can't be added as they are, and the way past it:
    /// untick some, use ingredients already in the inventory, or upgrade. Judged
    /// on the ticked recipes and what they bring, never the whole file, and
    /// still all or nothing among those — a recipe added without its
    /// ingredients would point at things that were never made.
    private var limitSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(fit.explanations, id: \.self) { line in
                    HoneyLedgerFieldNote(line, tint: .warning)
                }
            }
            .padding(.vertical, 4)
            .ledgerSheetRow(position: .first)
            HoneyLedgerActionRow("Upgrade to SoapWiz Pro", systemImage: "sparkles") {
                if let reason = fit.upgradeReason { onUpgrade(reason) }
            }
            .ledgerSheetRow(position: .last)
        } header: {
            HoneyLedgerSectionLabel("Over the Free Limit")
        } footer: {
            if let guidance = limitFooter {
                HoneyLedgerFooter(guidance)
            }
        }
    }

    private var limitFooter: String? {
        switch (plan.isMultiRecipe, fit.exceedsCustomIngredients) {
        case (true, true):
            "Untick some recipes, use ingredients you already have in place of the new ones below, "
                + "or upgrade to add them all."
        case (true, false):
            "Untick some recipes to fit, or upgrade to add them all."
        case (false, true):
            "Use ingredients you already have in place of the new ones below, or upgrade to add them all."
        case (false, false):
            nil
        }
    }

    // MARK: - Recipes

    private var recipesSection: some View {
        Section {
            ForEach(Array(plan.recipeSummaries.enumerated()), id: \.element.id) { index, summary in
                let position = LedgerSheetPosition.position(index: index, count: plan.recipeSummaries.count)
                if plan.isMultiRecipe {
                    let isSelected = plan.isSelected(summary.id)
                    Button { onToggleRecipe(summary.id) } label: {
                        HoneyLedgerPickerRow(state: isSelected ? .selected : .unselected) {
                            recipeRow(summary, isSelected: isSelected)
                        }
                    }
                    .ledgerSheetRow(position: position)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                } else {
                    recipeRow(summary, isSelected: true)
                        .ledgerSheetRow(position: position)
                }
            }
        } header: {
            HoneyLedgerSectionLabel("Recipes")
        }
    }

    /// An unticked recipe keeps its notes and only fades its name: dropping the
    /// notes made the row change height the moment it was ticked.
    private func recipeRow(_ summary: RecipeTransferRecipeSummary, isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(summary.displayName)
                .foregroundStyle(isSelected ? Color.ink : Color.inkFaint)
            Text(summary.detail)
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(Color.inkSoft)
            // Said here rather than in an alert. The rename is a fact
            // about one row, and a payload can hold fifteen — a prompt
            // for each would be a wall of taps between the user and an
            // import they already asked for.
            //
            // A recognised recipe is told about instead of the rename,
            // never as well: the rename is a consequence of already
            // having it, and saying both would read as two problems.
            // Secondary rather than orange, because nothing here needs
            // checking — the sender's copy and the user's own are both
            // kept, which is the least surprising outcome available
            // until a screen exists to offer the alternative.
            if summary.isKnownRecipe {
                Text(
                    "This is a version of “\(summary.knownRecipeName)”, which you "
                    + "already have. It will be added separately."
                )
                .font(.footnote)
                .foregroundStyle(Color.inkSoft)
            } else if summary.isRenamed {
                HoneyLedgerFieldNote(
                    "You already have “\(summary.incomingName)”, so this one is renamed.",
                    tint: .warning
                )
            }
        }
        .padding(.vertical, 4)
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
            ForEach(Array(plan.ingredientsToCreate.enumerated()), id: \.element.id) { index, entry in
                HStack(spacing: 12) {
                    ingredientRow(entry.name, detail: chemistryText(entry.incoming))
                    if fit.exceedsCustomIngredients, entry.countsAsCustomIngredient {
                        Spacer(minLength: 0)
                        Button("Use Existing…") { pickingEntry = entry }
                            .buttonStyle(.borderless)
                            .foregroundStyle(Color.amberText)
                    }
                }
                .ledgerSheetRow(position: .position(index: index, count: plan.ingredientsToCreate.count))
            }
        } header: {
            HoneyLedgerSectionLabel("Will Be Added to Your Inventory")
        } footer: {
            HoneyLedgerFooter(
                "These aren’t in your inventory yet. The values above came with the recipe, "
                + "from whoever shared it — check them before you make a batch."
            )
        }
    }

    private var conflictsSection: some View {
        Section {
            ForEach(Array(plan.conflictingIngredients.enumerated()), id: \.element.id) { index, entry in
                ingredientRow(entry.name, detail: conflictText(entry))
                    .ledgerSheetRow(position: .position(index: index, count: plan.conflictingIngredients.count))
            }
        } header: {
            HoneyLedgerSectionLabel("Your Values Will Be Used")
        } footer: {
            HoneyLedgerFooter(
                "You already have these, with different values from the sender’s. "
                + "Yours are kept, so these recipes may not work out exactly as they did for them."
            )
        }
    }

    private func ingredientRow(_ name: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name)
                .foregroundStyle(Color.ink)
            Text(detail)
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(Color.inkSoft)
        }
        .padding(.vertical, 4)
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
            ForEach(Array(plan.unmatchedCollectionNames.enumerated()), id: \.element) { index, name in
                Text(name)
                    .foregroundStyle(Color.ink)
                    .ledgerSheetRow(position: .position(index: index, count: plan.unmatchedCollectionNames.count))
            }
        } header: {
            HoneyLedgerSectionLabel("Collections Not Added")
        } footer: {
            HoneyLedgerFooter(collectionsFooter)
        }
    }

    private var collectionsFooter: String {
        if freeTier.gate.allows(.collections) {
            "You don’t have these collections, so the recipes arrive unfiled. Nothing new is created."
        } else {
            "Collections are part of SoapWiz Pro, so the recipes arrive unfiled."
        }
    }

    // MARK: - Confirm

    private var confirmTitle: String {
        switch plan.recipeCount {
        case 0: "Add Recipes"
        case 1: "Add Recipe"
        default: "Add \(plan.recipeCount) Recipes"
        }
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
