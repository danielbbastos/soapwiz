import SwiftUI
import UIKit

/// What sits under the large title: a count line, and under it an amber
/// diamond with a hairline running off to the trailing edge. Only the label's
/// text changes after it is built; the label's font follows Dynamic Type itself.
final class LedgerSubtitleView: UIView {
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
/// Before iOS 26 the background of the scrolled bar is set too; see
/// `LedgerNavigationBarBackground`.
struct LedgerLargeTitleConfigurator: UIViewControllerRepresentable {
    let subtitle: String?
    /// The screen's capped-content margin from the edge of the screen, nil
    /// where the system margin applies.
    let margin: CGFloat?
    /// Whether the screen's `headerStrip` draws the paper behind the bar.
    let hasHeaderStrip: Bool
    /// Hears how far in from the edge the large title's text starts, before
    /// iOS 26, where the strip draws the subtitle.
    let onTitleLeading: (CGFloat) -> Void

    func makeUIViewController(context: Context) -> Controller { Controller() }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.subtitle = subtitle
        controller.margin = margin
        controller.hasHeaderStrip = hasHeaderStrip
        controller.onTitleLeading = onTitleLeading
        controller.apply()
    }

    final class Controller: UIViewController {
        var subtitle: String?
        var margin: CGFloat?
        var hasHeaderStrip = false
        var onTitleLeading: ((CGFloat) -> Void)?
        private var reportedLeading: CGFloat?
        private var hasMeasuredLeading = false
        private var missedMeasurements = 0
        private static let measurementsBeforeFallback = 5
        private weak var observedBar: UINavigationBar?
        private var boundsObservation: NSKeyValueObservation?

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

        /// Where the large title's text box starts in the bar, before any
        /// indent: the bar's `layoutMargins` (8pt on iPad) is not where the
        /// system puts it (20pt), so the title view's label is read instead.
        /// Nil while there is no large title view or label to read.
        private static func largeTitleOrigin(in bar: UINavigationBar) -> CGFloat? {
            func label(in view: UIView) -> UILabel? {
                if let label = view as? UILabel { return label }
                return view.subviews.lazy.compactMap { label(in: $0) }.first
            }
            let titleView = bar.subviews.first { String(describing: type(of: $0)).contains("LargeTitle") }
            guard let found = titleView.flatMap({ label(in: $0) }), found.bounds.width > 0 else { return nil }
            return found.convert(found.bounds, to: bar).minX
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            if #unavailable(iOS 26) { reportTitleLeading() }
        }

        /// Hears the bar resize (rotation, a split-view change), which moves
        /// the title without laying this view out.
        private func observe(_ bar: UINavigationBar) {
            guard observedBar !== bar else { return }
            observedBar = bar
            boundsObservation = bar.layer.observe(\.bounds) { [weak self] _, _ in
                Task { @MainActor in
                    self?.observedBar?.layoutIfNeeded()
                    self?.reportTitleLeading()
                }
            }
        }

        /// Reports only what was read off the title itself. When the title
        /// isn't laid out yet nothing is reported, and the strip lines up with
        /// the search field meanwhile; the bar's own margin stands in only if
        /// the title is never found, and never replaces a reading.
        private func reportTitleLeading() {
            guard let bar = observedBar else { return }
            // After the view update that called this, which can't change state.
            let leading: CGFloat
            if let origin = Self.largeTitleOrigin(in: bar) {
                hasMeasuredLeading = true
                leading = origin + titleInset
            } else if !hasMeasuredLeading {
                missedMeasurements += 1
                guard missedMeasurements >= Self.measurementsBeforeFallback else { return }
                leading = bar.layoutMargins.left + titleInset
            } else {
                return
            }
            guard leading != reportedLeading else { return }
            reportedLeading = leading
            Task { onTitleLeading?(leading) }
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

            var key = "\(traitCollection.preferredContentSizeCategory.rawValue) \(titleInset)"
            if #unavailable(iOS 26) {
                key += " \(hasHeaderStrip)"
                observe(navigationController.navigationBar)
                reportTitleLeading()
            }
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
        /// such slot: the screen's `headerStrip` shows the line instead.
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

            if #unavailable(iOS 26) {
                // The strip paints the paper under the bar itself, so the bar
                // is left clear there rather than showing a seam against it.
                let background: LedgerNavigationBarBackground = hasHeaderStrip ? .transparent : .paper
                background.apply(to: standard)
                background.apply(to: compact)
            }

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
