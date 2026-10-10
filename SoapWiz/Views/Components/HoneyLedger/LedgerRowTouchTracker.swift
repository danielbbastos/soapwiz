import SwiftUI
import UIKit

/// Watches the touches on a ledger row's list cell without ever taking part in
/// them. It reports that a finger is still holding a moment after it came down,
/// and that the touch ended: `true` when it lifted where it was, `false` when
/// it strayed far enough to be a scroll or was cancelled.
///
/// It sits in the row background and hangs its recogniser on the cell around
/// it. A gesture on the row's content would miss a `NavigationLink`: a list
/// draws a link row as a system cell, which keeps its touches from SwiftUI
/// gestures inside it, and ignores button styles too, so the cell is the only
/// place a link row's press can be seen. A reused cell keeps its recogniser,
/// and whichever row it now holds takes over the callbacks.
struct LedgerRowTouchTracker: UIViewRepresentable {
    let onHold: () -> Void
    let onEnd: (_ isTap: Bool) -> Void

    func makeUIView(context: Context) -> LedgerRowTouchTrackerView {
        let view = LedgerRowTouchTrackerView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: LedgerRowTouchTrackerView, context: Context) {
        view.callbacks = .init(onHold: onHold, onEnd: onEnd)
    }
}

/// The view behind `LedgerRowTouchTracker`: once it is in a window it finds the
/// cell it is drawn in and hands that cell's recogniser its callbacks.
///
/// SwiftUI hands it fresh callbacks on every update of its row, and an
/// Inventory row can update many times a second while an iCloud import saves.
/// The callbacks are cheap to hand over; finding the cell and scanning its
/// recognisers is not, so both are remembered and only redone when the view
/// moves or no longer sits inside the cell it found.
final class LedgerRowTouchTrackerView: UIView {
    struct Callbacks {
        var onHold: () -> Void
        var onEnd: (_ isTap: Bool) -> Void
    }

    var callbacks: Callbacks? {
        didSet { attach() }
    }

    /// How many times the cell and its recogniser had to be looked up.
    private(set) var lookupCount = 0

    private weak var cell: UIView?
    private weak var recognizer: LedgerRowTouchRecognizer?

    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        forgetCell()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        forgetCell()
        attach()
    }

    private func forgetCell() {
        cell = nil
        recognizer = nil
    }

    private func attach() {
        guard window != nil, let callbacks, let recognizer = recognizerOnEnclosingCell() else { return }
        recognizer.onHold = callbacks.onHold
        recognizer.onEnd = callbacks.onEnd
    }

    /// The remembered recogniser while this view is still inside the cell it
    /// was found on: checking that climbs only to that cell and compares
    /// references, where finding a cell tests every superview's class.
    func recognizerOnEnclosingCell() -> LedgerRowTouchRecognizer? {
        if let cell, let recognizer, recognizer.view === cell, isDescendant(of: cell) {
            return recognizer
        }
        lookupCount += 1
        guard let cell = enclosingCell else {
            forgetCell()
            return nil
        }
        let recognizer = cell.gestureRecognizers?.lazy.compactMap { $0 as? LedgerRowTouchRecognizer }.first
            ?? LedgerRowTouchRecognizer.installed(on: cell)
        self.cell = cell
        self.recognizer = recognizer
        return recognizer
    }

    private var enclosingCell: UIView? {
        sequence(first: self as UIView, next: \.superview)
            .dropFirst()
            .first { $0 is UICollectionViewCell || $0 is UITableViewCell }
    }
}

/// The recogniser behind `LedgerRowTouchTracker`. It never recognises, so the
/// row's buttons, links and text fields, and the list's scrolling, get every
/// touch as before: it stays possible while one finger is down and fails as
/// soon as that touch ends or turns into a scroll.
final class LedgerRowTouchRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    var onHold: () -> Void = {}
    var onEnd: (_ isTap: Bool) -> Void = { _ in }

    /// How far a finger may move before the touch counts as a scroll, about
    /// what a list allows before it starts scrolling.
    static let slop: CGFloat = 10

    /// How long a finger must stay before a link row lights: a list waits a
    /// moment too, so a row doesn't flash under every scroll that starts on it.
    static let holdDelay: Duration = .milliseconds(90)

    private var start: CGPoint?
    private var holdTask: Task<Void, Never>?

    static func installed(on view: UIView) -> LedgerRowTouchRecognizer {
        let recognizer = LedgerRowTouchRecognizer()
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.delegate = recognizer
        view.addGestureRecognizer(recognizer)
        return recognizer
    }

    static func exceedsSlop(from start: CGPoint, to point: CGPoint) -> Bool {
        hypot(point.x - start.x, point.y - start.y) > slop
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        guard start == nil, let touch = touches.first else { return }
        start = touch.location(in: view)
        holdTask = Task { [weak self] in
            try? await Task.sleep(for: Self.holdDelay)
            guard !Task.isCancelled, let self, self.start != nil else { return }
            self.onHold()
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let start, let touch = touches.first else { return }
        if Self.exceedsSlop(from: start, to: touch.location(in: view)) {
            finish(isTap: false)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        finish(isTap: true)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        finish(isTap: false)
    }

    /// Also reached when the system resets the recogniser mid-touch, so a row
    /// is never left lit.
    override func reset() {
        endTouch(isTap: false)
        super.reset()
    }

    private func finish(isTap: Bool) {
        endTouch(isTap: isTap)
        state = .failed
    }

    private func endTouch(isTap: Bool) {
        holdTask?.cancel()
        holdTask = nil
        guard start != nil else { return }
        start = nil
        onEnd(isTap)
    }
}
