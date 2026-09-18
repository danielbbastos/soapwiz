import SwiftUI

/// A red warning shown above a soap-property breakdown when one or more oils in
/// the blend have no fatty acid data. Those oils contribute nothing to the
/// weighted numbers, so the breakdown under-reports; naming them tells the user
/// which ones to fix. Renders nothing when every oil has a profile.
struct IncompleteFattyAcidWarningRow: View {
    let oilNames: [String]

    var body: some View {
        if !oilNames.isEmpty {
            Text("\(Image(systemName: "exclamationmark.triangle")) \(RecipeStatsCopy.incompleteSoapProperties(names: oilNames))")
                .font(.footnote)
                .foregroundStyle(.red)
                .listRowSeparator(.hidden)
        }
    }
}
