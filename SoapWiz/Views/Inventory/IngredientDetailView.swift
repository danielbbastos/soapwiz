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
                Section("Summary") {
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
                    if let sap = model.ingredient.sapValue {
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
                }
                .listRowBackground(Color.cardBackground)

                Section("Purchases") {
                    if model.sortedPurchases.isEmpty {
                        Text("No purchases yet. Tap + to add one.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.sortedPurchases) { purchase in
                            NavigationLink(destination: PurchaseDetailView(purchase: purchase)) {
                                PurchaseRowView(purchase: purchase, unit: model.ingredient.unit)
                            }
                        }
                        .onDelete { model.delete(at: $0, context: modelContext) }
                    }
                }
                .listRowBackground(Color.cardBackground)

                Section("Usage") {
                    if model.usageEntries.isEmpty {
                        Text("Not used in any batch yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(model.usageEntries) { entry in
                            UsageEntryRow(entry: entry)
                        }
                    }
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
    }
}
