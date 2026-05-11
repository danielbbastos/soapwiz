import Foundation
import SwiftData

@MainActor
@Observable
final class ProviderFormViewModel {
    var name: String = ""
    var website: String = ""
    var notes: String = ""

    let provider: Provider?

    init(provider: Provider? = nil) {
        self.provider = provider
        if let provider {
            name = provider.name
            website = provider.website
            notes = provider.notes
        }
    }

    var isEditing: Bool { provider != nil }
    var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    var trimmedWebsite: String { website.trimmingCharacters(in: .whitespaces) }
    var trimmedNotes: String { notes.trimmingCharacters(in: .whitespaces) }

    func isDuplicate(among providers: [Provider]) -> Bool {
        guard !trimmedName.isEmpty else { return false }
        return providers.contains { $0.name.lowercased() == trimmedName.lowercased() && $0 != provider }
    }

    func isValid(among providers: [Provider]) -> Bool {
        !trimmedName.isEmpty && !isDuplicate(among: providers)
    }

    func save(context: ModelContext) {
        if let provider {
            provider.name = trimmedName
            provider.website = trimmedWebsite
            provider.notes = trimmedNotes
        } else {
            context.insert(Provider(name: trimmedName, website: trimmedWebsite, notes: trimmedNotes))
        }
    }
}
