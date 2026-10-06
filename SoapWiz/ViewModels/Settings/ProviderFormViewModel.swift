import Foundation
import SwiftData

@MainActor
@Observable
final class ProviderFormViewModel {
    var name: String = ""
    var website: String = ""
    var notes: String = ""

    let provider: Provider?
    private let initialName: String
    private let initialWebsite: String
    private let initialNotes: String

    init(provider: Provider? = nil) {
        self.provider = provider
        initialName = provider?.name ?? ""
        initialWebsite = provider?.website ?? ""
        initialNotes = provider?.notes ?? ""
        name = initialName
        website = initialWebsite
        notes = initialNotes
    }

    var isEditing: Bool { provider != nil }
    /// Whether anything was typed, which stops a swipe from closing the sheet.
    var isDirty: Bool { name != initialName || website != initialWebsite || notes != initialNotes }
    var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    var trimmedWebsite: String { website.trimmingCharacters(in: .whitespaces) }
    var trimmedNotes: String { notes.trimmingCharacters(in: .whitespaces) }

    func isDuplicate(among providers: [Provider]) -> Bool {
        guard !trimmedName.isEmpty else { return false }
        return providers.contains { $0.name.lookupKey == trimmedName.lookupKey && $0 != provider }
    }

    func isValid(among providers: [Provider]) -> Bool {
        !trimmedName.isEmpty && !isDuplicate(among: providers)
    }

    @discardableResult
    func save(context: ModelContext) -> Provider {
        defer { context.saveLoggingFailure() }
        if let provider {
            provider.name = trimmedName
            provider.website = trimmedWebsite
            provider.notes = trimmedNotes
            return provider
        }
        let newProvider = Provider(name: trimmedName, website: trimmedWebsite, notes: trimmedNotes)
        context.insert(newProvider)
        return newProvider
    }
}
