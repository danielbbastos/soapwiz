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
    /// the underlying field each time editing begins. The input views are
    /// reloaded only when the value changed, so the keyboard already chosen
    /// switches to the docked one. The property doesn't exist before iOS 26,
    /// so this does nothing there. Safe to call more than once; it installs a
    /// single observer.
    static func disableNumberPadPopovers() {
        guard !NumberPadPopoverInstaller.isInstalled else { return }
        NumberPadPopoverInstaller.isInstalled = true
        guard #available(iOS 26, *) else { return }
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
