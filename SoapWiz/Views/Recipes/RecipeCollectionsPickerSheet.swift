import SwiftUI
import SwiftData

/// Multi-select filing for one recipe, reached from the recipe list's
/// long-press menu.
///
/// A sheet rather than a submenu inside the context menu: SwiftUI snapshots
/// `.contextMenu` content when it is presented and never re-evaluates it, so a
/// menu row's checkmark cannot follow the tap that changed it. Keeping the menu
/// open (`menuActionDismissBehavior(.disabled)`) without that feedback is worse
/// than closing it — the second tap on a row that looks unchanged silently
/// undoes the first.
///
/// Changes apply as they are made, like the favourite star; "Done" only closes.
struct RecipeCollectionsPickerSheet: View {
    let recipe: Recipe
    let onToggle: (RecipeCollection) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \RecipeCollection.name) private var collections: [RecipeCollection]

    @State private var showingNewCollection = false

    var body: some View {
        NavigationStack {
            Group {
                if collections.isEmpty {
                    ContentUnavailableView {
                        Label("No Collections", systemImage: "square.stack")
                    } description: {
                        Text("Group recipes into themes like \"Christmas\" or \"Gifts\".")
                    } actions: {
                        Button("New Collection") { showingNewCollection = true }
                    }
                } else {
                    List {
                        ForEach(collections) { collection in
                            Button {
                                onToggle(collection)
                            } label: {
                                row(collection)
                            }
                        }
                        .listRowBackground(Color.cardBackground)
                    }
                }
            }
            .navigationTitle(recipe.name)
            .navigationBarTitleDisplayMode(.inline)
            .warmNavigationTitle(recipe.name)
            .warmBackground()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("New Collection", systemImage: "plus") { showingNewCollection = true }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingNewCollection) {
                RecipeCollectionFormView { newCollection in
                    onToggle(newCollection)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ collection: RecipeCollection) -> some View {
        let isMember = recipe.isFiled(under: collection)
        return HStack {
            Circle()
                .fill(collection.color.tint)
                .frame(width: 12, height: 12)
            Text(collection.name)
                .foregroundStyle(.primary)
            Spacer()
            Image(systemName: "checkmark")
                .foregroundStyle(.tint)
                .opacity(isMember ? 1 : 0)
        }
        .contentShape(.rect)
        .accessibilityAddTraits(isMember ? .isSelected : [])
    }
}
