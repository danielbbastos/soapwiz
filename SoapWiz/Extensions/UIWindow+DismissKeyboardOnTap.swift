import UIKit

private enum DismissKeyboardOnTapInstaller {
    static var isInstalled = false
}

private extension UIResponder {
    static weak var capturedFirstResponder: UIResponder?

    @objc func captureFirstResponder(_ sender: Any?) {
        UIResponder.capturedFirstResponder = self
    }

    /// The current first responder, found by sending an action with no target,
    /// which UIKit delivers to whichever responder is first.
    static func currentFirstResponder() -> UIResponder? {
        UIApplication.shared.sendAction(
            #selector(captureFirstResponder(_:)),
            to: nil,
            from: nil,
            for: nil
        )
        defer { capturedFirstResponder = nil }
        return capturedFirstResponder
    }
}

/// Ends editing when a touch lands outside every text input (SW-253).
///
/// It sits on the window, so every screen and sheet is covered without a
/// modifier on each view. It never cancels or delays touches, so buttons and
/// rows still get their taps.
final class KeyboardDismissTapRecognizer: UITapGestureRecognizer, UIGestureRecognizerDelegate {
    private weak var trackedResponder: UIResponder?

    init() {
        super.init(target: nil, action: nil)
        addTarget(self, action: #selector(handleTap))
        cancelsTouchesInView = false
        delaysTouchesBegan = false
        delaysTouchesEnded = false
        delegate = self
    }

    /// Whether a touch on `touchedView` should end editing for `firstResponder`.
    ///
    /// - A search field keeps focus: its results are on screen while the user
    ///   taps them.
    /// - A touch on a text input is the user editing, not leaving.
    /// - A touch in the focused field's own row (the SW-244 row-height tap
    ///   area, or the unit menu next to an amount) mustn't unfocus the field.
    static func shouldEndEditing(touchedView: UIView?, firstResponder: UIResponder?) -> Bool {
        guard let responderView = firstResponder as? UIView, let touchedView else { return false }
        if responderView is UISearchTextField { return false }
        if let field = responderView as? UITextField, field.returnKeyType == .search { return false }
        if isInsideTextInput(touchedView) { return false }
        if let touchedCell = enclosingCell(of: touchedView),
           touchedCell === enclosingCell(of: responderView) {
            return false
        }
        return true
    }

    private static func isInsideTextInput(_ view: UIView) -> Bool {
        sequence(first: view, next: \.superview).contains { $0 is UITextField || $0 is UITextView }
    }

    private static func enclosingCell(of view: UIView) -> UIView? {
        sequence(first: view, next: \.superview).first { $0 is UICollectionViewCell || $0 is UITableViewCell }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        let responder = UIResponder.currentFirstResponder()
        guard Self.shouldEndEditing(touchedView: touch.view, firstResponder: responder) else { return false }
        trackedResponder = responder
        return true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    @objc private func handleTap() {
        guard state == .ended, let responder = trackedResponder else { return }
        Task { @MainActor in
            // A tap in another field's row padding focuses that field through
            // a SwiftUI gesture that runs after this one. Waiting a turn lets
            // it take focus first, so ending editing doesn't undo it.
            await Task.yield()
            guard responder.isFirstResponder else { return }
            UIApplication.shared.endEditing()
        }
    }
}

extension UIWindow {
    /// Ends editing on a tap outside any text input, in every window.
    ///
    /// SwiftUI has no app-wide way to dismiss the keyboard, and a tap on a
    /// button elsewhere on iPad doesn't end editing. One recognizer on each
    /// window covers all screens and sheets. Safe to call more than once; it
    /// installs a single observer and one recognizer per window.
    static func dismissKeyboardOnTapOutsideFields() {
        guard !DismissKeyboardOnTapInstaller.isInstalled else { return }
        DismissKeyboardOnTapInstaller.isInstalled = true
        NotificationCenter.default.addObserver(
            forName: UIWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { notification in
            MainActor.assumeIsolated {
                (notification.object as? UIWindow)?.installKeyboardDismissTap()
            }
        }
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene else { continue }
            for window in windowScene.windows where window.isKeyWindow {
                window.installKeyboardDismissTap()
            }
        }
    }

    private func installKeyboardDismissTap() {
        let hasRecognizer = gestureRecognizers?.contains { $0 is KeyboardDismissTapRecognizer } ?? false
        guard !hasRecognizer else { return }
        addGestureRecognizer(KeyboardDismissTapRecognizer())
    }
}
