import Foundation

// "Would you like to play a game?"

/// Composes server-side RSQL filters from `AdvancedQuery` instances built by
/// the Advanced Search UI.
///
/// The composer separates each criterion into one of three buckets:
///
/// 1. **Server filterable** — emitted into the returned `serverFilter` RSQL
///    string. These narrow results on Jamf's side.
/// 2. **Client-only** — fields whose `MobileDeviceField.isFilterable == false`
///    (e.g. `prestageEnrollmentProfile`). Returned in `clientCriteria` so the
///    view model can apply them in-memory after the API response is enriched.
/// 3. **Skipped** — empty values, unknown field keys, or operators that
///    require a value but don't have one. The composer drops them silently;
///    callers can detect drops by comparing input criteria count to the sum
///    of `serverGroups` parts and `clientCriteria`.
///
/// Output preserves group precedence by parenthesizing every group's body
/// regardless of how many criteria it contains, so the final filter is
/// unambiguous to any RSQL parser regardless of its precedence rules.
enum JamfRSQLComposer {

    /// Result of composing an `AdvancedQuery`.
    struct ComposeResult: Equatable {
        /// The server-side RSQL filter, or nil when every criterion is
        /// client-only or skipped.
        let serverFilter: String?

        /// Criteria the server can't filter — apply these in-memory.
        let clientCriteria: [AdvancedQueryCriterion]

        /// Inventory sections referenced by any criterion. The view model
        /// unions this with the active profile's sections to ensure the
        /// API response includes the values the client filter needs.
        let referencedSections: Set<MobileDeviceInventorySection>
    }

    /// Renders an `AdvancedQuery` into the three-bucket result.
    ///
    /// - Parameters:
    ///   - query: The user-built query.
    ///   - fieldLookup: Map from field key to catalog entry. Pass
    ///     `MobileDeviceField.keyLookup`. Unknown keys are skipped.
    /// - Returns: The compose result; never throws.
    static func compose(
        _ query: AdvancedQuery,
        fieldLookup: [String: MobileDeviceField]
    ) -> ComposeResult {
        var serverGroups: [String] = []
        var clientCriteria: [AdvancedQueryCriterion] = []
        var sections: Set<MobileDeviceInventorySection> = [.general]

        for group in query.groups {
            var parts: [String] = []
            for criterion in group.criteria {
                guard let field = fieldLookup[criterion.fieldKey] else {
                    continue
                }
                sections.insert(field.section)

                // Two routing flags:
                // - !isFilterable means the field shouldn't be in the picker
                //   at all; if it shows up in a saved smart filter we silently
                //   drop it rather than emit nonsense RSQL.
                // - !isServerFilterable means the user CAN pick it but its
                //   value is matched in-memory after the response (prestage
                //   profile name, tenant extension attributes, …).
                guard field.isFilterable else { continue }

                if field.isServerFilterable == false {
                    clientCriteria.append(criterion)
                    continue
                }

                if let part = render(criterion: criterion, fieldKey: field.key) {
                    parts.append(part)
                }
            }

            if parts.isEmpty {
                continue
            }

            serverGroups.append("(" + parts.joined(separator: group.combinator.rsqlSymbol) + ")")
        }

        let serverFilter: String? = serverGroups.isEmpty
            ? nil
            : serverGroups.joined(separator: query.outerCombinator.rsqlSymbol)

        return ComposeResult(
            serverFilter: serverFilter,
            clientCriteria: clientCriteria,
            referencedSections: sections
        )
    }

    /// Result of composing an `AdvancedQuery` against the computer-inventory
    /// field catalog. Mirrors `ComposeResult` but carries the computer section
    /// enum so the computer view model can union the right inventory sections.
    struct ComputerComposeResult: Equatable {
        /// The server-side RSQL filter, or nil when every criterion is
        /// client-only or skipped.
        let serverFilter: String?

        /// Criteria the server can't filter — apply these in-memory.
        let clientCriteria: [AdvancedQueryCriterion]

        /// Computer inventory sections referenced by any criterion. The view
        /// model unions this with the active profile's sections to ensure the
        /// API response includes the values the client filter needs.
        let referencedSections: Set<ComputerInventorySection>
    }

    /// Renders an `AdvancedQuery` into the three-bucket result against the
    /// computer-inventory field catalog. Shares the criterion → RSQL `render`
    /// helper with the mobile-device path; only the section/filterability
    /// routing differs (computer field metadata vs. mobile field metadata).
    ///
    /// - Parameters:
    ///   - query: The user-built query.
    ///   - fieldLookup: Map from field key to catalog entry. Pass
    ///     `ComputerField.keyLookup`. Unknown keys are skipped.
    /// - Returns: The compose result; never throws.
    static func composeForComputers(
        _ query: AdvancedQuery,
        fieldLookup: [String: ComputerField]
    ) -> ComputerComposeResult {
        var serverGroups: [String] = []
        var clientCriteria: [AdvancedQueryCriterion] = []
        var sections: Set<ComputerInventorySection> = [.general]

        for group in query.groups {
            var parts: [String] = []
            for criterion in group.criteria {
                guard let field = fieldLookup[criterion.fieldKey] else {
                    continue
                }
                sections.insert(field.section)

                guard field.isFilterable else { continue }

                if field.isServerFilterable == false {
                    clientCriteria.append(criterion)
                    continue
                }

                if let part = render(criterion: criterion, fieldKey: field.key) {
                    parts.append(part)
                }
            }

            if parts.isEmpty {
                continue
            }

            serverGroups.append("(" + parts.joined(separator: group.combinator.rsqlSymbol) + ")")
        }

        let serverFilter: String? = serverGroups.isEmpty
            ? nil
            : serverGroups.joined(separator: query.outerCombinator.rsqlSymbol)

        return ComputerComposeResult(
            serverFilter: serverFilter,
            clientCriteria: clientCriteria,
            referencedSections: sections
        )
    }

