import SwiftUI

// The Honey Ledger look, adopted screen by screen. Kept beside the warm helpers
// in View+Appearance.swift rather than replacing them, so a screen that hasn't
// moved over looks exactly as it did.
extension View {
    func ledgerBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background { PaperBackground() }
    }

    /// Sets this screen's large and inline titles in New York semibold `ink`,
    /// through its own navigation item, so no other screen in the stack changes.
    /// Keep `.navigationTitle` alongside this for the title text itself.
    ///
    /// `subtitle` is drawn under the large title on iOS 26 and later, and
    /// follows its value as it changes; nil shows none.
    func ledgerLargeTitle(subtitle: String? = nil) -> some View {
        background(LedgerLargeTitleConfigurator(subtitle: subtitle).frame(width: 0, height: 0))
    }

    func ledgerSheet() -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        return self
            .background(Color.paperRaised, in: shape)
            .overlay(shape.strokeBorder(Color.rule, lineWidth: 1))
            .shadow(color: .black.opacity(0.10), radius: 12, y: 8)
            .shadow(color: .black.opacity(0.12), radius: 1, y: 1)
    }

    /// `listDetailRow` on the ledger's paper: a selected row is honey, the rest
    /// sit on the raised sheet with a rule between them.
    func ledgerListDetailRow(isSelected: Bool) -> some View {
        listRowBackground(isSelected ? Color.honey : Color.paperRaised)
            .listRowSeparatorTint(Color.rule)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
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
private struct PaperBackground: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color.paper
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
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Reaches the hosting view controller's own `UINavigationItem` and gives it
/// serif, `ink` title attributes. Starts from copies of the bar's current
/// appearances and changes only the title text attributes, so the bar's
/// background, and with it iOS 26's glass, is left as the system draws it.
private struct LedgerLargeTitleConfigurator: UIViewControllerRepresentable {
    let subtitle: String?

    func makeUIViewController(context: Context) -> Controller { Controller() }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.subtitle = subtitle
        controller.apply()
    }

    final class Controller: UIViewController {
        var subtitle: String?

        private var appliedKey: String?
        /// Nil until a subtitle has been applied, so a first nil still clears.
        private var appliedSubtitle: String??

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            apply()
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            apply()
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (controller: Controller, _) in
                controller.apply()
            }
        }

        func apply() {
            var host: UIViewController = self
            while let parent = host.parent, !(parent is UINavigationController) {
                host = parent
            }
            guard let navigationController = host.parent as? UINavigationController else { return }

            let key = traitCollection.preferredContentSizeCategory.rawValue
            if key != appliedKey || host.navigationItem.standardAppearance == nil {
                appliedKey = key
                applyTitleAppearances(to: host, in: navigationController)
                // The subtitle's font scales with the text size too.
                appliedSubtitle = nil
            }
            applySubtitle(to: host)
        }

        /// Under the large title, on the leading edge; it belongs to the large
        /// title, so it goes when the title collapses. Earlier systems have no
        /// such slot, and show no line.
        private func applySubtitle(to host: UIViewController) {
            guard #available(iOS 26, *) else { return }
            guard appliedSubtitle != .some(subtitle) else { return }
            appliedSubtitle = .some(subtitle)

            guard let subtitle else {
                host.navigationItem.largeAttributedSubtitle = nil
                return
            }
            let base = UIFont.preferredFont(forTextStyle: .footnote)
            var text = AttributedString(subtitle)
            text.uiKit.font = UIFont.monospacedDigitSystemFont(ofSize: base.pointSize, weight: .regular)
            text.uiKit.foregroundColor = UIColor(named: "InkSoft") ?? UIColor.secondaryLabel
            host.navigationItem.largeAttributedSubtitle = text
        }

        private func applyTitleAppearances(to host: UIViewController, in navigationController: UINavigationController) {
            let bar = navigationController.navigationBar
            let standard = styled(bar.standardAppearance)
            let scrollEdge: UINavigationBarAppearance
            if let existing = bar.scrollEdgeAppearance {
                scrollEdge = styled(existing)
            } else {
                let transparent = UINavigationBarAppearance(barAppearance: bar.standardAppearance)
                transparent.configureWithTransparentBackground()
                scrollEdge = styled(transparent)
            }
            let compact = styled(bar.compactAppearance ?? bar.standardAppearance)

            host.navigationItem.standardAppearance = standard
            host.navigationItem.scrollEdgeAppearance = scrollEdge
            host.navigationItem.compactAppearance = compact
        }

        private func styled(_ source: UINavigationBarAppearance) -> UINavigationBarAppearance {
            let appearance = UINavigationBarAppearance(barAppearance: source)
            let ink = UIColor(named: "Ink") ?? .label
            appearance.largeTitleTextAttributes = [
                .font: Self.serifFont(.largeTitle),
                .foregroundColor: ink
            ]
            appearance.titleTextAttributes = [
                .font: Self.serifFont(.title3),
                .foregroundColor: ink
            ]
            return appearance
        }

        private static func serifFont(_ style: UIFont.TextStyle) -> UIFont {
            let base = UIFont.preferredFont(forTextStyle: style)
            let descriptor = base.fontDescriptor
                .addingAttributes([.traits: [UIFontDescriptor.TraitKey.weight: UIFont.Weight.semibold]])
            let serif = descriptor.withDesign(.serif) ?? descriptor
            return UIFont(descriptor: serif, size: base.pointSize)
        }
    }
}
