import UIKit

extension UIApplication {
    /// Ends editing wherever the keyboard focus is, without needing a reference
    /// to the focused field.
    ///
    /// A sheet presented over a focused field hands focus back to it when the
    /// sheet closes, and on iPad tapping a button doesn't end editing, so the
    /// field is still focused when the sheet presents. Ending editing first
    /// leaves nothing to restore. Sending the action with no target reaches
    /// whichever responder is first, which `@FocusState` can't do from a view
    /// that doesn't own the field.
    ///
    /// Also meant for dismissing the keyboard on a tap in a blank area (SW-253).
    func endEditing() {
        sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
