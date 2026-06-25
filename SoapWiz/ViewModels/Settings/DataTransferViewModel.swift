import Foundation
import SwiftData

/// Drives the export/import flow in Settings: builds a backup file for sharing,
/// decodes a chosen file, and (after the user confirms the destructive replace)
/// restores it into the store.
@MainActor
@Observable
final class DataTransferViewModel {
    /// Identifiable wrapper so a freshly written backup file can drive `.sheet(item:)`.
    struct ExportFile: Identifiable {
        let id = UUID()
        let url: URL
    }

    /// Set when an export file is ready; presents the share sheet.
    var exportFile: ExportFile?
    /// Drives the `.fileImporter` presentation.
    var isImporterPresented = false
    /// A decoded, validated backup awaiting the user's confirmation to replace.
    var pendingImport: BackupData?
    /// User-facing error message for either flow.
    var errorMessage: String?

    // MARK: - Export

    func export(from context: ModelContext) {
        do {
            let backup = try BackupService.makeBackup(from: context)
            let data = try BackupService.encode(backup)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(Self.fileName(for: backup.exportedAt))
            try data.write(to: url, options: .atomic)
            exportFile = ExportFile(url: url)
        } catch {
            errorMessage = "Couldn’t export your data. Please try again."
        }
    }

    /// Backup file name, e.g. `SoapWiz-Backup-2026-06-25-143000.json`. Built with a
    /// fixed POSIX locale so it's stable regardless of the device locale.
    static func fileName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return "SoapWiz-Backup-\(formatter.string(from: date)).json"
    }

    // MARK: - Import

    /// Reads and validates the chosen file, then stages it as a `pendingImport`
    /// so the view can confirm before anything is overwritten.
    func handleImportSelection(_ result: Result<URL, Error>) {
        switch result {
        case let .success(url):
            let didScope = url.startAccessingSecurityScopedResource()
            defer { if didScope { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                pendingImport = try BackupService.decode(data)
            } catch let error as BackupError {
                errorMessage = error.errorDescription
            } catch {
                errorMessage = "Couldn’t read this file."
            }
        case .failure:
            errorMessage = "Couldn’t open the selected file."
        }
    }

    /// Performs the destructive replace-all restore for the staged backup.
    func confirmImport(into context: ModelContext) {
        guard let backup = pendingImport else { return }
        pendingImport = nil
        do {
            try BackupService.restore(backup, into: context)
        } catch let error as BackupError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Couldn’t restore this backup."
        }
    }
}
