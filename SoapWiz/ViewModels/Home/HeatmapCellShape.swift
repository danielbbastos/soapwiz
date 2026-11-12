import CoreGraphics

/// The proportions of a heatmap cell on the phone grid.
enum HeatmapCellShape {
    /// The widest a cell may be against its height.
    static let maximumAspectRatio: CGFloat = 1.5

    /// A cell's height for its width: `minimum` while the cell is no wider than
    /// that allows, then growing with the width.
    static func height(forWidth width: CGFloat, minimum: CGFloat) -> CGFloat {
        guard width.isFinite, width > 0 else { return minimum }
        return max(minimum, width / maximumAspectRatio)
    }
}
