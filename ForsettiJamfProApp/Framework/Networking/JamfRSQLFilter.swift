import Foundation

// "End of Line"

/// Pure-function helpers for building Jamf Pro RSQL filter expressions.
///
/// Extracted from `MobileDeviceSearchViewModel` and the mobile search
/// path in `SupportTechnicianAPIService` so both call sites share a
/// single, tested implementation of the grammar instead of drifting.
///
/// Jamf Pro's RSQL grammar:
///
/// - **Logical OR**: `,` (comma) — unioning two conditions
/// - **Logical AND**: `;` (semicolon) — intersecting two conditions
/// - **Equality**: `=='value'` — single-quoted string literal
/// - **Wildcard**: `*` inside the quoted value (e.g. `*foo*`)
/// - **Escapes**: backslash before backslash or single quote
///
/// The literal word `or` is NOT valid RSQL syntax — strict Jamf parsers
/// return HTTP 400; lenient parsers silently match nothing. This was the
/// bug the audit report flagged: the two mobile search paths were
/// emitting `(serialNumber=='…' or username=='…')` and losing searches
/// on strict tenants.
///
/// `nonisolated` keeps these pure static functions callable from actor
/// contexts such as `SupportTechnicianAPIService`, independent of any
/// target-level actor isolation defaults.
enum JamfRSQLFilter {
    /// Builds a filter expression that matches a query against either a
    /// serial-number field or a username field. Returns `nil` for an
    /// empty/whitespace-only query so callers can skip sending a
    /// `filter=` query parameter entirely.
    ///
    /// Output shape: `(<serialField>=='<value>',<usernameField>=='<value>')`
    ///
    /// The parentheses keep the OR group cleanly composable if the
    /// caller wants to AND it with other conditions later.
    ///
    /// - Parameters:
    ///   - query: The user-entered search string.
    ///   - useWildcard: Whether to wrap the query in wildcard `*` characters.
    ///   - serialField: The Jamf inventory field for serial number.
    ///     Defaults to `"serialNumber"`.
    ///   - usernameField: The Jamf inventory field for username.
    ///     Defaults to `"username"`.
    /// - Returns: The RSQL filter string, or `nil` for an empty query.
    nonisolated static func serialOrUsername(
        query: String,
        useWildcard: Bool,
        serialField: String = "serialNumber",
        usernameField: String = "username"
    ) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        let escaped = escapeSingleQuoted(trimmed)
        let value = useWildcard ? "*\(escaped)*" : escaped

        return "(\(serialField)=='\(value)',\(usernameField)=='\(value)')"
    }

    /// Escapes backslashes and single quotes for safe inclusion inside
    /// an RSQL single-quoted string literal.
    nonisolated static func escapeSingleQuoted(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
    }

    /// Builds a single equality (or inequality) RSQL fragment for one
    /// field/value pair, with optional wildcard wrap.
    ///
    /// Output shape: `field=='value'` (or `field!='value'`). When `wildcard`
    /// is non-`.none` the value is bracketed with `*` characters AFTER
    /// escaping so user-typed literal asterisks don't accidentally turn into
    /// wildcards (the existing `serialOrUsername` codepath has always done it
    /// this way and the audit specifically called it out). Used by
    /// `JamfRSQLComposer` for criterion-by-criterion composition; the
    /// existing `serialOrUsername` helper continues to use its own inlined
    /// formatting for back-compat.
    ///
    /// - Parameters:
    ///   - field: The Jamf inventory field name (matches the filter docs).
    ///   - value: The user-supplied literal. Escaped before quoting.
    ///   - wildcard: How to wrap the value with `*` characters.
    ///   - negated: When `true`, emits `!=` instead of `==`.
    /// - Returns: The RSQL equality fragment.
    nonisolated static func equality(
        field: String,
        value: String,
        wildcard: WildcardWrap = .none,
        negated: Bool = false
    ) -> String {
        let escaped = escapeSingleQuoted(value)
        let wrapped: String
        switch wildcard {
        case .none: wrapped = escaped
        case .leading: wrapped = "*\(escaped)"
        case .trailing: wrapped = "\(escaped)*"
        case .both: wrapped = "*\(escaped)*"
        }
        let `operator` = negated ? "!=" : "=="
        return "\(field)\(`operator`)'\(wrapped)'"
    }
}

//endofline
