import Foundation
import Combine

@MainActor
final class ComputerAdvancedSearchViewModel: ObservableObject {
    @Published var query: AdvancedQuery
    @Published private(set) var previewRSQL: String = ""
    @Published private(set) var validationMessage: String?
    @Published var isSearching: Bool = false
    @Published var selectedFieldKeys: Set<String>
    @Published var isSaveSmartFilterPromptPresented: Bool = false
    @Published var pendingSmartFilterName: String = ""

    let availableFields: [ComputerField]
    let fieldLookup: [String: ComputerField]

    private var cancellables: Set<AnyCancellable> = []

    init(
        initialQuery: AdvancedQuery,
        initialFieldKeys: Set<String>,
        availableFields: [ComputerField],
        fieldLookup: [String: ComputerField]
    ) {
        var hydrated = initialQuery
        if hydrated.groups.isEmpty {
            hydrated.groups = [AdvancedQueryGroup()]
        }
        query = hydrated
        selectedFieldKeys = initialFieldKeys
        self.availableFields = availableFields
        self.fieldLookup = fieldLookup

        $query
            .receive(on: RunLoop.main)
            .sink { [weak self] newQuery in
                self?.regeneratePreview(for: newQuery)
            }
            .store(in: &cancellables)

        regeneratePreview(for: hydrated)
    }

    func addGroup() {
        query.groups.append(AdvancedQueryGroup())
    }

    func removeGroup(id: UUID) {
        query.groups.removeAll { $0.id == id }
        if query.groups.isEmpty {
            query.groups = [AdvancedQueryGroup()]
        }
    }

    func addCriterion(toGroup groupID: UUID) {
        guard let groupIndex = query.groups.firstIndex(where: { $0.id == groupID }),
              let firstField = availableFields.first(where: { $0.isFilterable }) else {
            return
        }

        let firstOp = firstField.dataType.supportedOperators.first ?? .equals
        query.groups[groupIndex].criteria.append(
            AdvancedQueryCriterion(
                fieldKey: firstField.key,
                op: firstOp,
                value: defaultValue(for: firstField.dataType, op: firstOp)
            )
        )
    }

    func removeCriterion(id: UUID) {
        for index in query.groups.indices {
            query.groups[index].criteria.removeAll { $0.id == id }
        }
    }

    func updateCriterion(_ criterion: AdvancedQueryCriterion) {
        for groupIndex in query.groups.indices {
            if let criterionIndex = query.groups[groupIndex].criteria.firstIndex(where: { $0.id == criterion.id }) {
                query.groups[groupIndex].criteria[criterionIndex] = criterion
                return
            }
        }
    }

    func defaultValue(for dataType: MobileDeviceFieldDataType, op: RSQLOperator) -> AdvancedQueryValue {
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
            case .string, .enumeration:
                return .string("")
            case .integer:
                return .int(0)
            case .double:
                return .double(0)
            case .bool:
                return .bool(true)
            case .date:
                return .date(Date())
            }
        }
    }

    func compose() -> JamfRSQLComposer.ComputerComposeResult {
        JamfRSQLComposer.composeComputer(query, fieldLookup: fieldLookup)
    }

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

    private func regeneratePreview(for query: AdvancedQuery) {
        let result = JamfRSQLComposer.composeComputer(query, fieldLookup: fieldLookup)
        previewRSQL = result.serverFilter ?? ""

        if query.isEmpty {
            validationMessage = "Add at least one criterion to enable Search."
        } else if result.serverFilter == nil && result.clientCriteria.isEmpty {
            validationMessage = "Every criterion is empty or invalid."
        } else {
            validationMessage = nil
        }
    }
}
