import Foundation
import OSLog
import SwiftData

extension ModelContext {
    private static let saveLog = Logger(subsystem: "pt.tachyon.SoapWiz", category: "store")

    /// Saves now rather than at the next autosave, and logs a failure instead
    /// of throwing it.
    ///
    /// Called after every action that adds or deletes a row. Until the context
    /// saves, the other side of a relationship doesn't change for the screens
    /// observing it: a purchase added to an ingredient on screen showed only
    /// several seconds later, when autosave ran. Saving straight away also
    /// means a row the user just added can't be lost if the app is closed in
    /// between.
    ///
    /// A failure leaves the change in the context, where autosave tries again.
    func saveLoggingFailure() {
        do {
            try save()
        } catch {
            Self.saveLog.error("Save failed: \(error, privacy: .public)")
        }
    }
}
