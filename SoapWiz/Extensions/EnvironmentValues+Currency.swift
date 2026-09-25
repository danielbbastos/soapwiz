import SwiftUI

extension EnvironmentValues {
    /// The ISO code every price is shown in, injected once at the root from
    /// `AppSettings` so a currency change synced from another device relabels
    /// every screen.
    @Entry var currencyCode: String = AppSettings.regionCurrencyCode()
}
