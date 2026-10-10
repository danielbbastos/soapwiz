import SwiftUI

struct FloatingActionButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .frame(width: 56, height: 56)
        }
        .modifier(FABStyle())
        .padding(.trailing, 20)
        .padding(.bottom, 20)
    }
}

/// Amber glass with an `onAmber` plus on iOS 26; a solid `amber` circle with a
/// soft shadow before it.
private struct FABStyle: ViewModifier {
    func body(content: Content) -> some View {
        let label = content.foregroundStyle(Color.onAmber)
        if #available(iOS 26, *) {
            label
                .glassEffect(.floatingActionButton, in: .circle)
        } else {
            label
                .background(Color.amber)
                .clipShape(Circle())
                .shadow(radius: 4, y: 2)
        }
    }
}
