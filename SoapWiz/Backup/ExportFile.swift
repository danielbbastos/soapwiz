import Foundation

/// A backup file on disk, ready to be handed to the share sheet. `Identifiable`
/// so it can drive `.sheet(item:)`; the `id` is per-instance rather than derived
/// from the URL so re-offering the same file presents the sheet again.
struct ExportFile: Identifiable {
    let id = UUID()
    let url: URL
}
