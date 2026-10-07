import SwiftUI
import SwiftData
import UIKit

struct IngredientDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppNavigation.self) private var navigation
    @Query private var settingsRecords: [AppSettings]

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

    /// Draws the row's share of the ledger sheet, from where it sits among the
    /// rows its section actually shows.
    private func sheetRow<Content: View>(
        _ index: Int,
        of count: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content().ledgerSheetRow(position: .position(index: index, count: count))
    }

    /// A tappable section header with a rotating chevron. Used instead of the
    /// `Section(isExpanded:)` API, whose disclosure control doesn't render under
    /// this screen's photo header + ledger background styling.
    ///
    /// `animated` is off for the iPad's side-by-side columns: they share one
    /// list row, and the list resizes a row around content already laid out at
    /// its new height, so an animated fold makes the other column jump.
    private func collapsibleHeader(_ title: String, _ section: DetailSection, animated: Bool = true) -> some View {
        Button {
            withAnimation(animated ? .easeInOut(duration: 0.2) : nil) {
                if expandedSections.contains(section) {
                    expandedSections.remove(section)
                } else {
                    expandedSections.insert(section)
                }
            }
        } label: {
            HoneyLedgerSectionLabel(title, isExpanded: isExpanded(section))
        }
        .buttonStyle(.plain)
    }

    init(ingredient: Ingredient) {
        _model = State(initialValue: IngredientDetailViewModel(ingredient: ingredient))
    }

    /// Deliberately the device idiom rather than `horizontalSizeClass`, for the
    /// reason spelled out in `RecipeRowView`: `ContentView` pins the whole
    /// `TabView` to `.compact`, which leaves the size class saying "compact"
    /// everywhere.
    private static let isPhone = UIDevice.current.userInterfaceIdiom == .phone

    /// Taller than the recipe screen's crop. A photographed bar is laid flat and
    /// shot from above; a photographed ingredient is a bottle or a bag standing
    /// up, so a landscape band across it keeps the label and drops the rest.
    private static let heroAspectRatio: CGFloat =
        isPhone ? 4.0 / 3.0 : 2.0 / 1.0

    /// Nil for an ingredient with no photo, which leaves the screen laid out
    /// exactly as it was. The letter avatar deliberately doesn't stand in here:
    /// at the top of the screen it would be a third of a page of flat colour
    /// saying no more than the title already does.
    private var heroImage: UIImage? {
        model.ingredient.imageData.flatMap(UIImage.init(data:))
    }

    /// Off, everything about purchases is hidden — the stock rows, the purchase
    /// log and the add button — but the purchases themselves are kept.
    private var tracksInventory: Bool { AppSettings.tracksInventory(from: settingsRecords) }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            List {
                Section {
                    IngredientDetailSummaryRows(
                        ingredient: model.ingredient,
                        totalRemaining: model.totalRemaining,
                        tracksInventory: tracksInventory,
                        showsChemistry: model.showsChemistry
                    )
                } header: {
                    HoneyLedgerOrnament()
                        // Without a photo the List's first-header inset leaves the
                        // ornament lower than centred; the List clamps this negative
                        // padding, so -10 moves it up about 7pt. With a photo,
                        // `heroPhotoHeader` reserves no gap and the inset centres it.
                        .padding(.top, heroImage == nil ? -10 : 0)
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
                        .foregroundStyle(Color.inkSoft)
                    }
                }

                // Purchases sit directly under Summary: for an ingredient you
                // already own, what you have and when you bought it matters more
                // than its chemistry, which the block below covers in full.
                if tracksInventory {
                    purchasesSection
                }

                if let stats = model.chemistryStats {
                    chemistrySections(stats: stats)
                }

                Section {
                    if isExpanded(.usage) {
                        let entries = model.usageEntries
                        if entries.isEmpty {
                            sheetRow(0, of: 1) {
                                Text("Not used in any batch yet.")
                                    .foregroundStyle(Color.inkSoft)
                            }
                        } else {
                            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                                sheetRow(index, of: entries.count) { UsageEntryRow(entry: entry) }
                            }
                        }
                    }
                } header: {
                    collapsibleHeader("Usage", .usage)
                }
            }
            .readableWidth()
            // Before `ledgerBackground`, whose fill would otherwise cover the photo.
            .heroPhotoHeader(
                image: heroImage,
                aspectRatio: Self.heroAspectRatio,
                coversNavigationBar: $photoCoversNavigationBar
            )
            .navigationTitle(model.ingredient.name)
            .navigationBarTitleDisplayMode(.inline)
            .honeyLedgerInlineTitle(model.ingredient.name, overPhoto: photoCoversNavigationBar)
            .ledgerBackground()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") { navigation.detailSheetRequest = .editIngredient(model.ingredient) }
                }
            }

            if tracksInventory {
                FloatingActionButton(tint: .glassAmber, ink: .onAmber) { navigation.detailSheetRequest = .addPurchase(model.ingredient) }
            }
        }
        // On appear for a merge that landed while this screen was pushed but not
        // on top, and on the notification for one that lands while the user is
        // looking at it.
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
                    sheetRow(0, of: 1) {
                        Text("No purchases yet. Tap + to add one.")
                            .foregroundStyle(Color.inkSoft)
                    }
                } else {
                    let displayed = model.displayedPurchases(showingAll: showAllPurchases)
                    let rowCount = displayed.count + (model.hasMorePurchases ? 1 : 0)
                    ForEach(Array(displayed.enumerated()), id: \.element.id) { index, purchase in
                        sheetRow(index, of: rowCount) {
                            NavigationLink(destination: PurchaseDetailView(purchase: purchase)) {
                                PurchaseRowView(purchase: purchase, unit: model.ingredient.unit)
                            }
                        }
                    }
                    .onDelete { model.delete(at: $0, context: modelContext) }

                    if model.hasMorePurchases {
                        sheetRow(displayed.count, of: rowCount) {
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) { showAllPurchases.toggle() }
                            } label: {
                                Text(showAllPurchases
                                     ? "Show fewer"
                                     : "Show all \(model.sortedPurchases.count) purchases")
                                    .foregroundStyle(Color.amberText)
                            }
                        }
                    }
                }
            }
        } header: {
            collapsibleHeader("Purchases", .purchases)
        }
    }

    /// The read-only chemistry block, shown only for oils. The SAP figures stand
    /// on their own; the composition and qualities need a profile, and are
    /// replaced by a note when the oil has none yet.
    @ViewBuilder
    private func chemistrySections(stats: RecipeStats) -> some View {
        Section {
            if isExpanded(.sapValues) {
                // INS rides with the qualities chart when there's a profile;
                // without one there is no chart, so it belongs here or nowhere.
                let rowCount = model.hasFattyAcidProfile ? 2 : 3
                sheetRow(0, of: rowCount) { sapRow("SAP (NaOH)", model.ingredient.sapValue) }
                sheetRow(1, of: rowCount) { sapRow("SAP (KOH)", model.ingredient.kohSapValue) }
                if !model.hasFattyAcidProfile {
                    sheetRow(2, of: rowCount) {
                        HoneyLedgerLabeledRow("INS") {
                            Text.honeyLedgerFigure(
                                (stats.ins ?? 0).formatted(.number.precision(.fractionLength(1)))
                            )
                        }
                    }
                }
            }
        } header: {
            collapsibleHeader(model.hasFattyAcidProfile ? "SAP Values" : "SAP & INS Values", .sapValues)
        }

        if model.hasFattyAcidProfile {
            profileSections(stats: stats)
        } else {
            Section {
                sheetRow(0, of: 1) {
                    Text(RecipeStatsCopy.ingredientNoFattyAcidData)
                        .foregroundStyle(Color.inkSoft)
                }
            } header: {
                HoneyLedgerSectionLabel("Composition")
            }
        }
    }

    @ViewBuilder
    private func profileSections(stats: RecipeStats) -> some View {
        Group {
            if Self.isPhone {
                Section {
                    if isExpanded(.fattyAcidProfile) {
                        sheetRow(0, of: 1) {
                            VStack(spacing: 10) { FattyAcidBreakdownRows(stats: stats) }
                                .padding(.vertical, 4)
                        }
                    }
                } header: {
                    collapsibleHeader("Fatty Acid Profile", .fattyAcidProfile)
                }

                Section {
                    if isExpanded(.fattyAcidTypes) {
                        sheetRow(0, of: 1) {
                            VStack(spacing: 10) { FattyAcidTotalsRows(stats: stats) }
                                .padding(.vertical, 4)
                        }
                    }
                } header: {
                    collapsibleHeader("Fatty Acid Types", .fattyAcidTypes)
                }
            } else {
                fattyAcidColumnsSection(stats: stats)
            }

            Section {
                if isExpanded(.soapQualities) {
                    sheetRow(0, of: 1) {
                        VStack(alignment: .leading, spacing: 12) {
                            SoapPropertiesSection(stats: stats, interactive: false)
                        }
                        .padding(.vertical, 4)
                    }
                }
            } header: {
                collapsibleHeader("Soap Qualities", .soapQualities)
            }
        }
    }

    /// The profile and the types side by side on iPad: the labels never
    /// change and are short.
    private func fattyAcidColumnsSection(stats: RecipeStats) -> some View {
        Section {
            HoneyLedgerColumns {
                HoneyLedgerColumn(isExpanded: isExpanded(.fattyAcidProfile)) {
                    collapsibleHeader("Fatty Acid Profile", .fattyAcidProfile, animated: false)
                } rows: {
                    FattyAcidBreakdownRows(stats: stats)
                }
            } trailing: {
                HoneyLedgerColumn(isExpanded: isExpanded(.fattyAcidTypes)) {
                    collapsibleHeader("Fatty Acid Types", .fattyAcidTypes, animated: false)
                } rows: {
                    FattyAcidTotalsRows(stats: stats)
                }
            }
        }
    }

    private func sapRow(_ title: String, _ value: Double?) -> some View {
        HoneyLedgerLabeledRow(title) {
            if let value {
                Text.honeyLedgerFigure(
                    value.formatted(.number.precision(.fractionLength(0...4)).grouping(.never)),
                    unit: "g/g"
                )
            } else {
                Text("Not specified")
                    .font(.body)
                    .foregroundStyle(Color.inkSoft)
            }
        }
    }
}
