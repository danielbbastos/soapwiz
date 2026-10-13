import SwiftUI

/// A raised `paperRaised` card with the tour's two-layer lift shadow.
struct TourCardSurface: View {
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.paperRaised)
            .shadow(color: Color.shadow.opacity(0.10), radius: 12, y: 8)
            .shadow(color: Color.shadow.opacity(0.12), radius: 1, y: 1)
    }
}
