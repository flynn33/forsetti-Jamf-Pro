import Foundation

enum ReportsQueryPlanner {
    nonisolated static func makePlan(for request: ReportRequest) -> ReportQueryPlan {
        let domains = request.domain.inventoryDomains
        let requestedFields = requestedFields(for: request)

        var computerSections: Set<ComputerInventorySection> = [.general, .hardware]
        var mobileSections: Set<MobileDeviceInventorySection> = [.general, .hardware]

        for field in requestedFields {
            if domains.contains(.computer), let section = field.computerSection {
                computerSections.insert(section)
            }
            if domains.contains(.mobile), let section = field.mobileSection {
                mobileSections.insert(section)
            }
        }

        let computerFilter = domains.contains(.computer)
            ? serverFilter(for: request.criteria, domain: .computer)
            : nil
        let mobileFilter = domains.contains(.mobile)
            ? serverFilter(for: request.criteria, domain: .mobile)
            : nil

        return ReportQueryPlan(
            domains: domains,
            computerSections: computerSections,
            mobileSections: mobileSections,
            computerServerFilter: computerFilter,
            mobileServerFilter: mobileFilter,
            clientCriteria: request.criteria,
            requestedFields: requestedFields
        )
    }

    nonisolated static func validate(_ request: ReportRequest) -> [String] {
        request.criteria.compactMap { criterion in
            guard let field = ReportsFieldCatalog.field(for: criterion.fieldKey) else {
                return "Unknown field in criteria."
            }
            guard criterion.comparison.supports(field.dataType) else {
                return "\(criterion.comparison.displayName) is not valid for \(field.displayName)."
            }
            if criterion.comparison.requiresValue, criterion.trimmedValue.isEmpty {
                return "Provide a value for \(field.displayName)."
            }
            return nil
        }
    }

    nonisolated static func matches(record: ReportDeviceRecord, criteria: [ReportCriterion]) -> Bool {
        criteria.allSatisfy { criterion in
            guard let field = ReportsFieldCatalog.field(for: criterion.fieldKey) else {
                return true
            }
            return matches(record: record, criterion: criterion, field: field)
        }
    }

    nonisolated private static func requestedFields(for request: ReportRequest) -> [ReportField] {
        var keys: Set<String> = [
            "deviceType",
            "model",
            "modelIdentifier",
            "osVersion",
            "osBuild",
            "building",
            "department",
            "room",
            "assignedName",
            "email",
            "managed",
            "supervised",
            // Extension Attributes are always requested so the aggregator can
            // populate the Locations panel from the "Billing GL & Store NO"
            // EA (see ReportsInventoryService.locationExtensionAttributeName)
            // regardless of which criteria the user picks.
            "extensionAttributes",
            request.grouping.fieldKey
        ]

        for criterion in request.criteria {
            keys.insert(criterion.fieldKey)
        }

        return keys.compactMap(ReportsFieldCatalog.field(for:)).sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    nonisolated private static func serverFilter(for criteria: [ReportCriterion], domain: ReportInventoryDomain) -> String? {
        let parts = criteria.compactMap { criterion -> String? in
            guard let field = ReportsFieldCatalog.field(for: criterion.fieldKey) else {
                return nil
            }

            switch domain {
            case .computer:
                guard field.isServerFilterableForComputers, let fieldKey = field.computerFieldKey else {
                    return nil
                }
                return renderServerCriterion(criterion, field: field, fieldKey: fieldKey)
            case .mobile:
                guard field.isServerFilterableForMobile, let fieldKey = field.mobileFieldKey else {
                    return nil
                }
                return renderServerCriterion(criterion, field: field, fieldKey: fieldKey)
            }
        }

        return parts.isEmpty ? nil : parts.joined(separator: ";")
    }

    nonisolated private static func renderServerCriterion(_ criterion: ReportCriterion, field: ReportField, fieldKey: String) -> String? {
        let value = criterion.trimmedValue
        if criterion.comparison.requiresValue, value.isEmpty {
            return nil
        }

        switch criterion.comparison {
        case .equals:
            if field.dataType == .bool, let bool = boolValue(value) {
                return "\(fieldKey)==\(bool)"
            }
            return JamfRSQLFilter.equality(field: fieldKey, value: value)
        case .notEquals:
            if field.dataType == .bool, let bool = boolValue(value) {
                return "\(fieldKey)!=\(bool)"
            }
            return JamfRSQLFilter.equality(field: fieldKey, value: value, negated: true)
        case .contains:
            return JamfRSQLFilter.equality(field: fieldKey, value: value, wildcard: .both)
        case .notContains:
            return JamfRSQLFilter.equality(field: fieldKey, value: value, wildcard: .both, negated: true)
        case .startsWith:
            return JamfRSQLFilter.equality(field: fieldKey, value: value, wildcard: .trailing)
        case .endsWith:
            return JamfRSQLFilter.equality(field: fieldKey, value: value, wildcard: .leading)
        case .greaterThan:
            return "\(fieldKey)=gt='\(JamfRSQLFilter.escapeSingleQuoted(value))'"
        case .lessThan:
            return "\(fieldKey)=lt='\(JamfRSQLFilter.escapeSingleQuoted(value))'"
        case .isSet:
            return "\(fieldKey)!=''"
        case .isEmpty:
            return "\(fieldKey)==''"
        }
    }

    nonisolated private static func matches(record: ReportDeviceRecord, criterion: ReportCriterion, field: ReportField) -> Bool {
        let raw = record.value(for: field.key)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = criterion.trimmedValue

        switch criterion.comparison {
        case .isSet:
            return raw?.isEmpty == false
        case .isEmpty:
            return raw == nil || raw?.isEmpty == true
        case .equals:
            if field.dataType == .bool {
                return boolValue(raw ?? "") == boolValue(value)
            }
            return raw?.localizedCaseInsensitiveCompare(value) == .orderedSame
        case .notEquals:
            if field.dataType == .bool {
                return boolValue(raw ?? "") != boolValue(value)
            }
            return raw?.localizedCaseInsensitiveCompare(value) != .orderedSame
        case .contains:
            return raw?.range(of: value, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        case .notContains:
            return raw?.range(of: value, options: [.caseInsensitive, .diacriticInsensitive]) == nil
        case .startsWith:
            return raw?.range(of: value, options: [.caseInsensitive, .anchored, .diacriticInsensitive]) != nil
        case .endsWith:
            guard let raw else { return false }
            return raw.range(of: value, options: [.caseInsensitive, .backwards, .anchored, .diacriticInsensitive]) != nil
        case .greaterThan:
            guard let left = Double(raw ?? ""), let right = Double(value) else { return false }
            return left > right
        case .lessThan:
            guard let left = Double(raw ?? ""), let right = Double(value) else { return false }
            return left < right
        }
    }

    nonisolated private static func boolValue(_ value: String) -> Bool? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "true", "yes", "1", "managed", "supervised": return true
        case "false", "no", "0", "unmanaged", "unsupervised": return false
        default: return nil
        }
    }
}
