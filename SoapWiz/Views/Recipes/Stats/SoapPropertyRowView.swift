import SwiftUI

/// One quality of a single oil as a compact row: name, a track with the usual
/// whole-recipe range outlined and a marker for the oil's value, the figure,
/// and an info icon. Tapping anywhere on the row opens the explanation.
struct SoapPropertyRowView: View {
    let title: String
    let value: Double
    let recommended: ClosedRange<Double>
    let scale: ClosedRange<Double>
    var infoTitle: String?
    let infoText: String

    /// The row's own minimum height, 44pt unless the list row around it already
    /// supplies that through its inset.
    var minHeight: CGFloat = 44

    /// Space above and below the two-line layout, for when the list row around
    /// it has no inset of its own to separate one quality from the next.
    var verticalPadding: CGFloat = 0

    /// Which edges take `verticalPadding`: only those facing another row, since
    /// the sheet's outer edge gets its own space.
    var paddedEdges: Edge.Set = .vertical

    /// Deliberately the device idiom rather than `horizontalSizeClass`, for the
    /// reason spelled out in `RecipeRowView`: `ContentView` pins the whole
    /// `TabView` to `.compact`, which leaves the size class saying "compact"
    /// everywhere.
    private static let isPhone = UIDevice.current.userInterfaceIdiom == .phone

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ScaledMetric(relativeTo: .body) private var nameWidth: CGFloat = 104
    @ScaledMetric(relativeTo: .body) private var valueWidth: CGFloat = 40

    @State private var showingInfo = false

    private static let trackHeight: CGFloat = 3
    private static let rangeHeight: CGFloat = 11
    private static let markerSize: CGFloat = 13

    /// Two lines, the track under the name and figure: on iPhone, where one line
    /// leaves the track short, and at the accessibility sizes on any device.
    private var isStacked: Bool {
        Self.isPhone || dynamicTypeSize.isAccessibilitySize
    }

    /// Where `value` sits along `scale`, from 0 at the lower bound to 1 at the
    /// upper, clamped. A zero-width scale reads as 0 rather than dividing by it.
    static func fraction(of value: Double, in scale: ClosedRange<Double>) -> Double {
        let span = scale.upperBound - scale.lowerBound
        guard span > 0 else { return 0 }
        return min(1, max(0, (value - scale.lowerBound) / span))
    }

    var body: some View {
        Group {
            if isStacked {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 0) {
                        nameText
                        Spacer(minLength: 8)
                        valueText
                            .frame(width: valueWidth, alignment: .trailing)
                        // Pulled out by its tap padding so the glyph, not the
                        // padding, sits on the trailing edge the track ends at.
                        infoIcon
                            .padding(.trailing, -InfoPopoverIcon.tapPadding)
                    }
                    track
                }
                .padding(paddedEdges, verticalPadding)
            } else {
                HStack(spacing: 12) {
                    nameText
                        .frame(width: nameWidth, alignment: .leading)
                    track
                    valueText
                        .frame(width: valueWidth, alignment: .trailing)
                    infoIcon
                }
            }
        }
        .frame(minHeight: minHeight)
        .contentShape(.rect)
        .onTapGesture { showingInfo = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(
            "\(value.formatted(.number.precision(.fractionLength(0)))), "
            + "usual range \(SoapPropertyIndicatorView.rangeText(recommended))"
        )
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { showingInfo = true }
    }

    private var nameText: some View {
        Text(title)
            .foregroundStyle(Color.ink)
    }

    private var valueText: some View {
        Text(value, format: .number.precision(.fractionLength(0)))
            .font(.body.weight(.semibold))
            .monospacedDigit()
            .lineLimit(1)
            .foregroundStyle(Color.ink)
    }

    private var infoIcon: some View {
        InfoPopoverIcon(title: infoTitle, text: infoText, isPresented: $showingInfo)
    }

    private var track: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let rangeStart = Self.fraction(of: recommended.lowerBound, in: scale) * width
            let rangeEnd = Self.fraction(of: recommended.upperBound, in: scale) * width
            let markerX = Self.fraction(of: value, in: scale) * width

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.chartBand)
                    .frame(height: Self.trackHeight)

                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.success.opacity(0.10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.success.opacity(0.45), lineWidth: 1)
                    )
                    .frame(width: max(0, rangeEnd - rangeStart), height: Self.rangeHeight)
                    .offset(x: rangeStart)

                Circle()
                    .fill(Color.amber)
                    .frame(width: Self.markerSize, height: Self.markerSize)
                    .overlay(Circle().stroke(Color.paperRaised, lineWidth: 2))
                    .position(x: markerX, y: geo.size.height / 2)
                    // Keyed on value so rotation and first appearance don't glide.
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: value)
                    .allowsHitTesting(false)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: isStacked ? 14 : 20)
    }
}
