import SwiftUI
import SwiftData

/// The log on a batch's detail screen: its entries oldest first, and a row to
/// add another. The part of the screen that is not a snapshot — everything
/// here is written after the batch was made.
struct BatchLogSection: View {
    @Environment(\.modelContext) private var modelContext
    let batch: Batch

    @State private var addingEntry = false
    @State private var editingEntry: BatchLogEntry?
    @State private var entryPendingDelete: BatchLogEntry?
    @State private var viewerContent: PhotoViewerContent?

    private var confirmingDelete: Binding<Bool> {
        Binding(
            get: { entryPendingDelete != nil },
            set: { if !$0 { entryPendingDelete = nil } }
        )
    }

    private var sortedEntries: [BatchLogEntry] {
        BatchHistoryViewModel.sortedLogEntries(of: batch)
    }

    var body: some View {
        Section {
            ForEach(sortedEntries) { entry in
                BatchLogEntryRow(
                    entry: entry,
                    onEdit: { editingEntry = entry },
                    onDelete: { entryPendingDelete = entry },
                    onOpenPhoto: { index in openPhoto(at: index, of: entry) }
                )
            }
            addRow
        } header: {
            Text("Log")
        } footer: {
            if batch.logEntries.isEmpty {
                Text("Keep notes and photos as the batch goes: the pour, unmoulding, the cut, cure checks.")
            }
        }
    }

    /// The presentations hang off this row because it is the one row the
    /// section always has; a modifier on the `Section` itself would be applied
    /// to every row in it.
    private var addRow: some View {
        Button {
            addingEntry = true
        } label: {
            Label("Add Entry", systemImage: "plus")
        }
        .sheet(isPresented: $addingEntry) {
            BatchLogEntryFormView(batch: batch)
        }
        .sheet(item: $editingEntry) { entry in
            BatchLogEntryFormView(batch: batch, entry: entry)
        }
        .fullScreenCover(item: $viewerContent) { content in
            PhotoViewer(content: content)
        }
        .alert("Delete Entry", isPresented: confirmingDelete, presenting: entryPendingDelete) { entry in
            Button("Delete", role: .destructive) {
                BatchLogEntryFormViewModel.delete(entry, context: modelContext)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This entry and its photos will be deleted.")
        }
    }

    /// Reads the full-size images only now, when they are about to be shown;
    /// the rows draw from thumbnails.
    private func openPhoto(at index: Int, of entry: BatchLogEntry) {
        let photos = entry.sortedPhotos
        guard photos.indices.contains(index), photos[index].imageData != nil else { return }
        // A photo whose file hasn't arrived from iCloud yet has no data, so
        // the tapped one is counted again among those that do.
        let startIndex = photos[..<index].count { $0.imageData != nil }
        viewerContent = PhotoViewerContent(images: photos.compactMap(\.imageData), startIndex: startIndex)
    }
}
