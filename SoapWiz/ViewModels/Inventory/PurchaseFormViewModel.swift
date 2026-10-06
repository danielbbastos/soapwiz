import Foundation
import SwiftData

@MainActor
@Observable
final class PurchaseFormViewModel {
    var selectedProvider: Provider?
    var dateOfPurchase: Date = Date()
    var quantityText: String = ""
    var totalPriceText: String = ""
    var badge: String = ""
    var journalCode: String = ""
    var hasExpiryDate: Bool = false
    /// Defaults to one year out; overwritten when editing a purchase that has an expiry.
    var expiryDate: Date = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    var hasOpeningDate: Bool = false
    var openingDate: Date = Date()
    var selectedLocation: StorageLocation?

    let ingredient: Ingredient
    let purchase: IngredientPurchase?
    private let locale: Locale

    /// The ingredient's merge key, read in `init` while the row is certainly
    /// still in the store. The duplicate merge can delete it while this sheet is
    /// open, and by then the captured reference is detached and reading anything
    /// stored off it traps — so the key has to be taken now. See `LiveIngredient`.
    private let ingredientSlug: String

    private struct Snapshot {
        let provider: Provider?
        let dateOfPurchase: Date
        let quantityText: String
        let totalPriceText: String
        let badge: String
        let journalCode: String
        let hasExpiryDate: Bool
        let expiryDate: Date
        let hasOpeningDate: Bool
        let openingDate: Date
        let location: StorageLocation?
    }

    private let initialSnapshot: Snapshot

    init(ingredient: Ingredient, purchase: IngredientPurchase? = nil, locale: Locale = .autoupdatingCurrent) {
        self.ingredient = ingredient
        self.ingredientSlug = ingredient.librarySlug
        self.purchase = purchase
        self.locale = locale
        let snapshot = purchase.map { Self.snapshot(of: $0, locale: locale) } ?? Self.newPurchaseSnapshot(for: ingredient)
        initialSnapshot = snapshot

        selectedProvider = snapshot.provider
        dateOfPurchase = snapshot.dateOfPurchase
        quantityText = snapshot.quantityText
        totalPriceText = snapshot.totalPriceText
        badge = snapshot.badge
        journalCode = snapshot.journalCode
        hasExpiryDate = snapshot.hasExpiryDate
        expiryDate = snapshot.expiryDate
        hasOpeningDate = snapshot.hasOpeningDate
        openingDate = snapshot.openingDate
        selectedLocation = snapshot.location
    }

    private static func snapshot(of purchase: IngredientPurchase, locale: Locale) -> Snapshot {
        let fieldFormat = FloatingPointFormatStyle<Double>(locale: locale)
            .precision(.fractionLength(0...2))
            .grouping(.never)
        return Snapshot(
            provider: purchase.provider,
            dateOfPurchase: purchase.dateOfPurchase,
            quantityText: purchase.quantity.formatted(fieldFormat),
            totalPriceText: purchase.totalPrice.formatted(fieldFormat),
            badge: purchase.badge,
            journalCode: purchase.journalCode,
            hasExpiryDate: purchase.expiryDate != nil,
            expiryDate: purchase.expiryDate ?? Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date(),
            hasOpeningDate: purchase.openingDate != nil,
            openingDate: purchase.openingDate ?? Date(),
            location: purchase.storageLocation
        )
    }

    /// A new purchase's starting values, so it only counts as changed once the
    /// user has entered something, and a swipe can still close it until then.
    private static func newPurchaseSnapshot(for ingredient: Ingredient) -> Snapshot {
        let now = Date()
        return Snapshot(
            provider: nil,
            dateOfPurchase: now,
            quantityText: "",
            totalPriceText: "",
            badge: "",
            journalCode: suggestedJournalCode(for: ingredient),
            hasExpiryDate: false,
            expiryDate: Calendar.current.date(byAdding: .year, value: 1, to: now) ?? now,
            hasOpeningDate: false,
            openingDate: now,
            location: nil
        )
    }

    /// Numbers below this are zero-padded out to three digits, so a fresh
    /// sequence reads `AO-001` rather than `AO-1`.
    private static let journalNumberWidth = 3

