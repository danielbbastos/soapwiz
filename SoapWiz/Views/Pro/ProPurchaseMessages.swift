import SwiftUI

struct ProReasonBox: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(Color.amberText)
                .accessibilityHidden(true)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(Color.honey, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct ProPendingBox: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StatusStamp(word: "Waiting for approval", tone: .warning, glyph: "clock")
            Text("Someone in your family needs to approve this purchase. "
                 + "SoapWiz Pro unlocks by itself once they do, so you can close this.")
                .font(.subheadline)
                .foregroundStyle(Color.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .messageBox(fill: .warningWash, edge: .warning)
    }
}

struct ProFailedBox: View {
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Color.danger)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("The purchase didn’t go through")
                    .font(.subheadline.bold())
                    .foregroundStyle(Color.danger)
                Text("Check your internet connection and try again.")
                    .font(.subheadline)
                    .foregroundStyle(Color.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .messageBox(fill: .dangerWash, edge: .danger)
        .accessibilityElement(children: .combine)
    }
}

private extension View {
    func messageBox(fill: Color, edge: Color) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return self
            .background(fill, in: shape)
            .overlay(shape.strokeBorder(edge, lineWidth: 1))
    }
}
