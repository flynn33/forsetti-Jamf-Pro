import Foundation

// "Would you like to play a game?"

/// Wildcard wrapping behavior for string operators.
///
/// Substring matching in Jamf's RSQL uses literal `*` characters inside a
/// single-quoted string. The composer applies the wrapping after escaping but
/// before quoting so the asterisks are not themselves escaped.
enum WildcardWrap: String, Codable, Sendable {
    /// No asterisks. Used by exact-match operators.
    case none
    /// Prepend an asterisk (`*value`). Used by `endsWith`.
    case leading
    /// Append an asterisk (`value*`). Used by `startsWith`.
    case trailing
    /// Wrap on both sides (`*value*`). Used by `contains` / `notContains`.
    case both
}

/// A typed RSQL operator that the Advanced Search composer can emit.
///
/// `rsqlSymbol` is the on-the-wire literal Jamf accepts. `displayName` is what
/// the picker shows. `requiresValue` is `false` for the bool operators which
/// imply their literal (`true` / `false`) — the composer reads the symbol,
/// not a user-supplied value, in that case.
enum RSQLOperator: String, Codable, CaseIterable, Sendable {
    case equals
    case notEquals
    case contains
    case notContains
    case startsWith
    case endsWith
    case lessThan
    case lessThanOrEqual
    case greaterThan
    case greaterThanOrEqual
    case isTrue
    case isFalse
    case before
    case after
    case on
    case between
    case includedIn
    case excludedFrom

    /// The on-the-wire symbol Jamf accepts. Empty for compound operators
    /// (`between`, `includedIn`, `excludedFrom`) that the composer expands
    /// into multiple primitive comparisons joined by `;` or `,`.
    var rsqlSymbol: String {
        switch self {
        case .equals, .contains, .startsWith, .endsWith, .on:
            return "=="
        case .notEquals, .notContains:
            return "!="
        case .lessThan, .before:
            return "=lt="
        case .lessThanOrEqual:
            return "=le="
        case .greaterThan, .after:
            return "=gt="
        case .greaterThanOrEqual:
            return "=ge="
        case .isTrue, .isFalse:
            return "=="
        case .between, .includedIn, .excludedFrom:
            return ""
        }
    }

    /// User-facing label rendered in the operator picker.
    var displayName: String {
        switch self {
        case .equals: return "equals"
        case .notEquals: return "does not equal"
        case .contains: return "contains"
        case .notContains: return "does not contain"
        case .startsWith: return "starts with"
        case .endsWith: return "ends with"
        case .lessThan: return "less than"
        case .lessThanOrEqual: return "less than or equal to"
        case .greaterThan: return "greater than"
        case .greaterThanOrEqual: return "greater than or equal to"
        case .isTrue: return "is true"
        case .isFalse: return "is false"
        case .before: return "before"
        case .after: return "after"
        case .on: return "on"
        case .between: return "between"
        case .includedIn: return "is one of"
        case .excludedFrom: return "is none of"
        }
    }

    /// Whether the operator pulls a value from the user. The two bool operators
    /// are self-describing — the composer hard-codes `true` / `false` and
    /// the picker hides the value control for them.
    var requiresValue: Bool {
        switch self {
        case .isTrue, .isFalse:
            return false
        default:
            return true
        }
    }

    /// How the composer wraps the literal in `*` for substring matching.
    var wildcardWrap: WildcardWrap {
        switch self {
        case .contains, .notContains:
            return .both
        case .startsWith:
            return .trailing
        case .endsWith:
            return .leading
        default:
            return .none
        }
    }
}

//endofline
