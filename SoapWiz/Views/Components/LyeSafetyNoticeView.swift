import SwiftUI

/// The lye safety text, shown once as a sheet and kept readable in Settings.
///
/// Set in the Honey Ledger tokens: `danger` on `dangerWash` for the warning,
/// `amberText` on `honey` for the instructions, `ink` and `inkSoft` for text.
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
                .font(.headline.weight(.semibold))
                .fontDesign(.serif)
                .foregroundStyle(Color.danger)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 4)
    }

    private var header: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(Color.danger)
                .frame(width: 64, height: 64)
                .background(Color.dangerWash, in: .circle)
                .overlay(Circle().stroke(Color.danger.opacity(0.38), lineWidth: 1))
            Text("Handle Lye with Care")
                .font(.title.weight(.semibold))
                .fontDesign(.serif)
                .foregroundStyle(Color.ink)
                .multilineTextAlignment(.center)
            Text("Lye (sodium or potassium hydroxide) is caustic. It can burn skin and damage eyes.")
                .foregroundStyle(Color.inkSoft)
                .multilineTextAlignment(.center)
        }
    }

    private func bullet(symbol: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.system(size: 18))
                .foregroundStyle(Color.amberText)
                .frame(width: 40, height: 40)
                .background(Color.honey, in: .rect(cornerRadius: 12))
            Text(text)
                .foregroundStyle(Color.ink)
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
            .foregroundStyle(Color.inkSoft)
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
        .readableWidth(inset: 16)
        .navigationTitle("Lye Safety")
        .navigationBarTitleDisplayMode(.inline)
        .honeyLedgerInlineTitle("Lye Safety")
        .ledgerBackground()
    }
}

#Preview {
    ScrollView { LyeSafetyNoticeView().padding() }
        .background { HoneyLedgerPaper() }
}
