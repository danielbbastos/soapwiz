# SwiftUI Image Optimization Reference

## Table of Contents

- [AsyncImage Best Practices](#asyncimage-best-practices)
- [Image Decoding and Downsampling (Optional Optimization)](#image-decoding-and-downsampling-optional-optimization)
- [SF Symbols](#sf-symbols)
- [Summary Checklist](#summary-checklist)

## AsyncImage Best Practices

### Basic AsyncImage with Phase Handling

```swift
// Good - handles loading and error states
AsyncImage(url: imageURL) { phase in
    switch phase {
    case .empty:
        ProgressView()
    case .success(let image):
        image
            .resizable()
            .aspectRatio(contentMode: .fit)
    case .failure:
        Image(systemName: "photo")
            .foregroundStyle(.secondary)
    @unknown default:
        EmptyView()
    }
}
.frame(width: 200, height: 200)
```

For custom placeholders, replace `ProgressView()` in the `.empty` case with your placeholder view. Add `.transition(.opacity)` to the success case and `.animation(.easeInOut, value: imageURL)` to the container for fade-in transitions.

## Image Decoding and Downsampling (Optional Optimization)

**When displaying local image data at a smaller size than the source, consider suggesting image downsampling as a potential performance improvement**, especially for large images in lists or grids.

### Suggested Optimization Pattern

```swift
// Decode and downsample off main thread
struct DownsampledImageView: View {
    let imageData: Data
    let targetSize: CGSize
    @State private var processedImage: CGImage?

    var body: some View {
        Group {
            if let processedImage {
                Image(processedImage, scale: 1, label: Text(""))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                ProgressView()
            }
        }
        .task {
            processedImage = await downsample(imageData, targetSize: targetSize)
        }
    }

    private func downsample(_ data: Data, targetSize: CGSize) async -> CGImage? {
        await Task.detached {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                return nil
            }
            let maxPixel = max(targetSize.width, targetSize.height)
            let options: [CFString: Any] = [
                kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true
            ]
            return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }.value
    }
}
```

### Reusable Downsampling Actor

For repeated use, wrap the logic in an `actor` with a cache-disabled source option:

```swift
actor ImageProcessor {
    func downsample(data: Data, targetSize: CGSize, scale: CGFloat = 2) -> CGImage? {
        let maxPixel = max(targetSize.width, targetSize.height) * scale
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else {
            return nil
        }
        let downsampleOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions as CFDictionary)
    }
}
```

Key details: `kCGImageSourceShouldCache: false` on the source prevents the full-resolution image from being cached in memory. Multiplying `targetSize` by the display scale ensures the thumbnail is sharp on Retina displays. `kCGImageSourceShouldCacheImmediately: true` on the thumbnail forces decoding at creation time rather than at first render.

### When to Suggest This Optimization

Mention this optimization when displaying local `Data` images, particularly in:
- Scrollable content (List, ScrollView with LazyVStack/LazyHStack)
- Grid layouts with many images
- Any scenario where large images are displayed at smaller sizes

**Don't automatically apply it** — present it as an optional improvement for performance-sensitive scenarios. For remote images, `AsyncImage` handles caching and decoding appropriately.

## SF Symbols

```swift
Image(systemName: "star.fill")
    .foregroundStyle(.yellow)
    .symbolRenderingMode(.multicolor)     // or .hierarchical, .palette, .monochrome

// Animated symbols (iOS 17+)
Image(systemName: "antenna.radiowaves.left.and.right")
    .symbolEffect(.variableColor)
```

Variants are available via naming convention: `star.circle.fill`, `star.square.fill`, `folder.badge.plus`.

## Summary Checklist

- [ ] Use `AsyncImage` with proper phase handling for remote images
- [ ] Handle empty, success, and failure states
- [ ] Consider downsampling for local image `Data` in performance-sensitive scenarios
- [ ] Decode and downsample images off the main thread
- [ ] Use appropriate target sizes for downsampling
- [ ] Use SF Symbols with appropriate rendering modes

**Performance Note**: Image downsampling is an optional optimization. Only suggest it when displaying local image data in performance-sensitive contexts like scrollable lists or grids.
