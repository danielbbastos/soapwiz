import Foundation
import SwiftUI

enum SoapQuality: String, CaseIterable, Identifiable {
    case hardness, cleansing, conditioning, bubbly, creamy, longevity

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .hardness: "Hardness"
        case .cleansing: "Cleansing"
        case .conditioning: "Condition"
        case .bubbly: "Bubbly"
        case .creamy: "Creamy"
        case .longevity: "Longevity"
        }
    }

    var shortName: String {
        switch self {
        case .hardness: "Hard"
        case .cleansing: "Clean"
        case .conditioning: "Cond"
        case .bubbly: "Bub"
        case .creamy: "Cream"
        case .longevity: "Life"
        }
    }

    var recommendedRange: ClosedRange<Double> {
        switch self {
        case .hardness: 29...54
        case .cleansing: 12...22
        case .conditioning: 44...69
        case .bubbly: 14...46
        case .creamy: 16...48
        case .longevity: 16...48
        }
    }

    var color: Color {
        switch self {
        case .hardness: .brown
        case .cleansing: .blue
        case .conditioning: .teal
        case .bubbly: .red
        case .creamy: .yellow
        case .longevity: .green
        }
    }

    func value(from profile: FattyAcidProfile) -> Double {
        switch self {
        case .hardness: profile.hardness
        case .cleansing: profile.cleansing
        case .conditioning: profile.conditioning
        case .bubbly: profile.bubbly
        case .creamy: profile.creamy
        case .longevity: profile.longevity
        }
    }
}

enum SoapMetric {
    static let insRange: ClosedRange<Double> = 136...170
    static let insScale: ClosedRange<Double> = 0...320
    static let iodineRange: ClosedRange<Double> = 41...70
    static let iodineScale: ClosedRange<Double> = 0...200
}
