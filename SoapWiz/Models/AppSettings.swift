import SwiftData

@Model
final class AppSettings {
    var pvpFactor: Double = 4.0
    var expiryNotificationsEnabled: Bool = false

    init() {}

    static func resolve(in context: ModelContext) -> AppSettings {
        let existing = try? context.fetch(FetchDescriptor<AppSettings>())
        if let settings = existing?.first { return settings }
        let settings = AppSettings()
        context.insert(settings)
        return settings
    }
}
