import Foundation

/// Why the Inventory says it is syncing, which decides what it tells the user.
enum SyncNotice: Equatable {
    /// This device has never completed an import: the library is in, and the
    /// user's own ingredients and purchases are on their way.
    case firstSync

    /// This device's last successful sync was long ago, so the import is a
    /// large catch-up with changes from the user's other devices.
    case catchingUp
}
