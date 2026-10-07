import SwiftUI

struct FloatingActionButton: View {
    /// The glass tint, and the solid fill before iOS 26 (where `Color.amber`
    /// stands in for it). Nil keeps the app's yellow `FABTint` and accent.
    var tint: Color?
    /// The `+`. Nil keeps `FABInk`, and white before iOS 26.
    var ink: Color?
    let action: () -> Void

    init(tint: Color? = nil, ink: Color? = nil, action: @escaping () -> Void) {
        self.tint = tint
        self.ink = ink
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .frame(width: 56, height: 56)
        }
        .modifier(FABStyle(tint: tint, ink: ink))
        .padding(.trailing, 20)
        .padding(.bottom, 20)
    }
}

private struct FABStyle: ViewModifier {
    let tint: Color?
    let ink: Color?

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .foregroundStyle(ink ?? Color.fabInk)
                .glassEffect(glass, in: .circle)
        } else {
            content
                .foregroundStyle(ink ?? .white)
                .background(tint == nil ? Color.accentColor : Color.amber)
                .clipShape(Circle())
                .shadow(radius: 4, y: 2)
        }
    }

    @available(iOS 26, *)
    private var glass: Glass {
        guard let tint else { return .floatingActionButton }
        return .clear.tint(tint).interactive()
    }
}
