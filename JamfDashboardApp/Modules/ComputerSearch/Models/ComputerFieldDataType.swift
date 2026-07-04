import Foundation

// "End of Line"

/// The runtime value type carried by a `ComputerField`.
///
/// Drives both the Advanced Search UI (which input control to render) and the
/// RSQL composer (which operators are valid for the field). New cases must be
/// paired with a `supportedOperators` mapping below; otherwise the picker will
/// offer no operators for the field and it will be silently un-queryable.
enum ComputerFieldDataType: String, Codable, Sendable, CaseIterable {
    /// Free-form string. Default for unknown or human-typed fields.
    case string
    /// Whole-number values. Renders as a numeric `TextField` with integer parsing.
    case integer
    /// Floating-point values, reserved for decimal fields like purchase price.
    case double
    /// Boolean toggle. Renders as a `Toggle` with `isTrue` / `isFalse` operators.
    case bool
    /// Calendar date. Renders a `DatePicker` and emits ISO-8601 UTC literals.
    case date
    /// Closed set of allowed string values. Renders a multi-select picker driven by
    /// the field's `allowedValues` list.
    case enumeration

    /// The operator allowlist exposed by the Advanced Search picker for this type.
    ///
    /// Strings get full substring/prefix/suffix coverage. Numbers add relational
    /// comparisons. Bools collapse to two operators because RSQL only needs an
    /// affirmative or negative literal. Dates use range-friendly verbs that the
    /// composer translates to `=lt=` / `=gt=` / `between` pairs.
    var supportedOperators: [RSQLOperator] {
        switch self {
        case .string:
            return [.equals, .notEquals, .contains, .notContains, .startsWith, .endsWith]
        case .integer, .double:
            return [.equals, .notEquals, .lessThan, .lessThanOrEqual, .greaterThan, .greaterThanOrEqual]
        case .bool:
            return [.isTrue, .isFalse]
        case .date:
            return [.before, .after, .on, .between]
        case .enumeration:
            return [.includedIn, .excludedFrom, .equals, .notEquals]
        }
    }
}

//endofline
