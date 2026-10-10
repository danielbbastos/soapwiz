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
    /// follows its value as it changes; nil shows none.
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

    func body(content: Content) -> some View {
        content
            .background(LedgerLargeTitleConfigurator(subtitle: subtitle, margin: margin).frame(width: 0, height: 0))
            .onGeometryChange(for: CGFloat?.self) { proxy in
                ReadableWidth.margin(for: proxy.size.width)
            } action: { newMargin in
                margin = newMargin
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

/// What sits under the large title: a count line, and under it an amber
/// diamond with a hairline running off to the trailing edge. Only the label's
/// text changes after it is built; the label's font follows Dynamic Type itself.
private final class LedgerSubtitleView: UIView {
    var text: String? {
        get { label.text }
        set { if label.text != newValue { label.text = newValue } }
    }

    /// How far both sides are drawn in from the view's edges, so the block can
    /// line up with content that is capped narrower than the bar.
    var inset: CGFloat = 0 {
        didSet {
            leadingConstraint.constant = inset
            trailingConstraint.constant = -inset
        }
    }

    private let label = UILabel()
    private let stack = UIStackView()
    private lazy var leadingConstraint = stack.leadingAnchor.constraint(equalTo: leadingAnchor)
    private lazy var trailingConstraint = stack.trailingAnchor.constraint(equalTo: trailingAnchor)

    override init(frame: CGRect) {
        super.init(frame: frame)

        // The footnote size at the default text size: `scaledFont` does the
        // scaling, and starting from the current size would apply it twice.
        let defaultSize = UIFont.preferredFont(
            forTextStyle: .footnote,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .large)
        ).pointSize
        let base = UIFont.monospacedDigitSystemFont(ofSize: defaultSize, weight: .regular)
        label.font = UIFontMetrics(forTextStyle: .footnote).scaledFont(for: base)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UIColor(named: "InkSoft") ?? .secondaryLabel

        stack.addArrangedSubview(label)
        stack.addArrangedSubview(Self.makeOrnament())
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            leadingConstraint,
            trailingConstraint,
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The diamond is a square turned 45 degrees, so its side is 8 over root two
    /// to make it 8pt across.
    private static func makeOrnament() -> UIView {
        let row = UIView()
        let diamondSide = 8 / 2.0.squareRoot()

        let diamondSlot = UIView()
        let diamond = UIView()
        diamond.backgroundColor = UIColor(named: "Amber")
        diamond.transform = CGAffineTransform(rotationAngle: .pi / 4)
        diamond.translatesAutoresizingMaskIntoConstraints = false
        diamondSlot.addSubview(diamond)

        let line = UIView()
        line.backgroundColor = UIColor(named: "Rule")

        for view in [diamondSlot, line] {
            view.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(view)
        }
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 8),
            diamondSlot.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            diamondSlot.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            diamondSlot.widthAnchor.constraint(equalToConstant: 8),
            diamondSlot.heightAnchor.constraint(equalToConstant: 8),
            diamond.centerXAnchor.constraint(equalTo: diamondSlot.centerXAnchor),
            diamond.centerYAnchor.constraint(equalTo: diamondSlot.centerYAnchor),
            diamond.widthAnchor.constraint(equalToConstant: diamondSide),
            diamond.heightAnchor.constraint(equalToConstant: diamondSide),
            line.leadingAnchor.constraint(equalTo: diamondSlot.trailingAnchor, constant: 8),
            line.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            line.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            line.heightAnchor.constraint(equalToConstant: 1)
        ])
        return row
    }
}

/// Reaches the hosting view controller's own `UINavigationItem` and gives it
/// serif, `ink` title attributes. Starts from copies of the bar's current
/// appearances and changes only the title text attributes, so the bar's
/// background, and with it iOS 26's glass, is left as the system draws it.
private struct LedgerLargeTitleConfigurator: UIViewControllerRepresentable {
    let subtitle: String?
    /// The screen's capped-content margin from the edge of the screen, nil
    /// where the system margin applies.
    let margin: CGFloat?

    func makeUIViewController(context: Context) -> Controller { Controller() }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.subtitle = subtitle
        controller.margin = margin
        controller.apply()
    }

    final class Controller: UIViewController {
        var subtitle: String?
        var margin: CGFloat?

        private var subtitleView: LedgerSubtitleView?
        private var titleInset: CGFloat = 0
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

            // How far in from the bar's own leading margin the title block goes.
            let barMargin = navigationController.navigationBar.layoutMargins.left
            titleInset = margin.map { max($0 - barMargin, 0) } ?? 0

            let key = "\(traitCollection.preferredContentSizeCategory.rawValue) \(titleInset)"
            if key != appliedKey || host.navigationItem.standardAppearance == nil {
                appliedKey = key
                applyTitleAppearances(to: host, in: navigationController)
                // The subtitle's font scales with the text size too.
                appliedSubtitle = nil
            }
            subtitleView?.inset = titleInset
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
                host.navigationItem.largeSubtitleView = nil
                return
            }
            let view = subtitleView ?? LedgerSubtitleView()
            subtitleView = view
            view.inset = titleInset
            view.text = subtitle
            if host.navigationItem.largeSubtitleView !== view {
                host.navigationItem.largeSubtitleView = view
            }
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
            var largeTitle: [NSAttributedString.Key: Any] = [
                .font: Self.serifFont(.largeTitle),
                .foregroundColor: ink
            ]
            if titleInset > 0 {
                let paragraph = NSMutableParagraphStyle()
                paragraph.firstLineHeadIndent = titleInset
                paragraph.headIndent = titleInset
                largeTitle[.paragraphStyle] = paragraph
            }
            appearance.largeTitleTextAttributes = largeTitle
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
