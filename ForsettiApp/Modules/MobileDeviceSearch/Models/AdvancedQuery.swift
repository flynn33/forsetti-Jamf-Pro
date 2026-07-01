import Foundation

// "End of Line"

/// Boolean combinator joining criteria within a group, or groups within a query.
enum LogicalCombinator: String, Codable, Sendable, CaseIterable {
    case and
    case or

    /// On-the-wire RSQL joiner (`;` for AND, `,` for OR).
    var rsqlSymbol: String {
        switch self {
        case .and: return ";"
        case .or: return ","
        }
    }

    var displayName: String {
        switch self {
        case .and: return "All"
        case .or: return "Any"
        }
    }
}

/// A typed value attached to an `AdvancedQueryCriterion`.
///
/// The composer reads the case (not just the rawValue) to format the literal
/// correctly: dates emit ISO-8601 UTC, lists expand to RSQL OR / AND chains,
/// numerics skip the surrounding single quotes per Jamf's relaxed parser.
enum AdvancedQueryValue: Codable, Hashable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case date(Date)
    case dateRange(Date, Date)
    case list([String])

    /// `true` when the value carries no useful payload (empty string, empty
    /// list). The composer uses this to short-circuit empty criteria.
    var isEmpty: Bool {
        switch self {
        case .string(let value):
            return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .list(let values):
            return values.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        default:
            return false
        }
    }
}

/// A single advanced-search criterion: pick a field, choose an operator,
/// supply a typed value.
struct AdvancedQueryCriterion: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var fieldKey: String
    var op: RSQLOperator
    var value: AdvancedQueryValue

    /// `nonisolated` so the project's `-default-isolation MainActor` setting
    /// doesn't trap this initializer behind the main actor — composer tests
    /// and the persistence layer build these from off-actor contexts.
    nonisolated init(id: UUID = UUID(), fieldKey: String, op: RSQLOperator, value: AdvancedQueryValue) {
        self.id = id
        self.fieldKey = fieldKey
        self.op = op
        self.value = value
    }
}

/// A group of criteria joined by a single combinator. Groups are themselves
/// joined by the query's outer combinator.
///
/// Example precedence:
///   query.outerCombinator = .and
///   group A (or): X, Y     → "(X,Y)"
///   group B (and): Z, W    → "(Z;W)"
///   ⇒ final RSQL "(X,Y);(Z;W)"
struct AdvancedQueryGroup: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var combinator: LogicalCombinator
    var criteria: [AdvancedQueryCriterion]

    /// `nonisolated` so the project's `-default-isolation MainActor` setting
    /// doesn't trap this initializer behind the main actor.
    nonisolated init(id: UUID = UUID(), combinator: LogicalCombinator = .and, criteria: [AdvancedQueryCriterion] = []) {
        self.id = id
        self.combinator = combinator
        self.criteria = criteria
    }
}

/// The complete advanced query: an outer combinator plus an ordered list of
/// groups. Persisted via `SmartFilter` and consumed by `JamfRSQLComposer`.
struct AdvancedQuery: Codable, Hashable, Sendable {
    var groups: [AdvancedQueryGroup]
    var outerCombinator: LogicalCombinator

    /// `nonisolated` so the project's `-default-isolation MainActor` setting
    /// doesn't trap this initializer behind the main actor.
    nonisolated init(groups: [AdvancedQueryGroup] = [], outerCombinator: LogicalCombinator = .and) {
        self.groups = groups
        self.outerCombinator = outerCombinator
    }

    /// True when every group is empty (or the query has no groups). The view
    /// model uses this to disable the Search button.
    var isEmpty: Bool {
        groups.allSatisfy { $0.criteria.isEmpty }
    }
}

//endofline
