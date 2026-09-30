import SwiftUI
import UIKit

/// What a `PhotoViewer` was asked to show. `Identifiable` so it can drive
/// `.fullScreenCover(item:)`; the `id` is per-instance so opening the same
/// photo twice presents the viewer again.
struct PhotoViewerContent: Identifiable {
    let id = UUID()
    /// Display-size images, in the order they are paged through.
    let images: [Data]
    let startIndex: Int
}

/// One or more photos at full size on black, paged side to side.
///
/// No pinch to zoom: the stored image is already downscaled to about the width
/// of a phone screen in pixels, so there is no further detail to zoom into.
struct PhotoViewer: View {
    let content: PhotoViewerContent

    @Environment(\.dismiss) private var dismiss
    @State private var selection: Int

    init(content: PhotoViewerContent) {
        self.content = content
        _selection = State(initialValue: content.startIndex)
    }

    var body: some View {
        TabView(selection: $selection) {
            ForEach(content.images.indices, id: \.self) { index in
                page(content.images[index])
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: content.images.count > 1 ? .always : .never))
        .background(Color.black.ignoresSafeArea())
        .overlay(alignment: .topTrailing) { closeButton }
    }

    @ViewBuilder
    private func page(_ data: Data) -> some View {
        if let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Image(systemName: "photo")
                .font(.largeTitle)
                .foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.title)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .white.opacity(0.25))
                .padding()
        }
        .accessibilityLabel("Close")
    }
}
