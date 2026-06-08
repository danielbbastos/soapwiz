import Foundation
import SwiftData

@MainActor
@Observable
final class ProviderListViewModel {
    var showingAddProvider: Bool = false
    var providerToEdit: Provider?
    var deleteBlockedProvider: Provider?

    func delete(at offsets: IndexSet, in providers: [Provider], context: ModelContext) {
        for index in offsets {
            let provider = providers[index]
            if provider.purchases.isEmpty {
                context.delete(provider)
            } else {
                deleteBlockedProvider = provider
            }
        }
    }
}
