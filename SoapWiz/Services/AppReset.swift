import Foundation
import SwiftData

/// Erases everything and leaves the app as a fresh install would: the
/// ingredient library installed, settings at their defaults, and nothing the
/// user added.
///
/// Rows are deleted one by one rather than by deleting the CloudKit zone. A
/// mirrored store sends each delete to iCloud, so the user's other devices
/// empty too. A deleted zone instead makes every other device upload its whole
/// store again, which would undo the reset.
@MainActor
enum AppReset {
    static let confirmationWord = "DELETE"

    /// Whether `text` is the word the user has to type to confirm. Spaces
    /// around it and its case don't matter; the keyboard may add either.
    static func isConfirmed(by text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == confirmationWord
    }

    /// Deletes every row and rebuilds what a fresh install starts with.
    ///
    /// The wipe is saved before the library goes back in. The installer only
    /// adds an entry no ingredient carries yet, and rows deleted but not yet
    /// saved would still count.
    static func eraseStore(
        in context: ModelContext,
        library: IngredientLibrary = .bundled
    ) throws {
        do {
            try BackupService.wipe(context)
            try context.save()
            try IngredientLibraryInstaller.installMissing(from: library, in: context)
            IngredientCodeBackfill.fillMissingCodesLoggingFailure(from: library, in: context)
            _ = AppSettings.resolve(in: context)
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Clears what this device keeps outside the store: the lye safety
    /// acknowledgment and any rollback files a restore left in `directory`.
    ///
    /// The sync preference and sync status stay. They describe this device's
    /// connection to iCloud, not the user's data.
    static func clearDeviceState(defaults: UserDefaults = .standard, rollbackDirectory: URL?) {
        LyeSafetyAcknowledgment(defaults: defaults).reset()
        guard let rollbackDirectory else { return }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: rollbackDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        for url in files where RestoreCoordinator.isRollbackFile(url) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
