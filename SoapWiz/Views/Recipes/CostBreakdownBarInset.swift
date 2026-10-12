import SwiftUI

/// Pins the cost bar to the bottom of a tab. The collapsed bar steps aside
/// while a text input is being edited with a docked keyboard up.
///
/// The bar is always drawn in an overlay and placed by hand, because the
/// keyboard safe area SwiftUI applies to the tab is wrong for a floating
/// keyboard: it keeps a docked keyboard's inset, doesn't follow the keyboard
/// as it is dragged, and outlives it. A clear spacer in the bottom safe area
/// reserves the room the bar takes, so the tab's content scrolls clear of it.
struct CostBreakdownBarInset: ViewModifier {
    /// The gap left where the collapsed bar stepped aside, so a row scrolled
    /// above the keyboard doesn't sit flush against it.
    private static let editingGap: CGFloat = 20
    /// How far a frame may be from the screen's edges and still count as
    /// reaching them.
    private static let edgeTolerance: CGFloat = 1

    let model: RecipeFormViewModel
    let isShown: Bool
    @Binding var isExpanded: Bool
    let availableHeight: CGFloat
    /// Whether the tab fills the window, so its bottom edge is the window's.
    /// Where a tab bar sits below it, the correction would push the bar
    /// behind that.
    let pinsToWindowBottom: Bool
    @State private var dockedKeyboard = false
    @State private var isEditing = false
    @State private var editingStartCount = 0
    @State private var containerMaxY: CGFloat = 0
    @State private var barHeight: CGFloat = 0
    @State private var window: UIWindow?
    @State private var windowSafeMaxY: CGFloat?

    private var hidesBar: Bool {
        Self.hidesCostBar(isEditing: isEditing, dockedKeyboard: dockedKeyboard, isExpanded: isExpanded)
    }

    private var reservedHeight: CGFloat {
        guard isShown else { return 0 }
        return hidesBar ? Self.editingGap : barHeight
    }

    private var barOffset: CGFloat {
        Self.barOffset(
            containerMaxY: containerMaxY,
            windowSafeMaxY: windowSafeMaxY ?? containerMaxY,
            dockedKeyboard: dockedKeyboard,
            pinsToWindowBottom: pinsToWindowBottom
        )
    }