    /// The next journal code in the ingredient's own sequence: `<CODE>-<n>`,
    /// where `n` is one past the highest number already recorded against it.
    /// Codes the user typed by hand don't match the pattern and are skipped, so
    /// one custom entry never stalls the sequence. Empty when the ingredient has
    /// no code — a bare `-001` would mean nothing.
    ///
    /// Padding widens to whatever the ingredient already uses, so an existing
    /// `AO-0007` continues as `AO-0008` instead of dropping a digit.
    static func suggestedJournalCode(for ingredient: Ingredient) -> String {
        let code = ingredient.code.trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty else { return "" }

        let prefix = "\(code.uppercased())-"
        var highest = 0
        var width = journalNumberWidth
        for purchase in ingredient.purchases {
            let journal = purchase.journalCode.trimmingCharacters(in: .whitespaces)
            guard journal.uppercased().hasPrefix(prefix) else { continue }
            let digits = journal.dropFirst(prefix.count)
            guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let number = Int(digits) else { continue }
            highest = max(highest, number)
            width = max(width, digits.count)
        }
        let next = String(highest + 1)
        let padding = String(repeating: "0", count: max(0, width - next.count))
        return "\(code)-\(padding)\(next)"
    }

    var isEditing: Bool { purchase != nil }
    var quantity: Double { LocaleDecimal.parse(quantityText, locale: locale) ?? 0 }
    var totalPrice: Double { LocaleDecimal.parse(totalPriceText, locale: locale) ?? 0 }
    var pricePerUnit: Double {
        guard quantity > 0 else { return 0 }
        return totalPrice / quantity
    }

    var isDirty: Bool {
        let snap = initialSnapshot
        return selectedProvider !== snap.provider
            || dateOfPurchase != snap.dateOfPurchase
            || quantityText != snap.quantityText
            || totalPriceText != snap.totalPriceText
            || badge != snap.badge
            || journalCode != snap.journalCode
            || hasExpiryDate != snap.hasExpiryDate
            || (hasExpiryDate && expiryDate != snap.expiryDate)
            || hasOpeningDate != snap.hasOpeningDate
            || (hasOpeningDate && openingDate != snap.openingDate)
            || selectedLocation !== snap.location
    }

    var isValid: Bool { quantity > 0 && LocaleDecimal.isReadable(totalPriceText, locale: locale) && isDirty }

    /// Throws when the ingredient this sheet was opened for has been merged away
    /// and no surviving row carries its slug. Appending to the detached reference
    /// instead would lose the purchase without a trace — `Ingredient.purchases`
    /// cascades, so the new row is deleted along with the dead parent — and the
    /// caller is told rather than dismissing on a write that went nowhere.
    func save(context: ModelContext) throws {
        if let purchase {
            purchase.provider = selectedProvider
            purchase.dateOfPurchase = dateOfPurchase
            purchase.quantity = quantity
            purchase.totalPrice = totalPrice
            purchase.badge = badge
            purchase.journalCode = journalCode
            purchase.expiryDate = hasExpiryDate ? expiryDate : nil
            purchase.openingDate = hasOpeningDate ? openingDate : nil
            purchase.storageLocation = selectedLocation
        } else {
            guard let live = LiveIngredient.resolve(ingredient, slug: ingredientSlug, in: context) else {
                throw PurchaseSaveError.ingredientUnavailable
            }
            let newPurchase = IngredientPurchase(
                provider: selectedProvider,
                dateOfPurchase: dateOfPurchase,
                quantity: quantity,
                totalPrice: totalPrice,
                badge: badge,
                journalCode: journalCode,
                expiryDate: hasExpiryDate ? expiryDate : nil,
                openingDate: hasOpeningDate ? openingDate : nil,
                storageLocation: selectedLocation
            )
            context.insert(newPurchase)
            newPurchase.attach(to: live)
        }
        // Not thrown: the sheet stays open on a throw, and tapping Add again
        // would insert a second purchase beside the one still in the context.
        context.saveLoggingFailure()
    }
}

/// The one way saving a purchase can fail.
enum PurchaseSaveError: LocalizedError {
    /// The ingredient was merged away while the sheet was open, and no surviving
    /// row carries its slug.
    case ingredientUnavailable

    var errorDescription: String? {
        "This ingredient is no longer available, so the purchase wasn’t saved. "
            + "Close this form and open the ingredient again."
    }
}
