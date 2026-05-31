import SwiftUI

/// Helpers for sanitizing input that arrives from hardware barcode scanners
/// configured as USB keyboard wedges.
///
/// Scanner guns commonly append a carriage-return suffix to terminate each scan,
/// and some configurations emit additional control bytes (NUL, GS, RS, US) or
/// — when programmed for Windows ALT+keypad sequences that macOS does not honor —
/// leak unintended keypad digits into the focused text field. Stripping all
/// Unicode control characters keeps search text clean regardless of how the
/// scanner is configured.
extension String {
    /// Returns the string with every Unicode control character removed.
    /// Internal whitespace is preserved; only control codes are filtered.
    func strippingControlCharacters() -> String {
        components(separatedBy: .controlCharacters).joined()
    }
}

extension Binding where Value == String {
    /// Wraps the binding so any value being assigned has Unicode control characters
    /// removed first. Apply to text fields fed by hardware barcode scanners so
    /// trailing CR/LF and other control bytes don't contaminate the displayed value
    /// or the downstream search query.
    func strippingControlCharacters() -> Binding<String> {
        Binding(
            get: { wrappedValue },
            set: { wrappedValue = $0.strippingControlCharacters() }
        )
    }
}

//endofline
