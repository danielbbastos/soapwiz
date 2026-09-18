import SwiftUI

/// The lye safety text, shown once as a sheet and kept readable in Settings.
///
/// Colours come from the asset catalogue rather than the mock's hex values, so
/// the gold and the red both follow the app into light mode. The one new colour
/// is `dangerAccent`, which had no equivalent: nothing else in the app has had
/// to say "this can hurt you".
///
/// No card behind the text: the notice fills the sheet, which keeps the lines
/// wide enough to fit without scrolling.
struct LyeSafetyNoticeView: View {
    var body: some View {
        VStack(spacing: 24) {
            header
            bullet(
                symbol: "shield",
                text: "Wear gloves, long sleeves and eye protection, and work somewhere ventilated, "
                    + "away from children and pets."
            )
            bullet(
                symbol: "function",
                text: "SoapWiz calculates from the numbers you enter: SAP values, lye purity, superfat "
                    + "and water. Check every lye amount with a second soap calculator before you make "
                    + "a batch."
            )
            Text("Always add lye to water — never water to lye.")
                .font(.system(.headline, design: .rounded, weight: .heavy))
                .foregroundStyle(Color.dangerAccent)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 4)
    }

    private var header: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(Color.dangerAccent)
                .frame(width: 64, height: 64)
                .background(Color.dangerAccent.opacity(0.14), in: .circle)
                .overlay(Circle().stroke(Color.dangerAccent.opacity(0.38), lineWidth: 1))
            Text("Handle Lye with Care")
                .font(.system(.title, design: .rounded, weight: .heavy))
                .multilineTextAlignment(.center)
            Text("Lye (sodium or potassium hydroxide) is caustic. It can burn skin and damage eyes.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func bullet(symbol: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .foregroundStyle(Color.accentColor)
                .frame(width: 40, height: 40)
                .background(Color.accentColor.opacity(0.14), in: .rect(cornerRadius: 12))
            Text(text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The liability line, set as fine print beneath the notice and above the
/// button rather than in the body: it qualifies the whole notice, so it reads
/// as a footer to it rather than a fourth instruction.
struct LyeSafetyDisclaimer: View {
    var body: some View {
        Text("SoapWiz can't guarantee a safe result. You use its calculations at your own risk.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }
}

/// The notice as a screen of its own, for Settings → About.
struct LyeSafetyScreen: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                LyeSafetyNoticeView()
                LyeSafetyDisclaimer()
            }
            .padding()
        }
        .navigationTitle("Lye Safety")
        .navigationBarTitleDisplayMode(.inline)
        .warmNavigationTitle("Lye Safety")
        .warmBackground()
    }
}

#Preview {
    ScrollView { LyeSafetyNoticeView().padding() }
        .background(Color.warmBackground)
}
