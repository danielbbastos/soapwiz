import CoreGraphics
import Foundation

/// The safe-area insets of the tour's container, in points.
nonisolated struct TourSafeInsets: Equatable {
    var top: CGFloat
    var leading: CGFloat
    var bottom: CGFloat
    var trailing: CGFloat
}

/// Which side of the spotlight the caption card sits on. `leading` and
/// `trailing` are the side of the spotlight the card is placed on.
nonisolated enum TourCardEdge: Equatable {
    case below
    case above
    case leading
    case trailing
}

/// Decides where the tour's caption card goes relative to its spotlights. Pure
/// geometry, so it can be tested without a view: the overlay measures the
/// card, calls `place`, and draws it where the result says.
nonisolated enum TourCardPlacement {
    struct Result: Equatable {
        let origin: CGPoint
        let edge: TourCardEdge

        /// Where the card's notch sits along the edge that faces the
        /// spotlight: from the card's leading edge for `below` and `above`,
        /// from its top for a side placement.
        let notchOffset: CGFloat

        /// Set when the card is taller than the room it was given. The card
        /// should be no taller than this, and scroll its text to fit.
        let maxHeight: CGFloat?
    }

    static let margin: CGFloat = 16
    static let gap: CGFloat = 16
    static let cutoutInflation: CGFloat = 8
    static let notchSize: CGFloat = 14
    static let notchCornerClearance: CGFloat = 18
    static let maxCardWidth: CGFloat = 400

    static func cardWidth(for containerWidth: CGFloat) -> CGFloat {
        min(maxCardWidth, containerWidth - 2 * margin)
    }

    /// `cutouts` are in container coordinates, the first being the one the
    /// card points at. Tries below it, then above, then (when `allowsSide`)
    /// beside it. When none leaves the card clear of every spotlight, it goes
    /// where there is most room and reports that room as `maxHeight`.
    static func place(
        container: CGSize,
        safeInsets: TourSafeInsets,
        cutouts: [CGRect],
        cardSize: CGSize,
        allowsSide: Bool
    ) -> Result {
        let width = cardWidth(for: container.width)
        let safe = CGRect(
            x: safeInsets.leading + margin,
            y: safeInsets.top + margin,
            width: max(0, container.width - safeInsets.leading - safeInsets.trailing - 2 * margin),
            height: max(0, container.height - safeInsets.top - safeInsets.bottom - 2 * margin)
        )
        guard let primary = cutouts.first else {
            let origin = CGPoint(x: clamp(safe.midX - width / 2, safe.minX, safe.maxX - width), y: safe.minY)
            return Result(origin: origin, edge: .below, notchOffset: notchCornerClearance, maxHeight: nil)
        }
        let frame = Frame(
            width: width,
            safe: safe,
            primary: primary,
            obstacles: cutouts.map { $0.insetBy(dx: -cutoutInflation, dy: -cutoutInflation) }
        )

        let candidates = frame.candidates(cardHeight: cardSize.height, allowsSide: allowsSide)
        let size = CGSize(width: width, height: cardSize.height)
        if let fit = candidates.first(where: { frame.isClear(CGRect(origin: $0.origin, size: size)) }) {
            return frame.result(origin: fit.origin, edge: fit.edge, height: cardSize.height, maxHeight: nil)
        }
        return frame.crowdedResult(cardHeight: cardSize.height, allowsSide: allowsSide)
    }

    /// What `place` works against: the card's width, the safe area it must stay
    /// in, the spotlight it points at, and every spotlight grown by the ring
    /// and glow, which it must not touch.
    private struct Frame {
        let width: CGFloat
        let safe: CGRect
        let primary: CGRect
        let obstacles: [CGRect]

        var centredX: CGFloat {
            clamp(primary.midX - width / 2, safe.minX, safe.maxX - width)
        }

        var sideOnLeading: Bool {
            (primary.minX - safe.minX) > (safe.maxX - primary.maxX)
        }

        var sideX: CGFloat {
            sideOnLeading ? primary.minX - gap - width : primary.maxX + gap
        }

        var sideEdge: TourCardEdge {
            sideOnLeading ? .leading : .trailing
        }

        func candidates(cardHeight: CGFloat, allowsSide: Bool) -> [(origin: CGPoint, edge: TourCardEdge)] {
            var found: [(origin: CGPoint, edge: TourCardEdge)] = [
                (CGPoint(x: centredX, y: primary.maxY + gap), .below),
                (CGPoint(x: centredX, y: primary.minY - gap - cardHeight), .above)
            ]
            if allowsSide {
                let top = clamp(primary.midY - cardHeight / 2, safe.minY, safe.maxY - cardHeight)
                found.append((CGPoint(x: sideX, y: top), sideEdge))
            }
            return found
        }

        func isClear(_ rect: CGRect) -> Bool {
            let insideSafeArea = rect.minX >= safe.minX && rect.maxX <= safe.maxX
                && rect.minY >= safe.minY && rect.maxY <= safe.maxY
            return insideSafeArea && !obstacles.contains { $0.intersects(rect) }
        }

        func result(origin: CGPoint, edge: TourCardEdge, height: CGFloat, maxHeight: CGFloat?) -> Result {
            let notch: CGFloat
            switch edge {
            case .below, .above:
                notch = clamp(
                    primary.midX - origin.x - notchSize / 2,
                    notchCornerClearance,
                    width - notchCornerClearance - notchSize
                )
            case .leading, .trailing:
                notch = clamp(
                    primary.midY - origin.y - notchSize / 2,
                    notchCornerClearance,
                    height - notchCornerClearance - notchSize
                )
            }
            return Result(origin: origin, edge: edge, notchOffset: notch, maxHeight: maxHeight)
        }

        /// No edge fits the whole card: use the edge with the most free height.
        func crowdedResult(cardHeight: CGFloat, allowsSide: Bool) -> Result {
            var best = (edge: TourCardEdge.below, space: space(.below))
            let above = space(.above)
            if above.length > best.space.length {
                best = (.above, above)
            }
            if allowsSide, sideX >= safe.minX, sideX + width <= safe.maxX {
                let side = space(sideEdge)
                if side.length > best.space.length {
                    best = (sideEdge, side)
                }
            }

            let available = best.space.length
            let height = min(cardHeight, available)
            let origin: CGPoint
            switch best.edge {
            case .below:
                origin = CGPoint(x: centredX, y: best.space.lower)
            case .above:
                origin = CGPoint(x: centredX, y: best.space.upper - height)
            case .leading, .trailing:
                let top = clamp(primary.midY - height / 2, best.space.lower, best.space.upper - height)
                origin = CGPoint(x: sideX, y: top)
            }
            return result(origin: origin, edge: best.edge, height: height, maxHeight: available < cardHeight ? available : nil)
        }

        /// The free stretch for a card on `edge`: from the spotlight to the
        /// safe area for below and above, the tallest free stretch beside it
        /// for a side.
        private func space(_ edge: TourCardEdge) -> Stretch {
            switch edge {
            case .below:
                return freeStretch(Stretch(lower: primary.maxY + gap, upper: safe.maxY), column: centredX, anchoredAtLower: true)
            case .above:
                return freeStretch(Stretch(lower: safe.minY, upper: primary.minY - gap), column: centredX, anchoredAtLower: false)
            case .leading, .trailing:
                return freeStretch(Stretch(lower: safe.minY, upper: safe.maxY), column: sideX, anchoredAtLower: nil)
            }
        }

        /// The part of `range` that no obstacle crossing the card's column
        /// takes. With `anchoredAtLower` set, only the stretch that begins
        /// (true) or ends (false) at the range's own edge counts, so a card
        /// meant to hug the spotlight does. Without it, the tallest wins.
        private func freeStretch(_ range: Stretch, column: CGFloat, anchoredAtLower: Bool?) -> Stretch {
            let empty = Stretch(lower: range.lower, upper: range.lower)
            guard range.length > 0 else { return empty }
            let crossing = obstacles
                .filter { $0.minX < column + width && $0.maxX > column }
                .sorted { $0.minY < $1.minY }
            var stretches: [Stretch] = []
            var cursor = range.lower
            for obstacle in crossing {
                if obstacle.minY > cursor {
                    stretches.append(Stretch(lower: cursor, upper: min(obstacle.minY, range.upper)))
                }
                cursor = max(cursor, obstacle.maxY)
                if cursor >= range.upper { break }
            }
            if cursor < range.upper {
                stretches.append(Stretch(lower: cursor, upper: range.upper))
            }
            stretches = stretches.filter { $0.length > 0 }
            let chosen: Stretch?
            switch anchoredAtLower {
            case true:
                chosen = stretches.first { $0.lower == range.lower }
            case false:
                chosen = stretches.first { $0.upper == range.upper }
            case nil:
                chosen = stretches.max { $0.length < $1.length }
            }
            return chosen ?? empty
        }
    }

    /// A vertical span. Unlike a `ClosedRange`, it may be empty or inverted
    /// without trapping, which happens when a spotlight leaves no room.
    private struct Stretch {
        let lower: CGFloat
        let upper: CGFloat

        var length: CGFloat { max(0, upper - lower) }
    }
}

/// `value` held within `lower...upper`, preferring `lower` when the range is
/// inverted.
private nonisolated func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
    min(max(value, lower), max(lower, upper))
}
