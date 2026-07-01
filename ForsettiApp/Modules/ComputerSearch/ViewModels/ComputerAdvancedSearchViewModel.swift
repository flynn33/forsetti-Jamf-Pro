import Foundation
import Combine

/// Drives the computer Advanced Search sheet.
///
/// Owns the in-progress `AdvancedQuery`, exposes a live RSQL preview, and
/// validates as criteria change. Also handles snapshotting the query as a
/// named `SmartFilter` once the user decides to keep it.
///
/// Search execution itself stays on `ComputerSearchViewModel` so the existing
/// pagination / version fallback / prestage resolution code is reused
/// unchanged. This view model just hands the composed query and chosen field
/// columns to the parent on Search. It is the computer-side analogue of
/// `AdvancedSearchViewModel` (mobile) and shares the same `AdvancedQuery`,
/// `SmartFilter`, and `RSQLOperator` value types.
@MainActor
final class ComputerAdvancedSearchViewModel: ObservableObject {

    // MARK: - Published state

    /// The query the user is composing. Always has at least one (possibly
    /// empty) group so the UI has somewhere to drop new criteria.
    @Published var query: AdvancedQuery

    /// Live RSQL preview string. Updated whenever `query` changes via the
    /// Combine pipeline below. Empty string when the query is empty so the
    /// UI can render a placeholder.
    @Published private(set) var previewRSQL: String = ""

    /// Validation message surfaced under the preview, or nil when the query
    /// is composeable as-is. The composer drops invalid criteria silently
    /// from the RSQL output, so this message exists to nudge the user when
    /// their input is actually empty.
    @Published private(set) var validationMessage: String?

    /// Set true while the parent is running a search kicked off by this
    /// sheet, so the Search button can show a spinner.
    @Published var isSearching: Bool = false

    /// Field-column keys to apply when this query produces results. Mirrors
    /// the search view model's selection so users can tune what columns the
    /// results show without leaving the sheet.
    @Published var selectedFieldKeys: Set<String>

    /// Set during smart-filter save so the alert binds to a single source.
    @Published var isSaveSmartFilterPromptPresented: Bool = false
    @Published var pendingSmartFilterName: String = ""

    // MARK: - Dependencies

    /// All catalog entries available for filtering. Injected from the parent
    /// view model so the merged set (built-in catalog + tenant Extension
    /// Attributes) flows into the pickers.
    let availableFields: [ComputerField]

    /// Quick lookup for composer / criterion editor. Must be the dictionary
    /// form of `availableFields` so EA criteria resolve.
    let fieldLookup: [String: ComputerField]

    private var cancellables: Set<AnyCancellable> = []

    // MARK: - Init

    /// Default values are intentionally omitted on `availableFields` and
    /// `fieldLookup`. Under the project's `-default-isolation MainActor`
    /// setting, `ComputerField.catalog` and `keyLookup` are MainActor-isolated;
    /// using them as default-argument expressions triggers "main actor-isolated
    /// static property can not be referenced from a nonisolated context"
    /// because the compiler evaluates the default at the declaration site, not
    /// the call site. Every caller already passes the merged catalog from the
    /// parent view model anyway.
    init(
        initialQuery: AdvancedQuery,
        initialFieldKeys: Set<String>,
        availableFields: [ComputerField],
        fieldLookup: [String: ComputerField]
    ) {
        // Ensure at least one (empty) group exists so the editor renders.
        var hydrated = initialQuery
        if hydrated.groups.isEmpty {
            hydrated.groups = [AdvancedQueryGroup()]
        }
        self.query = hydrated
        self.selectedFieldKeys = initialFieldKeys
        self.availableFields = availableFields
        self.fieldLookup = fieldLookup

        // Live preview pipeline — recomputes RSQL on every query mutation.
        $query
            .receive(on: RunLoop.main)
            .sink { [weak self] newQuery in
                self?.regeneratePreview(for: newQuery)
            }
            .store(in: &cancellables)

        regeneratePreview(for: hydrated)
    }

    // MARK: - Mutation API

