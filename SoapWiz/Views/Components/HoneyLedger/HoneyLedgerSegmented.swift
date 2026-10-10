import SwiftUI

/// A two- to four-way choice per the Segmented component: a sunken
/// `paperSunken` track with a `ruleStrong` hairline, and the selected option
/// raised on it like a paper tab, its label `ink` semibold. The other labels
/// are `inkSoft`. Segments share the width equally; a label that doesn't fit
/// shrinks rather than truncating.
///
/// Each segment is its own button, so VoiceOver reads them as a group of
/// choices with the selected one marked.
struct HoneyLedgerSegmented<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [(value: Value, label: String)]

    @Namespace private var selectionNamespace

    init(_ title: String, selection: Binding<Value>, options: [(value: Value, label: String)]) {
        self.title = title
        self._selection = selection
        self.options = options
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                segment(option.value, label: option.label)
            }
        }
        .padding(3)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.paperSunken.shadow(.inner(color: Color.shadow.opacity(0.2), radius: 1, y: 1)))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.ruleStrong, lineWidth: 1)
        }
        // In a list row the separator would otherwise start under the first
        // segment's label.
        .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(title))
    }

    private func segment(_ value: Value, label: String) -> some View {
        let isSelected = value == selection
        return Button {
            withAnimation(.snappy(duration: 0.2)) { selection = value }
        } label: {
            Text(label)
                .font(.subheadline.weight(isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? Color.ink : Color.inkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                // Capped, as the system segmented control is: past this size a
                // label breaks mid-word. Holding a segment shows it full size.
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .padding(.horizontal, 4)
                .padding(.vertical, 3)
                .frame(maxWidth: .infinity, minHeight: 26)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.paperRaised)
                            .shadow(color: Color.shadow.opacity(0.2), radius: 1, y: 1)
                            .shadow(color: Color.shadow.opacity(0.12), radius: 6, y: 4)
                            .matchedGeometryEffect(id: "selection", in: selectionNamespace)
                    }
                }
                // A 44pt hit area around the 26pt segment, laid out at its
                // drawn size.
                .padding(.vertical, 9)
                .contentShape(.rect)
                .padding(.vertical, -9)
        }
        .buttonStyle(.plain)
        .accessibilityShowsLargeContentViewer {
            Text(label)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
