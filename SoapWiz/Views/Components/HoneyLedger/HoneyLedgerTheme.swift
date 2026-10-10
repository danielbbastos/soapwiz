import SwiftUI

// The Honey Ledger look, the app's only look.
extension View {
    /// `sunken` lays the screen on `paperSunken`, a step below the paper: a
    /// list sitting beside its detail on a wide window, underneath it.
    func ledgerBackground(sunken: Bool = false) -> some View {
        self
            .scrollContentBackground(.hidden)
            .background { HoneyLedgerPaper(sunken: sunken) }
    }

    /// Sets this screen's large and inline titles in New York semibold `ink`,
    /// through its own navigation item, so no other screen in the stack changes.
    /// Keep `.navigationTitle` alongside this for the title text itself.
    ///
    /// `subtitle` is drawn under the large title on iOS 26 and later, and
    /// follows its value as it changes; nil shows none. Earlier versions have
    /// no such slot, so a `headerStrip` further out on the screen draws it at
    /// its top.
    ///
    /// Where the screen's content is capped and centred (`readableWidth()`),
    /// the title block moves in to the content's leading edge, and the
    /// subtitle's hairline ends at its trailing edge.
    func ledgerLargeTitle(subtitle: String? = nil) -> some View {
        modifier(LedgerLargeTitleModifier(subtitle: subtitle))
    }

    func ledgerSheet() -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return self
            .background(Color.paperRaised, in: shape)
            .overlay(shape.strokeBorder(Color.rule, lineWidth: 1))
            .shadow(color: Color.shadow.opacity(0.10), radius: 12, y: 8)
            .shadow(color: Color.shadow.opacity(0.12), radius: 1, y: 1)
    }

    /// `fill` in `shape` with a `rule` edge and a soft shadow, for the small
    /// raised controls that stand in for glass on earlier versions.
    func ledgerRaisedSurface<S: InsettableShape>(_ fill: Color = .paperRaised, in shape: S) -> some View {
        self
            .background(fill, in: shape)
            .overlay(shape.strokeBorder(Color.rule, lineWidth: 1))
            .shadow(color: Color.shadow.opacity(0.2), radius: 1, y: 1)
            .shadow(color: Color.shadow.opacity(0.12), radius: 6, y: 4)
    }

    /// A row's share of the ledger sheet, unselected, with a rule between rows.
    /// A row that is a button lights up while it is pressed; see
    /// `LedgerSheetRowModifier`. Pass `navigates` for a row whose root is a
    /// `NavigationLink`, which can't report its press any other way.
    func ledgerSheetRow(position: LedgerSheetPosition, navigates: Bool = false) -> some View {
        modifier(LedgerSheetRowModifier(position: position, isSelected: false, navigates: navigates))
    }

    /// A row of a list that can sit beside its detail: a selected row is honey,
    /// the rest sit on the raised sheet with a rule between them. Each row draws
    /// its own piece of the sheet's edge, so it needs to know where in the list
    /// it is. A button row rather than `List(selection:)`, which on iPadOS 26
    /// draws a bordered capsule no row background can hide.
    func ledgerListDetailRow(isSelected: Bool, position: LedgerSheetPosition) -> some View {
        modifier(LedgerSheetRowModifier(position: position, isSelected: isSelected, navigates: false))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct LedgerLargeTitleModifier: ViewModifier {
    let subtitle: String?
    @State private var margin: CGFloat?
    @State private var titleLeading: CGFloat?
    @Environment(\.ledgerHasHeaderStrip) private var hasHeaderStrip

    @ViewBuilder
    func body(content: Content) -> some View {
        let configured = content
            .background(
                LedgerLargeTitleConfigurator(
                    subtitle: subtitle,
                    margin: margin,
                    hasHeaderStrip: hasHeaderStrip,
                    onTitleLeading: { titleLeading = $0 }
                )
                .frame(width: 0, height: 0)
            )
            .onGeometryChange(for: CGFloat?.self) { proxy in
                ReadableWidth.margin(for: proxy.size.width)
            } action: { newMargin in
                margin = newMargin
            }
        if #available(iOS 26, *) {
            configured
        } else {
            configured.preference(
                key: LedgerLargeTitleInfoKey.self,
                value: LedgerLargeTitleInfo(subtitle: subtitle, titleLeading: titleLeading)
            )
        }
    }
}

/// Two hairlines with a hairline between them, set above a total.
struct DoubleRule: View {
    var body: some View {
        VStack(spacing: 1) {
            Rectangle().frame(height: 1)
            Rectangle().frame(height: 1)
        }
        .foregroundStyle(Color.inkSoft)
    }
}

/// `paper` with its grain laid over it, behind everything and never over text.
struct HoneyLedgerPaper: View {
    @Environment(\.colorScheme) private var colorScheme

    var sunken = false

    var body: some View {
        ZStack {
            sunken ? Color.paperSunken : Color.paper
            Image(uiImage: PaperGrain.tile)
                .resizable(resizingMode: .tile)
                .foregroundStyle(Color.ink)
                .opacity(colorScheme == .dark ? 0.05 : 0.07)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// The grain tile: random alpha per pixel, from a fixed seed so it is the same
/// on every launch, built once and reused. A template image, so it takes the
/// colour of `ink` in either appearance.
private enum PaperGrain {
    static let tile: UIImage = makeTile()

    private static let side = 128

    private static func makeTile() -> UIImage {
        var state: UInt64 = 0x5EED_50A9
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        for index in 0..<(side * side) {
            // Black with alpha: premultiplied, so the colour channels stay zero.
            pixels[index * 4 + 3] = UInt8(truncatingIfNeeded: splitMix64(&state) >> 56)
        }
        let image = pixels.withUnsafeMutableBytes { buffer -> CGImage? in
            let context = CGContext(
                data: buffer.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
            return context?.makeImage()
        }
        guard let image else { return UIImage() }
        return UIImage(cgImage: image, scale: 2, orientation: .up).withRenderingMode(.alwaysTemplate)
    }

    private static func splitMix64(_ state: inout UInt64) -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}
