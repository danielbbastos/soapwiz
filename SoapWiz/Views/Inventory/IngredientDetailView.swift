import SwiftUI
import SwiftData
import UIKit

struct IngredientDetailView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var model: IngredientDetailViewModel

    /// Driven by the hero header: true while the photo is still behind the
    /// navigation bar, which decides whether the title is drawn for a
    /// photograph or for the app's own background.
    @State private var photoCoversNavigationBar = false

    /// Whether the purchases section has been expanded past its two-row preview.
    @State private var showAllPurchases = false

    /// The collapsible sections currently open. Everything but Summary (and the
    /// single-line composition note) can be collapsed; all start expanded.
    @State private var expandedSections: Set<DetailSection> = Set(DetailSection.allCases)

    /// The sections that carry a collapse chevron. Summary and the composition
    /// note are deliberately absent — Summary is always shown, and a one-line
    /// note has nothing to gain from folding away.
    private enum DetailSection: CaseIterable {
        case purchases, sapValues, fattyAcidProfile, fattyAcidTypes, soapQualities, usage
    }

    private func isExpanded(_ section: DetailSection) -> Bool {
        expandedSections.contains(section)
    }

    /// A tappable section header with a rotating chevron. Used instead of the
    /// `Section(isExpanded:)` API, whose disclosure control doesn't render under
    /// this screen's photo header + `warmBackground` styling.
    private func collapsibleHeader(_ title: String, _ section: DetailSection) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                if expandedSections.contains(section) {
                    expandedSections.remove(section)
                } else {
                    expandedSections.insert(section)
                }
            }
        } label: {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .rotationEffect(.degrees(isExpanded(section) ? 0 : -90))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    init(ingredient: Ingredient, autoAddPurchase: Bool = false) {
        _model = State(initialValue: IngredientDetailViewModel(ingredient: ingredient, showingAddPurchase: autoAddPurchase))
    }

    /// Taller than the recipe screen's crop. A photographed bar is laid flat and
    /// shot from above; a photographed ingredient is a bottle or a bag standing
    /// up, so a landscape band across it keeps the label and drops the rest.
    ///
    /// Deliberately the device idiom rather than `horizontalSizeClass`, for the
    /// reason spelled out in `RecipeRowView`: `ContentView` pins the whole
    /// `TabView` to `.compact`, which leaves the size class saying "compact"
    /// everywhere.
    private static let heroAspectRatio: CGFloat =
        UIDevice.current.userInterfaceIdiom == .phone ? 4.0 / 3.0 : 2.0 / 1.0

    /// Nil for an ingredient with no photo, which leaves the screen laid out
    /// exactly as it was. The letter avatar deliberately doesn't stand in here:
    /// at the top of the screen it would be a third of a page of flat colour
    /// saying no more than the title already does.
    private var heroImage: UIImage? {
        model.ingredient.imageData.flatMap(UIImage.init(data:))
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            List {
                Section {
                    if let categoryName = model.ingredient.category?.name {
                        LabeledContent("Category", value: categoryName)
                    }
                    if !model.ingredient.unit.isEmpty {
                        LabeledContent("Unit", value: IngredientUnit(rawValue: model.ingredient.unit)?.label ?? model.ingredient.unit)
                    }
                    LabeledContent("Total Remaining") {
                        let symbol = model.ingredient.unit
                        Text("\(model.totalRemaining.formatted(.number.precision(.fractionLength(0...2)))) \(symbol)")
                            .foregroundStyle(model.totalRemaining > 0 ? AnyShapeStyle(.primary) : AnyShapeStyle(.red))
                    }
                    LabeledContent("Purchases", value: "\(model.ingredient.purchases.count)")
                    // Oils carry SAP in the dedicated chemistry block below; this
                    // is the fallback for the rare non-oil that still has a value.
                    if !model.showsChemistry, let sap = model.ingredient.sapValue {
                        LabeledContent("SAP Value (NaOH)") {
                            Text("\(sap.formatted(.number.precision(.fractionLength(0...4)).grouping(.never))) g/g")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if IngredientUnitConverter.isVolume(model.ingredient.unit) {
                        LabeledContent("Density") {
                            let stored = model.ingredient.density
                            let value = stored ?? IngredientUnitConverter.defaultDensity
                            let source = stored == nil ? "default" : "custom"
                            Text("\(value.formatted(.number.precision(.fractionLength(0...4)).grouping(.never))) g/ml (\(source))")
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Summary")
                } footer: {
                    // A footer sentence rather than a labelled row: where an
                    // ingredient came from is context, not one of its properties,
                    // and a bare "Custom" reads like something the user is being
                    // asked to act on — the more so beside the Density row, which
                    // already says "(custom)" to mean an entirely different thing.
                    if model.ingredient.isLibraryInstalled {
                        Text(model.ingredient.hasCustomChemistry
                             ? "From the built-in ingredient library, with chemistry you've changed."
                             : "From the built-in ingredient library.")
                    }
                }
                .listRowBackground(Color.cardBackground)

                // Purchases sit directly under Summary: for an ingredient you
                // already own, what you have and when you bought it matters more
                // than its chemistry, which the block below covers in full.
                purchasesSection

                if let stats = model.chemistryStats {
                    chemistrySections(stats: stats)
                }

                Section {
                    if isExpanded(.usage) {
                        if model.usageEntries.isEmpty {
                            Text("Not used in any batch yet.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(model.usageEntries) { entry in
                                UsageEntryRow(entry: entry)
                            }
                        }
                    }
                } header: {
                    collapsibleHeader("Usage", .usage)
                }
                .listRowBackground(Color.cardBackground)
            }
            // Before `warmBackground`, whose fill would otherwise cover the photo.
            .heroPhotoHeader(
                image: heroImage,
                aspectRatio: Self.heroAspectRatio,
                coversNavigationBar: $photoCoversNavigationBar
            )
            .navigationTitle(model.ingredient.name)
            .navigationBarTitleDisplayMode(.inline)
            .warmNavigationTitle(model.ingredient.name, overPhoto: photoCoversNavigationBar)
            .warmBackground()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { model.showingEditIngredient = true }
                }
            }

            FloatingActionButton { model.showingAddPurchase = true }
        }
        .sheet(isPresented: $model.showingAddPurchase) {
            PurchaseFormView(ingredient: model.ingredient)
        }
        .sheet(isPresented: $model.showingEditIngredient) {
            IngredientFormView(ingredient: model.ingredient)
        }
        // On appear for a merge that landed while this screen was pushed but not
        // on top, and on the notification for one that lands while the user is
        // looking at it — which is how a sheet opened from here ends up holding
        // a row that no longer exists.
        .onAppear { model.resolve(in: modelContext) }
        .onReceive(NotificationCenter.default.publisher(for: .duplicatesMerged)) { _ in
            model.resolve(in: modelContext)
        }
    }

    /// Two most-recent purchases, with a "Show more" affordance for the rest so
    /// the page can lead with them without an unbounded log.
    @ViewBuilder
    private var purchasesSection: some View {
        Section {
            if isExpanded(.purchases) {
                if model.sortedPurchases.isEmpty {
                    Text("No purchases yet. Tap + to add one.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.displayedPurchases(showingAll: showAllPurchases)) { purchase in
                        NavigationLink(destination: PurchaseDetailView(purchase: purchase)) {
                            PurchaseRowView(purchase: purchase, unit: model.ingredient.unit)
                        }
                    }
                    .onDelete { model.delete(at: $0, context: modelContext) }

                    if model.hasMorePurchases {
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) { showAllPurchases.toggle() }
                        } label: {
                            Text(showAllPurchases
                                 ? "Show fewer"
                                 : "Show all \(model.sortedPurchases.count) purchases")
                        }
                    }
                }
            }
        } header: {
            collapsibleHeader("Purchases", .purchases)
        }
        .listRowBackground(Color.cardBackground)
    }

    /// The read-only chemistry block, shown only for oils. The SAP figures stand
    /// on their own; the composition and qualities need a profile, and are
    /// replaced by a note when the oil has none yet.
    @ViewBuilder
    private func chemistrySections(stats: RecipeStats) -> some View {
        Section {
            if isExpanded(.sapValues) {
                sapRow("SAP (NaOH)", model.ingredient.sapValue)
                sapRow("SAP (KOH)", model.ingredient.kohSapValue)
                // INS rides with the qualities chart when there's a profile;
                // without one there is no chart, so it belongs here or nowhere.
                if !model.hasFattyAcidProfile {
                    LabeledContent("INS") {
                        Text(stats.ins ?? 0, format: .number.precision(.fractionLength(1)))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }
        } header: {
            collapsibleHeader(model.hasFattyAcidProfile ? "SAP Values" : "SAP & INS Values", .sapValues)
        }
        .listRowBackground(Color.cardBackground)

        if model.hasFattyAcidProfile {
            Section {
                if isExpanded(.fattyAcidProfile) {
                    FattyAcidBreakdownRows(stats: stats)
                }
            } header: {
                collapsibleHeader("Fatty Acid Profile", .fattyAcidProfile)
            }
            .listRowBackground(Color.cardBackground)

            Section {
                if isExpanded(.fattyAcidTypes) {
                    FattyAcidTotalsRows(stats: stats)
                }
            } header: {
                collapsibleHeader("Fatty Acid Types", .fattyAcidTypes)
            }
            .listRowBackground(Color.cardBackground)

            Section {
                if isExpanded(.soapQualities) {
                    SoapPropertiesSection(stats: stats, interactive: false)
                }
            } header: {
                collapsibleHeader("Soap Qualities", .soapQualities)
            }
            .listRowBackground(Color.cardBackground)
        } else {
            Section("Composition") {
                Text(RecipeStatsCopy.ingredientNoFattyAcidData)
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(Color.cardBackground)
        }
    }

    private func sapRow(_ title: String, _ value: Double?) -> some View {
        let formatted = value.map { "\($0.formatted(.number.precision(.fractionLength(0...4)).grouping(.never))) g/g" }
        return LabeledContent(title) {
            Text(formatted ?? "Not specified")
                .foregroundStyle(.secondary)
        }
    }
}
