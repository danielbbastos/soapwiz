import SwiftUI
import UIKit

/// One entry of a batch's log: when, what, and a strip of its photos. Each
/// photo opens full size; the menu edits or deletes the entry.
struct BatchLogEntryRow: View {
    let entry: BatchLogEntry
    let onEdit: () -> Void
    let onDelete: () -> Void
    /// Called with the position, among the entry's sorted photos, of the one tapped.
    let onOpenPhoto: (Int) -> Void

    private static let thumbnailSide: CGFloat = 72
    private static let cornerRadius: CGFloat = 10

    var body: some View {
        let photos = entry.sortedPhotos
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Color.inkSoft)
                Spacer()
                menu
            }
            if !entry.text.isEmpty {
                HoneyLedgerNote(entry.text)
            }
            if !photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(photos.enumerated()), id: \.element.persistentModelID) { index, photo in
                            thumbnail(photo, index: index, count: photos.count)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// Borderless, like every button in this row: a form row otherwise takes
    /// the whole row as the tap target of whichever control comes first.
    private var menu: some View {
        Menu {
            Button(action: onEdit) {
                Label("Edit", systemImage: "pencil")
            }
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(Color.inkSoft)
        }
        // The row's menu style would stretch this across the row and override the borderless style.
        .menuStyle(.automatic)
        .buttonStyle(.borderless)
        .accessibilityLabel("Entry Actions")
    }

    private func thumbnail(_ photo: BatchLogPhoto, index: Int, count: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
        return Button {
            onOpenPhoto(index)
        } label: {
            shape
                .fill(Color.honey)
                .frame(width: Self.thumbnailSide, height: Self.thumbnailSide)
                .overlay {
                    if let image = photo.thumbnailData.flatMap(UIImage.init(data:)) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                    }
                }
                // After the overlay, so it crops the photo rather than only the well.
                .clipShape(shape)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Photo \(index + 1) of \(count)")
    }
}
