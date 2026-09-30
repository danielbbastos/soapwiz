import SwiftUI
import SwiftData

/// What the log on a batch's screen has asked to show: the form for a new or
/// an existing entry, the delete confirmation, or photos at full size.
struct BatchLogPresentation {
    var addingEntry = false
    var editingEntry: BatchLogEntry?
    var entryPendingDelete: BatchLogEntry?
    var viewerContent: PhotoViewerContent?
}

/// The log on a batch's detail screen: a row to add an entry, then the entries
/// oldest first. The part of the screen that is not a snapshot — everything
/// here is written after the batch was made.
///
/// The section only records what it wants shown; the screen presents it, with
/// `batchLogPresentations(_:batch:)`. A list builds only the rows on screen,
/// so a presentation hung off one of this section's rows fails to open once
/// that row has scrolled away — on a long log, a delete confirmation for an
/// entry far below the add row never appeared until the row came back.
struct BatchLogSection: View {
    let batch: Batch
    @Binding var presentation: BatchLogPresentation

    private var sortedEntries: [BatchLogEntry] {
        BatchHistoryViewModel.sortedLogEntries(of: batch)
    }

    var body: some View {
        Section {
            Button {
                presentation.addingEntry = true
            } label: {
                Label("Add Entry", systemImage: "plus")
            }
            ForEach(sortedEntries) { entry in
                BatchLogEntryRow(
                    entry: entry,
                    onEdit: { presentation.editingEntry = entry },
                    onDelete: { presentation.entryPendingDelete = entry },
                    onOpenPhoto: { index in openPhoto(at: index, of: entry) }
                )
            }
        } header: {
            Text("Log")
        } footer: {
            if batch.logEntries.isEmpty {
                Text("Keep notes and photos as the batch goes: the pour, unmoulding, the cut, cure checks.")
            }
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
        presentation.viewerContent = PhotoViewerContent(
            images: photos.compactMap(\.imageData),
            startIndex: startIndex
        )
    }
}

/// Presents what a `BatchLogSection` asked for. Applied to the screen's form
/// rather than to a row of the section, so it is there wherever the log has
/// been scrolled to.
private struct BatchLogPresentations: ViewModifier {
    @Environment(\.modelContext) private var modelContext
    @Binding var presentation: BatchLogPresentation
    let batch: Batch

    private var confirmingDelete: Binding<Bool> {
        Binding(
            get: { presentation.entryPendingDelete != nil },
            set: { if !$0 { presentation.entryPendingDelete = nil } }
        )
    }

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $presentation.addingEntry) {
                BatchLogEntryFormView(batch: batch)
            }
            .sheet(item: $presentation.editingEntry) { entry in
                BatchLogEntryFormView(batch: batch, entry: entry)
            }
            .fullScreenCover(item: $presentation.viewerContent) { content in
                PhotoViewer(content: content)
            }
            .alert(
                "Delete Entry",
                isPresented: confirmingDelete,
                presenting: presentation.entryPendingDelete
            ) { entry in
                Button("Delete", role: .destructive) {
                    BatchLogEntryFormViewModel.delete(entry, context: modelContext)
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("This entry and its photos will be deleted.")
            }
    }
}

extension View {
    /// Presents what the `BatchLogSection` bound to `presentation` asks for.
    func batchLogPresentations(_ presentation: Binding<BatchLogPresentation>, batch: Batch) -> some View {
        modifier(BatchLogPresentations(presentation: presentation, batch: batch))
    }
}
