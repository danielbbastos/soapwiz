import SwiftUI

/// Which colour pair a `StatusStamp` is struck in.
enum StatusStampTone {
    case danger
    case warning

    var ink: Color {
        switch self {
        case .danger:  Color.danger
        case .warning: Color.warning
        }
    }

    var wash: Color {
        switch self {
        case .danger:  Color.dangerWash
        case .warning: Color.warningWash
        }
    }
}

/// A small outlined word, like a rubber stamp, marking a status on a row.
///
/// Always carries a word: the colour and the glyph are reinforcement, never the
/// only carrier. The glyph is hidden from VoiceOver so only the word is read.
struct StatusStamp: View {
    let word: String
    let tone: StatusStampTone
    var glyph: String?

    var body: some View {
        HStack(spacing: 4) {
            if let glyph {
                Image(systemName: glyph)
                    .accessibilityHidden(true)
            }
            Text(word)
        }
        .font(.caption.weight(.bold))
        .textCase(.uppercase)
        .tracking(0.9)
        .foregroundStyle(tone.ink)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(tone.wash, in: shape)
        .overlay(shape.strokeBorder(tone.ink, lineWidth: 1))
        .fixedSize(horizontal: false, vertical: true)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
    }
}
