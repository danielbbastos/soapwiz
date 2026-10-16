import Foundation
import OSLog
import StoreKit

enum ProPurchaseOutcome: Equatable {
    case purchased
    case pending
    case cancelled
    /// An unverified transaction, a missing product, or a thrown error.
    case failed
}

/// What `ProStore` needs from the App Store, so tests can stand in for it.
protocol ProStoreBackend {
    func isEntitled() async -> Bool
    /// Emits whenever the entitlement may have changed (a purchase made or
    /// approved elsewhere such as Ask to Buy, a refund or a revocation).
    func entitlementChanges() -> AsyncStream<Void>
    func displayPrice() async -> String?
    func purchase() async -> ProPurchaseOutcome
    func sync() async throws
}

struct StoreKitProBackend: ProStoreBackend {
    static let productID = "pt.tachyon.SoapWiz.pro"

    private static let log = Logger(subsystem: "pt.tachyon.SoapWiz", category: "pro")

    func isEntitled() async -> Bool {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == Self.productID,
                  transaction.revocationDate == nil else { continue }
            return true
        }
        return false
    }

    func entitlementChanges() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let task = Task {
                for await result in Transaction.updates {
                    switch result {
                    case .verified(let transaction):
                        await transaction.finish()
                    case .unverified(_, let error):
                        Self.log.error("Unverified transaction update: \(error.localizedDescription)")
                    }
                    continuation.yield()
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func displayPrice() async -> String? {
        do {
            return try await Product.products(for: [Self.productID]).first?.displayPrice
        } catch {
            Self.log.error("Loading the Pro product failed: \(error.localizedDescription)")
            return nil
        }
    }

    func purchase() async -> ProPurchaseOutcome {
        do {
            guard let product = try await Product.products(for: [Self.productID]).first else {
                Self.log.error("The Pro product isn't available")
                return .failed
            }
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                await transaction.finish()
                return .purchased
            case .success(.unverified(_, let error)):
                Self.log.error("Unverified purchase: \(error.localizedDescription)")
                return .failed
            case .pending:
                return .pending
            case .userCancelled:
                return .cancelled
            @unknown default:
                return .failed
            }
        } catch {
            Self.log.error("Purchase failed: \(error.localizedDescription)")
            return .failed
        }
    }

    func sync() async throws {
        try await AppStore.sync()
    }
}
