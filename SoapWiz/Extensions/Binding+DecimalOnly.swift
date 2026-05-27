import SwiftUI

extension Binding where Value == String {
    func decimalOnly() -> Binding<String> {
        Binding(
            get: { wrappedValue },
            set: { wrappedValue = $0.filter { $0.isNumber || $0 == "." || $0 == "," } }
        )
    }
}
