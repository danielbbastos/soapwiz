import Testing
import UIKit
@testable import SoapWiz

@Suite
struct CurrencySymbolTests {

    @Test func symbolNames_EveryMappedName_ResolvesToSystemImage() {
        #expect(!CurrencySymbol.symbolNames.isEmpty)
        for (code, name) in CurrencySymbol.symbolNames {
            let image = UIImage(systemName: name)
            #expect(image != nil, "\(code) maps to missing symbol \(name)")
        }
    }

    @Test func fallbackSymbolName_ResolvesToSystemImage() {
        #expect(UIImage(systemName: CurrencySymbol.fallbackSymbolName) != nil)
    }

    @Test func symbolName_Euro_ReturnsEuroSign() {
        #expect(CurrencySymbol.symbolName(forCurrencyCode: "EUR") == "eurosign.circle.fill")
    }

    @Test func symbolName_Dollar_ReturnsDollarSign() {
        #expect(CurrencySymbol.symbolName(forCurrencyCode: "USD") == "dollarsign.circle.fill")
        #expect(CurrencySymbol.symbolName(forCurrencyCode: "CAD") == "dollarsign.circle.fill")
    }

    @Test func symbolName_Sterling_ReturnsSterlingSign() {
        #expect(CurrencySymbol.symbolName(forCurrencyCode: "GBP") == "sterlingsign.circle.fill")
    }

    @Test func symbolName_LowercaseCode_MatchesCaseInsensitively() {
        #expect(CurrencySymbol.symbolName(forCurrencyCode: "eur") == "eurosign.circle.fill")
    }

    @Test func symbolName_UnmappedCode_ReturnsFallback() {
        #expect(CurrencySymbol.symbolName(forCurrencyCode: "CHF") == CurrencySymbol.fallbackSymbolName)
        #expect(CurrencySymbol.symbolName(forCurrencyCode: "XYZ") == CurrencySymbol.fallbackSymbolName)
    }

    @Test func symbolName_EmptyCode_ReturnsFallback() {
        #expect(CurrencySymbol.symbolName(forCurrencyCode: "") == CurrencySymbol.fallbackSymbolName)
    }
}
