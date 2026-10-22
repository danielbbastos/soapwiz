import SwiftUI

/// Why an import produced nothing, with the way back to the text.
struct RecipeImportFailureView: View {
    let error: RecipeImportError
    var onBack: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            HoneyLedgerEmptyState(
                LocalizedStringKey(error.errorDescription ?? "Import failed"),
                systemImage: "text.badge.xmark",
                description: LocalizedStringKey(error.recoverySuggestion ?? "")
            )
            .fixedSize(horizontal: false, vertical: true)
            Button("Back to Text") { onBack() }
                .fontWeight(.semibold)
                .foregroundStyle(Color.amberText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
