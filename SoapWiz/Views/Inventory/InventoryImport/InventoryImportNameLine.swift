import SwiftUI

/// A small text button of an import row: subheadline semibold with a 44pt tap
/// height that doesn't take layout space, the look unchanged. Several buttons
/// share one list row, so it takes `.borderless` and keeps the row from
/// lighting as one.
///
/// The hit area grows past the text on both sides. A button right under a
/// toggle grows only downward, so it can't cover the toggle above it; whatever
/// comes later in the row wins the overlap below.
struct InventoryImportRowButton: View {
    private static let reach: CGFloat = 12

    let title: LocalizedStringKey
    let color: Color
    let growsUp: Bool
    var action: () -> Void

    init(
        _ title: LocalizedStringKey,
        color: Color = .amberText,
        growsUp: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.color = color
        self.growsUp = growsUp
        self.action = action
    }

    private var topReach: CGFloat {
        growsUp ? Self.reach : 0
    }

    private var bottomReach: CGFloat {
        growsUp ? Self.reach : Self.reach * 2
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .padding(.top, topReach)
                .padding(.bottom, bottomReach)
                .contentShape(.rect)
                .padding(.top, -topReach)
                .padding(.bottom, -bottomReach)
        }
        .buttonStyle(.borderless)
    }
}

/// The top of an ingredient's row, shared by the entry rows and by "Can't
/// Import": its name with Change at the trailing edge (Match to existing for a
/// new ingredient), what `stamp` adds under it, and Undo change once the user
/// has re-pointed it, so a rematch that blocked every row stays undoable. With
/// no `entry` there are no actions. At accessibility text sizes Change moves
/// under the name.
struct InventoryImportNameLine<Stamp: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let model: InventoryImportReviewViewModel
    let name: String
    let nameColor: Color
    let entry: InventoryImportEntry?
    var onChange: () -> Void
    private let stamp: Stamp

    init(
        model: InventoryImportReviewViewModel,
        name: String,
        nameColor: Color = .ink,
        entry: InventoryImportEntry?,
        onChange: @escaping () -> Void,
        @ViewBuilder stamp: () -> Stamp
    ) {
        self.model = model
        self.name = name
        self.nameColor = nameColor
        self.entry = entry
        self.onChange = onChange
        self.stamp = stamp()
    }

    private var layout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
    }

    private var canUndo: Bool {
        guard let entry else { return false }
        return model.canResetToNew(entry) || model.canResetMatch(entry)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            layout {
                Text(name)
                    .foregroundStyle(nameColor)
                if let entry {
                    if !dynamicTypeSize.isAccessibilitySize {
                        Spacer(minLength: 0)
                    }
                    InventoryImportRowButton(entry.isNew ? "Match to existing" : "Change", action: onChange)
                }
            }
            stamp
            if let entry, canUndo {
                InventoryImportRowButton("Undo change", color: .inkSoft) {
                    InventoryImportMotion.animate {
                        model.resetMatch(entry: entry.id)
                    }
                }
                .importTransition(.reveal)
            }
        }
    }
}

extension InventoryImportNameLine where Stamp == EmptyView {
    init(
        model: InventoryImportReviewViewModel,
        name: String,
        nameColor: Color = .ink,
        entry: InventoryImportEntry?,
        onChange: @escaping () -> Void
    ) {
        self.init(model: model, name: name, nameColor: nameColor, entry: entry, onChange: onChange) { EmptyView() }
    }
}