    func body(content: Content) -> some View {
        content
            .background {
                if pinsToWindowBottom {
                    WindowProbe { window = $0; refreshWindowBottom() }
                }
            }
            .onKeyboardFrameChange(keyboardChanged)
            .onEditingChange(began: editingBegan, ended: editingEnded)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear
                    .frame(height: reservedHeight)
                    .animation(.easeInOut(duration: 0.25), value: reservedHeight)
            }
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { maxY in
                containerMaxY = maxY
                refreshWindowBottom()
            }
            .overlay(alignment: .bottom) { overlayBar }
    }

    private var overlayBar: some View {
        Group {
            if isShown && !hidesBar {
                CostBreakdownBarView(
                    model: model,
                    isExpanded: $isExpanded,
                    availableHeight: availableHeight,
                    keyboardVisible: dockedKeyboard
                )
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { barHeight = $0 }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .offset(y: barOffset)
        .animation(.easeInOut(duration: 0.25), value: hidesBar)
    }

    /// Re-read from the view's own window whenever something that could have
    /// changed it happens: the window attaches, the tab's frame changes
    /// (rotation, a resized Stage Manager or Split View window), the keyboard
    /// moves, or editing begins or ends.
    private func refreshWindowBottom() {
        guard let window else {
            windowSafeMaxY = nil
            return
        }
        windowSafeMaxY = window.bounds.maxY - window.safeAreaInsets.bottom
    }

    private func keyboardChanged(_ note: Notification) {
        guard let end = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let screenBounds = Self.screenBounds(of: note) else { return }
        dockedKeyboard = Self.isDockedKeyboard(frame: end, screenBounds: screenBounds)
        refreshWindowBottom()
    }

    private static func screenBounds(of note: Notification) -> CGRect? {
        if let screen = note.object as? UIScreen { return screen.bounds }
        return UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.screen }
            .first?.bounds
    }

    /// A keyboard is docked when its frame spans the screen's width and
    /// reaches its bottom edge, both within a point. The frame's x doesn't
    /// matter: the keyboard settling back from floating passes through a full
    /// width frame that is still shifted sideways, and it is docked by then.
    /// An empty frame, or one that starts at or below the bottom edge (a
    /// hidden keyboard), is not docked.
    static func isDockedKeyboard(frame: CGRect, screenBounds: CGRect) -> Bool {
        guard !frame.isEmpty, !screenBounds.isEmpty, frame.minY < screenBounds.maxY else { return false }
        return frame.width >= screenBounds.width - edgeTolerance
            && abs(frame.maxY - screenBounds.maxY) <= edgeTolerance
    }

    /// Whether the collapsed bar steps aside: while a text input is being
    /// edited with a docked keyboard up. A floating keyboard leaves the bottom
    /// free, so the bar stays. The expanded bar holds its own fields, so it
    /// stays too.
    static func hidesCostBar(isEditing: Bool, dockedKeyboard: Bool, isExpanded: Bool) -> Bool {
        isEditing && dockedKeyboard && !isExpanded
    }

    /// How far to move the bar down from where its overlay puts it. A docked
    /// keyboard is placed correctly by SwiftUI, so it needs none. Otherwise
    /// the bar belongs at the bottom of the window above its safe area, and
    /// the tab's frame may end short of that because of a stale keyboard
    /// inset. Never negative.
    static func barOffset(
        containerMaxY: CGFloat,
        windowSafeMaxY: CGFloat,
        dockedKeyboard: Bool,
        pinsToWindowBottom: Bool
    ) -> CGFloat {
        guard pinsToWindowBottom, !dockedKeyboard else { return 0 }
        return max(0, windowSafeMaxY - containerMaxY)
    }

    private func editingBegan() {
        editingStartCount += 1
        isEditing = true
        refreshWindowBottom()
    }

    /// Moving from one field to another ends the first before the second
    /// begins, within the same run loop pass. The decision waits one yield and
    /// holds only if no field began editing in between, so the bar doesn't
    /// flicker back between the two.
    private func editingEnded() {
        let startCount = editingStartCount
        Task {
            await Task.yield()
            guard editingStartCount == startCount else { return }
            isEditing = false
            refreshWindowBottom()
        }
    }
}

/// Reports the window of the view it is placed behind, so the bar can be
/// placed against its own window rather than the app's key window.
private struct WindowProbe: UIViewRepresentable {
    let onWindowChange: (UIWindow?) -> Void

    func makeUIView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onWindowChange = onWindowChange
        return view
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        uiView.onWindowChange = onWindowChange
    }

    final class ProbeView: UIView {
        var onWindowChange: ((UIWindow?) -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            let window = window
            Task { onWindowChange?(window) }
        }
    }
}

private extension View {
    func onEditingChange(began: @escaping () -> Void, ended: @escaping () -> Void) -> some View {
        self
            .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)) { _ in began() }
            .onReceive(NotificationCenter.default.publisher(for: UITextView.textDidBeginEditingNotification)) { _ in began() }
            .onReceive(NotificationCenter.default.publisher(for: UITextField.textDidEndEditingNotification)) { _ in ended() }
            .onReceive(NotificationCenter.default.publisher(for: UITextView.textDidEndEditingNotification)) { _ in ended() }
    }

    func onKeyboardFrameChange(_ perform: @escaping (Notification) -> Void) -> some View {
        self
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification), perform: perform)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification), perform: perform)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidChangeFrameNotification), perform: perform)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification), perform: perform)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification), perform: perform)
    }
}

extension View {
    func costBreakdownBarInset(
        model: RecipeFormViewModel,
        isShown: Bool,
        isExpanded: Binding<Bool>,
        availableHeight: CGFloat,
        pinsToWindowBottom: Bool
    ) -> some View {
        modifier(CostBreakdownBarInset(
            model: model,
            isShown: isShown,
            isExpanded: isExpanded,
            availableHeight: availableHeight,
            pinsToWindowBottom: pinsToWindowBottom
        ))
    }
}