    static func composeComputer(
        _ query: AdvancedQuery,
        fieldLookup: [String: ComputerField]
    ) -> ComputerComposeResult {
        composeForComputers(query, fieldLookup: fieldLookup)
    }

    /// Builds the RSQL fragment for a single criterion. Returns nil when the
    /// criterion has no usable value (empty string, empty list, unparseable
    /// date) so the parent group cleanly skips it.
    ///
    /// Takes the bare `fieldKey` rather than a typed catalog entry so both the
    /// mobile-device and computer compose paths share this single source of
    /// truth for criterion → RSQL rendering. The section/filterability routing
    /// that differs between modules stays in the respective `compose` methods.
    private static func render(
        criterion: AdvancedQueryCriterion,
        fieldKey: String
    ) -> String? {

        // Pull a string out of the value for operators that take strings.
        // For numeric / date operators we use the typed branches below.
        func stringValue() -> String? {
            switch criterion.value {
            case .string(let value):
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            default:
                return nil
            }
        }

        switch criterion.op {

        // String / equality operators — value goes through the helper that
        // escapes single quotes and handles wildcard wrapping.
        case .equals:
            guard let value = stringValue() else { return nil }
            return JamfRSQLFilter.equality(field: fieldKey, value: value, wildcard: .none, negated: false)
        case .notEquals:
            guard let value = stringValue() else { return nil }
            return JamfRSQLFilter.equality(field: fieldKey, value: value, wildcard: .none, negated: true)
        case .contains:
            guard let value = stringValue() else { return nil }
            return JamfRSQLFilter.equality(field: fieldKey, value: value, wildcard: .both, negated: false)
        case .notContains:
            guard let value = stringValue() else { return nil }
            return JamfRSQLFilter.equality(field: fieldKey, value: value, wildcard: .both, negated: true)
        case .startsWith:
            guard let value = stringValue() else { return nil }
            return JamfRSQLFilter.equality(field: fieldKey, value: value, wildcard: .trailing, negated: false)
        case .endsWith:
            guard let value = stringValue() else { return nil }
            return JamfRSQLFilter.equality(field: fieldKey, value: value, wildcard: .leading, negated: false)

        // Numeric relational operators. Jamf accepts numeric literals
        // unquoted, but quoting is also accepted and matches our escaping
        // convention for everything else.
        case .lessThan, .lessThanOrEqual, .greaterThan, .greaterThanOrEqual:
            guard let literal = numericLiteral(for: criterion.value) else { return nil }
            return "\(fieldKey)\(criterion.op.rsqlSymbol)'\(literal)'"

        // Boolean.
        case .isTrue:
            return "\(fieldKey)==true"
        case .isFalse:
            return "\(fieldKey)==false"

        // Date — single-bound operators map to relational comparisons against
        // an ISO-8601 UTC literal. `on` is treated as equality against the
        // start-of-day UTC; users wanting "any moment that day" should pick
        // `between` with the same start/end.
        case .before, .after, .on:
            guard case .date(let date) = criterion.value else { return nil }
            let literal = JamfRSQLFilter.escapeSingleQuoted(isoUtc(date))
            return "\(fieldKey)\(criterion.op.rsqlSymbol)'\(literal)'"
        case .between:
            guard case .dateRange(let start, let end) = criterion.value else { return nil }
            let lower = JamfRSQLFilter.escapeSingleQuoted(isoUtc(start))
            let upper = JamfRSQLFilter.escapeSingleQuoted(isoUtc(end))
            return "(\(fieldKey)=ge='\(lower)';\(fieldKey)=le='\(upper)')"

        // Enumeration operators expand to an OR / AND chain over the list.
        case .includedIn:
            guard case .list(let raws) = criterion.value else { return nil }
            let values = nonEmptyTrimmed(raws)
            guard values.isEmpty == false else { return nil }
            let parts = values.map {
                JamfRSQLFilter.equality(field: fieldKey, value: $0, wildcard: .none, negated: false)
            }
            return "(" + parts.joined(separator: ",") + ")"
        case .excludedFrom:
            guard case .list(let raws) = criterion.value else { return nil }
            let values = nonEmptyTrimmed(raws)
            guard values.isEmpty == false else { return nil }
            let parts = values.map {
                JamfRSQLFilter.equality(field: fieldKey, value: $0, wildcard: .none, negated: true)
            }
            return "(" + parts.joined(separator: ";") + ")"
        }
    }

    private static func numericLiteral(for value: AdvancedQueryValue) -> String? {
        switch value {
        case .int(let int): return String(int)
        case .double(let double): return String(double)
        case .string(let string):
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        default: return nil
        }
    }

    private static func nonEmptyTrimmed(_ values: [String]) -> [String] {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
    }

    /// Stable ISO-8601 UTC formatter without fractional seconds. Used for
    /// date literals so a tenant comparing across timezones gets predictable
    /// ordering.
    private static let isoUtcFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static func isoUtc(_ date: Date) -> String {
        isoUtcFormatter.string(from: date)
    }
}

//endofline
