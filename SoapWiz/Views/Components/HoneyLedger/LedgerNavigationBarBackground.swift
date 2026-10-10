import SwiftUI

/// The background of a navigation bar once content has scrolled under it,
/// before iOS 26. The system's own is a whitish material that matches no
/// screen's paper, so the bar is either `paper` with a `rule` hairline below,
/// or clear where something else draws the paper or a photograph sits behind.
/// The scroll-edge appearance is left transparent by the callers.
///
/// Only the background properties are set, so a copy of an appearance keeps the
/// title attributes it already has.
enum LedgerNavigationBarBackground {
    case paper, transparent

    func apply(to appearance: UINavigationBarAppearance) {
        appearance.backgroundEffect = nil
        switch self {
        case .paper:
            appearance.backgroundColor = UIColor(named: "Paper")
            appearance.shadowColor = UIColor(named: "Rule")
        case .transparent:
            appearance.backgroundColor = .clear
            appearance.shadowColor = .clear
        }
    }
}

/// Reaches the hosting view controller's own `UINavigationItem` and gives its
/// standard and compact appearances `background`, for screens with an inline
/// title, whose appearances `LedgerLargeTitleConfigurator` doesn't reach. The
/// scroll-edge appearance is clear, as the system's is.
struct LedgerInlineBarConfigurator: UIViewControllerRepresentable {
    let background: LedgerNavigationBarBackground

    func makeUIViewController(context: Context) -> Controller { Controller() }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.background = background
        controller.apply()
    }

    final class Controller: UIViewController {
        var background = LedgerNavigationBarBackground.paper

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            apply()
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            apply()
        }

        func apply() {
            var host: UIViewController = self
            while let parent = host.parent, !(parent is UINavigationController) {
                host = parent
            }
            guard let navigationController = host.parent as? UINavigationController else { return }

            let bar = navigationController.navigationBar
            let standard = UINavigationBarAppearance(barAppearance: bar.standardAppearance)
            background.apply(to: standard)
            let scrollEdge = UINavigationBarAppearance(barAppearance: bar.scrollEdgeAppearance ?? bar.standardAppearance)
            LedgerNavigationBarBackground.transparent.apply(to: scrollEdge)

            host.navigationItem.standardAppearance = standard
            host.navigationItem.scrollEdgeAppearance = scrollEdge
            host.navigationItem.compactAppearance = standard
        }
    }
}
