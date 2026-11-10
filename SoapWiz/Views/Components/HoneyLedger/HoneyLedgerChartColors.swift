import SwiftUI

// The soap-properties bar colours. Most are pigments under another name, so
// they point at the pigment's colour set rather than repeating its values;
// creamy and the range band have colour sets of their own.
extension Color {
    static let chartHardness = Color.pigmentWalnut
    static let chartCleansing = Color.pigmentWoad
    static let chartConditioning = Color.pigmentVerdigris
    static let chartBubbly = Color.pigmentMadder
    static let chartLongevity = Color.pigmentOlive

    /// The batch heatmap's cell shade for a level from 0 (none) to 3 (3+).
    static func heatmapLevel(_ level: Int) -> Color {
        switch level {
        case ..<1: .heatmapLevel0
        case 1: .heatmapLevel1
        case 2: .heatmapLevel2
        default: .heatmapLevel3
        }
    }
}
