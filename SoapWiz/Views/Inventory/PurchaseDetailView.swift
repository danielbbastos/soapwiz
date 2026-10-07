import SwiftUI

struct PurchaseDetailView: View {
    @Environment(\.currencyCode) private var currencyCode
    let purchase: IngredientPurchase

    @State private var model: PurchaseDetailViewModel
    @State private var showingEdit = false

    init(purchase: IngredientPurchase) {
        self.purchase = purchase
        _model = State(initialValue: PurchaseDetailViewModel(purchase: purchase))
    }

    private var unit: String { purchase.ingredient?.unit ?? "" }

    /// Draws the row's share of the ledger sheet, from where it sits among the
    /// rows its section actually shows.
    private func sheetRow<Content: View>(
        _ index: Int,
        of count: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content().ledgerSheetRow(position: .position(index: index, count: count))
    }

    /// The value in `ink`, or a dash in `inkSoft` when there is none.
    @ViewBuilder
    private func plainValue(_ text: String?) -> some View {
        if let text, !text.isEmpty {
            Text(text)
                .font(.body)
                .foregroundStyle(Color.ink)
        } else {
            Text("—")
                .font(.body)
                .foregroundStyle(Color.inkSoft)
        }
    }

    private func longDate(_ date: Date) -> String {
        date.formatted(date: .long, time: .omitted)
    }

    /// Mirrors the purchase row: once nothing is left, an expiry is no longer
    /// something to act on, so it goes unstamped.
    private var expiryStamp: IngredientStockStamp? {
        guard purchase.remainingAmount > 0, let expiry = purchase.expiryDate else { return nil }
        return IngredientStockStamp.expiry(expiry)
    }

    var body: some View {
        List {
            Section {
                sheetRow(0, of: 5) {
                    HoneyLedgerLabeledRow("Provider") { plainValue(purchase.provider?.name) }
                }
                sheetRow(1, of: 5) {
                    HoneyLedgerLabeledRow("Date") { plainValue(longDate(purchase.dateOfPurchase)) }
                }
                sheetRow(2, of: 5) {
                    HoneyLedgerLabeledRow("Quantity") {
                        Text.honeyLedgerFigure(
                            purchase.quantity.formatted(.number.precision(.fractionLength(0...2))),
                            unit: unit
                        )
                    }
                }
                sheetRow(3, of: 5) {
                    HoneyLedgerLabeledRow("Total Price") {
                        Text.honeyLedgerFigure(purchase.totalPrice.formatted(.currency(code: currencyCode)))
                    }
                }
                sheetRow(4, of: 5) {
                    HoneyLedgerLabeledRow("Price / \(unit.isEmpty ? "unit" : unit)") {
                        Text.honeyLedgerFigure(purchase.pricePerUnit.unitPriceFormatted(currencyCode: currencyCode))
                    }
                }
            } header: {
                // The List's first-header inset leaves the ornament lower than
                // centred; it clamps this negative padding to about 7pt up.
                HoneyLedgerOrnament()
                    .padding(.top, -10)
            }

            Section {
                sheetRow(0, of: 2) {
                    PurchaseRemainingRow(purchase: purchase, unit: unit, model: model)
                }
                sheetRow(1, of: 2) {
                    HoneyLedgerLabeledRow("Storage Location") { plainValue(purchase.storageLocation?.name) }
                }
            } header: {
                HoneyLedgerSectionLabel("Stock")
            }

            Section {
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
            } header: {
                HoneyLedgerSectionLabel("Usage")
            }

            Section {
                sheetRow(0, of: 2) {
                    HoneyLedgerLabeledRow("Badge") {
                        if purchase.badge.isEmpty {
                            plainValue(nil)
                        } else {
                            StatusStamp(word: purchase.badge, tone: .neutral)
                        }
                    }
                }
                sheetRow(1, of: 2) {
                    HoneyLedgerLabeledRow("Journal Code") {
                        if purchase.journalCode.isEmpty {
                            plainValue(nil)
                        } else {
                            Text(purchase.journalCode)
                                .font(.body)
                                .fontDesign(.monospaced)
                                .foregroundStyle(Color.inkSoft)
                        }
                    }
                }
            } header: {
                HoneyLedgerSectionLabel("Identification")
            }

            Section {
                datesRows
            } header: {
                HoneyLedgerSectionLabel("Dates")
            }
        }
        .readableWidth()
        .onDisappear { model.isEditingAmount = false }
        .navigationTitle("Purchase Details")
        .navigationBarTitleDisplayMode(.inline)
        .honeyLedgerInlineTitle("Purchase Details")
        .ledgerBackground()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showingEdit = true }
            }
        }
        .sheet(isPresented: $showingEdit) {
            if let ingredient = purchase.ingredient {
                PurchaseFormView(ingredient: ingredient, purchase: purchase)
            }
        }
    }

    @ViewBuilder
    private var datesRows: some View {
        let expiry = purchase.expiryDate
        let opening = purchase.openingDate
        let count = (expiry == nil ? 0 : 1) + (opening == nil ? 0 : 1)
        if count == 0 {
            sheetRow(0, of: 1) {
                Text("No dates recorded")
                    .foregroundStyle(Color.inkSoft)
            }
        }
        if let expiry {
            sheetRow(0, of: count) {
                HoneyLedgerLabeledRow("Expiry Date") {
                    plainValue(longDate(expiry))
                } below: {
                    if let stamp = expiryStamp {
                        StatusStamp(word: stamp.word, tone: stamp.tone, glyph: stamp.glyph)
                    }
                }
            }
        }
        if let opening {
            sheetRow(count - 1, of: count) {
                HoneyLedgerLabeledRow("Opening Date") { plainValue(longDate(opening)) }
            }
        }
    }
}
