import UIKit

private enum NumberPadPopoverInstaller {
    static var isInstalled = false
}

extension UITextField {
    /// Whether a field with this keyboard should skip the floating number-pad
    /// popover and show the full docked keyboard instead.
    ///
    /// iPadOS 26 presents the number pads as a popover. A tap outside a
    /// popover only dismisses it, so tapping a second number field while it is
    /// open closes the popover and leaves the first field focused, and the
    /// field aimed at needs another tap (SW-244). `asciiCapableNumberPad` is
    /// included because it is a number pad too and takes the same popover.
    static func suppressesNumberPadPopover(
        keyboardType: UIKeyboardType,
        idiom: UIUserInterfaceIdiom
    ) -> Bool {
        guard idiom == .pad else { return false }
        switch keyboardType {
        case .numberPad, .decimalPad, .asciiCapableNumberPad:
            return true
        default:
            return false
        }
    }

    /// Turns the number-pad popover off for every number field in the app.
    ///
    /// SwiftUI has no modifier for `allowsNumberPadPopover`, so it is set on
    /// the underlying field. Setting it once the field is already focused
    /// reloads the keyboard a second time, which costs 38-48 ms per focus
    /// (SW-274). So a window-wide recognizer presets it when a touch begins,
    /// before the field takes focus, and the begin-editing observer is only
    /// the fallback for focus that doesn't come from a touch (a programmatic
    /// `@FocusState`, Tab on a hardware keyboard). The observer reloads the
    /// input views only when the value was still true. The property doesn't
    /// exist before iOS 26, so this does nothing there. Safe to call more than
    /// once; it installs a single observer and one recognizer per window.
    static func disableNumberPadPopovers() {
        guard !NumberPadPopoverInstaller.isInstalled else { return }
        NumberPadPopoverInstaller.isInstalled = true
        guard #available(iOS 26, *) else { return }
        NotificationCenter.default.addObserver(
            forName: UIWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { notification in
            MainActor.assumeIsolated {
                (notification.object as? UIWindow)?.installNumberPadPopoverPreset()
            }
        }
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows where window.isKeyWindow {
                window.installNumberPadPopoverPreset()
            }
        }
        NotificationCenter.default.addObserver(
            forName: UITextField.textDidBeginEditingNotification,
            object: nil,
            queue: .main
        ) { notification in
            MainActor.assumeIsolated {
                guard let field = notification.object as? UITextField else { return }
                let suppresses = suppressesNumberPadPopover(
                    keyboardType: field.keyboardType,
                    idiom: field.traitCollection.userInterfaceIdiom
                )
                guard suppresses, field.allowsNumberPadPopover else { return }
                field.allowsNumberPadPopover = false
                field.reloadInputViews()
            }
        }
    }
}

/// Turns the number-pad popover off before a number field takes focus (SW-274).
///
/// A field becomes first responder when the tap ends, but the touch begins
/// earlier, so the flag can be set in between and the keyboard loads once.
/// It never recognizes, cancels or delays anything; it only looks at touches.
final class NumberPadPopoverPresetRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    init() {
        super.init(target: nil, action: nil)
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    /// The number fields a touch on `touchedView` is about to focus.
    ///
    /// - A touch on a field, or inside one, targets that field.
    /// - A touch elsewhere in a list cell targets the cell's number fields,
    ///   since the SW-244 row-height tap area focuses the field from SwiftUI.
    /// - Anywhere else targets nothing.
    static func presetTargets(for touchedView: UIView?, idiom: UIUserInterfaceIdiom) -> [UITextField] {
        guard let touchedView else { return [] }
        let ancestors = sequence(first: touchedView, next: \.superview)
        let candidates: [UITextField]
        if let field = ancestors.lazy.compactMap({ $0 as? UITextField }).first {
            candidates = [field]
        } else if let cell = ancestors.first(where: { $0 is UICollectionViewCell || $0 is UITableViewCell }) {
            candidates = textFields(in: cell)
        } else {
            return []
        }
        return candidates.filter {
            UITextField.suppressesNumberPadPopover(keyboardType: $0.keyboardType, idiom: idiom)
        }
    }

    private static func textFields(in view: UIView) -> [UITextField] {
        view.subviews.flatMap { subview -> [UITextField] in
            (subview as? UITextField).map { [$0] } ?? textFields(in: subview)
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard #available(iOS 26, *) else { return false }
        let idiom = touch.view?.traitCollection.userInterfaceIdiom ?? .unspecified
        for field in Self.presetTargets(for: touch.view, idiom: idiom) where field.allowsNumberPadPopover {
            field.allowsNumberPadPopover = false
        }
        return false
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }
}

private extension UIWindow {
    func installNumberPadPopoverPreset() {
        let hasRecognizer = gestureRecognizers?.contains { $0 is NumberPadPopoverPresetRecognizer } ?? false
        guard !hasRecognizer else { return }
        addGestureRecognizer(NumberPadPopoverPresetRecognizer())
    }
}
