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

    /// The collapsible sections currently open; all start expanded. The
    /// chemistry sections keep their own state in `IngredientChemistrySections`.
    @State private var expandedSections: Set<DetailSection> = Set(DetailSection.allCases)

    /// The sections that carry a collapse chevron. Summary is deliberately
    /// absent — it is always shown.
    private enum DetailSection: CaseIterable {
        case purchases, usage
    }

    private func isExpanded(_ section: DetailSection) -> Bool {
        expandedSections.contains(section)
    }

    /// Draws the row's share of the ledger sheet, from where it sits among the
    /// rows its section actually shows.
    private func sheetRow<Content: View>(
        _ index: Int,
        of count: Int,
        navigates: Bool = false,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content().ledgerSheetRow(position: .position(index: index, count: count), navigates: navigates)
    }

    /// A tappable section header with a rotating chevron. Used instead of the
    /// `Section(isExpanded:)` API, whose disclosure control doesn't render under
    /// this screen's photo header + ledger background styling.
    ///
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

                IngredientChemistrySections(ingredient: model.ingredient)

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
                FloatingActionButton { navigation.detailSheetRequest = .addPurchase(model.ingredient) }
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
                        sheetRow(index, of: rowCount, navigates: true) {
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
}
