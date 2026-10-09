import SwiftUI

/// Which colour pair a `StatusStamp` is struck in.
enum StatusStampTone {
    case danger
    case warning
    case success
    case amber
    case neutral

    var ink: Color {
        switch self {
        case .danger:  Color.danger
        case .warning: Color.warning
        case .success: Color.success
        case .amber:   Color.amberText
        case .neutral: Color.inkSoft
        }
    }

    var wash: Color {
        switch self {
        case .danger:  Color.dangerWash
        case .warning: Color.warningWash
        case .success: Color.successWash
        case .amber:   Color.honey
        case .neutral: Color.paperSunken
        }
    }
}

/// A small outlined word, like a rubber stamp, marking a status on a row.
///
/// Always carries a word: the colour and the glyph are reinforcement, never the
/// only carrier. The glyph is hidden from VoiceOver so only the word is read.
///
/// `isInked` strikes it larger and slightly crooked, as if pressed by hand. That
/// is for a batch whose cure is over, wherever that status appears: the batch
/// screen and the history list.
struct StatusStamp: View {
    let word: String
    let tone: StatusStampTone
    var glyph: String?
    var isInked = false

    var body: some View {
        HStack(spacing: 4) {
            if let glyph {
                Image(systemName: glyph)
                    .accessibilityHidden(true)
            }
            Text(word)
        }
        .font(isInked ? .subheadline.weight(.bold) : .caption.weight(.bold))
        .textCase(.uppercase)
        .tracking(0.9)
        .foregroundStyle(tone.ink)
        .padding(.horizontal, isInked ? 12 : 8)
        .padding(.vertical, isInked ? 5 : 2)
        .background(tone.wash, in: shape)
        .overlay(shape.strokeBorder(tone.ink, lineWidth: 1))
        .fixedSize(horizontal: false, vertical: true)
        .rotationEffect(.degrees(isInked ? -2.5 : 0))
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
    }
}
