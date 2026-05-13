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

private struct FABStyle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content
                .glassEffect(.regular.interactive(), in: .circle)
        } else {
            content
                .foregroundStyle(.white)
                .background(Color.accentColor)
                .clipShape(Circle())
                .shadow(radius: 4, y: 2)
        }
    }
}
