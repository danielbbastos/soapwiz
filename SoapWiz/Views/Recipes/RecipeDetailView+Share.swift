import SwiftUI

/// Sharing a recipe out of the detail screen as a `.soapwizrecipe` file.
///
/// Kept apart from the screen's own body because it is a self-contained errand:
/// write the payload, hand the URL to the system, say so if it failed. None of
/// it touches the recipe being displayed.
extension RecipeDetailView {

    /// Share sits beside Edit rather than in a menu behind it: sending a recipe
    /// to someone is a thing people do often enough that burying it costs more
    /// than the toolbar space it takes.
    @ToolbarContentBuilder
    var shareToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                share()
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
    }

    /// The share sheet and the message shown when the file couldn't be written.
    var sharingPresentation: some ViewModifier {
        RecipeShareModifier(file: $exportFile, errorMessage: $exportErrorMessage)
    }

    /// Writes the recipe out and hands it to the share sheet.
    ///
    /// Called when the user taps Share rather than ahead of time, so viewing a
    /// recipe never writes a file the user didn't ask for.
    func share() {
        do {
            exportFile = try RecipeTransferExport.file(for: [recipe])
        } catch {
            exportErrorMessage = "Couldn’t prepare this recipe for sharing. Please try again."
        }
    }
}

/// Presents the share sheet, and the alert for a share that couldn't be
/// prepared. A modifier rather than two chained modifiers on the detail view, so
/// the screen's body reads as one line about sharing rather than fifteen.
private struct RecipeShareModifier: ViewModifier {
    @Binding var file: ExportFile?
    @Binding var errorMessage: String?

    func body(content: Content) -> some View {
        content
            .sheet(item: $file) { file in
                ShareSheet(items: [file.url])
            }
            .alert(
                "Couldn’t share",
                isPresented: Binding(
                    get: { errorMessage != nil },
                    set: { if !$0 { errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
    }
}