    /// Adds an empty new group below the existing ones.
    func addGroup() {
        query.groups.append(AdvancedQueryGroup())
    }

    /// Removes the group with the given id. The query keeps at least one
    /// group at all times so the editor never goes blank.
    func removeGroup(id: UUID) {
        query.groups.removeAll { $0.id == id }
        if query.groups.isEmpty {
            query.groups = [AdvancedQueryGroup()]
        }
    }

    /// Adds a fresh criterion to the named group, defaulting to the first
    /// filterable field's first allowed operator + an empty string value.
    func addCriterion(toGroup groupID: UUID) {
        guard let groupIndex = query.groups.firstIndex(where: { $0.id == groupID }) else {
            return
        }
        guard let firstField = availableFields.first(where: { $0.isFilterable }) else {
            return
        }
        let firstOp = firstField.dataType.supportedOperators.first ?? .equals
        let initialValue = defaultValue(for: firstField.dataType, op: firstOp)
        query.groups[groupIndex].criteria.append(
            AdvancedQueryCriterion(fieldKey: firstField.key, op: firstOp, value: initialValue)
        )
    }

    /// Removes a criterion from any group it lives in.
    func removeCriterion(id: UUID) {
        for index in query.groups.indices {
            query.groups[index].criteria.removeAll { $0.id == id }
        }
    }

    /// Updates a criterion in place. Used by the editor row's bindings.
    func updateCriterion(_ criterion: AdvancedQueryCriterion) {
        for groupIndex in query.groups.indices {
            if let critIndex = query.groups[groupIndex].criteria.firstIndex(where: { $0.id == criterion.id }) {
                query.groups[groupIndex].criteria[critIndex] = criterion
                return
            }
        }
    }

    /// Returns a sensible default `AdvancedQueryValue` for a field's data
    /// type and a chosen operator. Keeps the editor row from sitting in
    /// unparseable state right after the user picks a new field.
    func defaultValue(for dataType: ComputerFieldDataType, op: RSQLOperator) -> AdvancedQueryValue {
        switch op {
        case .between:
            let now = Date()
            return .dateRange(now.addingTimeInterval(-86_400), now)
        case .includedIn, .excludedFrom:
            return .list([])
        case .isTrue, .isFalse:
            return .bool(op == .isTrue)
        case .before, .after, .on:
            return .date(Date())
        default:
            switch dataType {
            case .string, .enumeration: return .string("")
            case .integer: return .int(0)
            case .double: return .double(0)
            case .bool: return .bool(true)
            case .date: return .date(Date())
            }
        }
    }

    // MARK: - Composition

    /// Compose-on-demand. Used by the parent search view model when the user
    /// hits Search; also drives the live preview via `regeneratePreview`.
    func compose() -> JamfRSQLComposer.ComputerComposeResult {
        JamfRSQLComposer.composeForComputers(query, fieldLookup: fieldLookup)
    }

    private func regeneratePreview(for query: AdvancedQuery) {
        let result = JamfRSQLComposer.composeForComputers(query, fieldLookup: fieldLookup)
        if let serverFilter = result.serverFilter {
            previewRSQL = serverFilter
        } else {
            previewRSQL = ""
        }

        if query.isEmpty {
            validationMessage = "Add at least one criterion to enable Search."
        } else if result.serverFilter == nil && result.clientCriteria.isEmpty {
            validationMessage = "Every criterion is empty or invalid."
        } else {
            validationMessage = nil
        }
    }

    // MARK: - Save smart filter

    /// Validates the pending name and returns a `SmartFilter` snapshot ready
    /// to be persisted by the parent. The view model itself doesn't write
    /// to disk — it stays UI-state-only and lets the parent coordinate
    /// persistence with the rest of the search module.
    func snapshotForSaving() -> SmartFilter? {
        let trimmed = pendingSmartFilterName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            validationMessage = "Provide a name to save the smart filter."
            return nil
        }
        return SmartFilter(
            name: trimmed,
            query: query,
            fieldKeys: Array(selectedFieldKeys)
        )
    }
}

//endofline
