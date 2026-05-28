import SwiftUI

extension Binding where Value == String {
    func decimalOnly() -> Binding<String> {
        Binding(
            get: { wrappedValue },
            set: {
                let filtered = $0.filter { $0.isNumber || $0 == "." || $0 == "," }
                let normalised = filtered.replacingOccurrences(of: ",", with: ".")
                let parts = normalised.components(separatedBy: ".")
                wrappedValue = parts.count > 2 ? parts.prefix(2).joined(separator: ".") : normalised
            }
        )
    }
}
