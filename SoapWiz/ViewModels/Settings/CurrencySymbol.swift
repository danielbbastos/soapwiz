import Foundation

/// Maps an ISO 4217 currency code to the SF Symbol drawn for it.
enum CurrencySymbol {
    static let fallbackSymbolName = "banknote.fill"

    /// Currency codes grouped by the SF Symbol sign that draws them.
    private static let codesBySign: [String: [String]] = [
        "dollarsign": ["USD", "CAD", "AUD", "NZD", "MXN", "SGD", "HKD", "TWD", "ARS", "CLP", "COP", "BND"],
        "eurosign": ["EUR"],
        "sterlingsign": ["GBP"],
        "yensign": ["JPY", "CNY"],
        "indianrupeesign": ["INR"],
        "wonsign": ["KRW"],
        "rublesign": ["RUB"],
        "turkishlirasign": ["TRY"],
        "brazilianrealsign": ["BRL"],
        "shekelsign": ["ILS"],
        "hryvniasign": ["UAH"],
        "dongsign": ["VND"],
        "bahtsign": ["THB"],
        "pesosign": ["PHP"],
        "nairasign": ["NGN"],
        "tengesign": ["KZT"],
        "rupeesign": ["PKR"]
    ]

    /// Every mapped code with its symbol name.
    static let symbolNames: [String: String] = {
        var names: [String: String] = [:]
        for (sign, codes) in codesBySign {
            for code in codes {
                names[code] = "\(sign).circle.fill"
            }
        }
        return names
    }()

    /// The symbol for `code`, ignoring case. Unmapped and empty codes get a generic banknote.
    static func symbolName(forCurrencyCode code: String) -> String {
        symbolNames[code.uppercased()] ?? fallbackSymbolName
    }
}
