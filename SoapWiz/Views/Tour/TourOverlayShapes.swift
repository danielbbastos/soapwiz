import SwiftUI

extension CGRect {
    /// A zero-size rect at this one's centre, for a hole that isn't there yet.
    var centrePoint: CGRect {
        CGRect(x: midX, y: midY, width: 0, height: 0)
    }
}

/// The card and spotlights of the step that is leaving.
struct TourLeaving: Equatable {
    let step: TourOverlayStep
    let cutouts: [TourCutout]
    let placement: TourCardPlacement.Result?
}

/// A step change under way. Nothing is leaving the first time the overlay
/// appears.
struct TourChange: Equatable {
    let start: Date
    let leaving: TourLeaving?
}

/// What changes the overlay: the step, where its targets are, and where its
/// card goes.
struct TourSpotlightKey: Equatable {
    let index: Int
    let cutouts: [TourCutout]
    let placement: TourCardPlacement.Result?
}

/// What is drawn at one moment of a step change. `hole` is how far the
/// cutouts are filled back in, `ring` how visible their rings are.
struct TourFrame {
    let cutouts: [TourCutout]
    let hole: Double
    let ring: Double
    let cardStep: TourOverlayStep
    let placement: TourCardPlacement.Result?
    let cardOpacity: Double
}

/// A spotlight's rounded rectangle.
struct TourCutout: Equatable {
    var rect: CGRect
    var cornerRadius: CGFloat
}

/// The whole container with a hole per cutout, for an even-odd fill.
struct TourDimShape: Shape {
    var first: TourCutout
    var second: TourCutout

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        path.addPath(TourHoleShape(first: first, second: second).path(in: rect))
        return path
    }
}

/// Just the cutouts, to fill a hole back in.
struct TourHoleShape: Shape {
    var first: TourCutout
    var second: TourCutout

    func path(in rect: CGRect) -> Path {
        var path = Path()
        for cutout in [first, second] where cutout.rect.width > 0 && cutout.rect.height > 0 {
            path.addPath(RoundedRectangle(cornerRadius: cutout.cornerRadius, style: .continuous).path(in: cutout.rect))
        }
        return path
    }
}

/// The cutout's outline pushed out by `outset`, so a stroke centred on it
/// sits wholly outside the lit area.
struct TourRingShape: Shape {
    var cutout: TourCutout
    let outset: CGFloat

    func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: cutout.cornerRadius + outset, style: .continuous)
            .path(in: cutout.rect.insetBy(dx: -outset, dy: -outset))
    }
}
