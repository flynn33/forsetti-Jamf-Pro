import Foundation

// MARK: - Field Catalog service
//
// This service owns layout operations for Workbench columns. Views ask it to
// change visibility, order, pinning, or width; the service applies the tracker's
// layout rules without touching device data or external snapshots.
nonisolated struct DeploymentFieldCatalogService: Sendable {
    let definitions: [DeploymentFieldDefinition]

    init(definitions: [DeploymentFieldDefinition]) {
        self.definitions = definitions
    }

    var activeDefinitions: [DeploymentFieldDefinition] {
        // Active fields are sorted by category and display name so the catalog
        // behaves predictably even when seed data or imported definitions change.
        definitions
            .filter { $0.lifecycleState == .active }
            .sorted {
                if $0.category == $1.category {
                    return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                }
                return $0.category.localizedCaseInsensitiveCompare($1.category) == .orderedAscending
            }
    }

    var categories: [String] {
        // Category lists come from active definitions only. Archived or pending
        // deletion fields should not drive visible catalog filters.
        Array(Set(activeDefinitions.map(\.category))).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    func definition(for fieldKey: String) -> DeploymentFieldDefinition? {
        definitions.first { $0.fieldKey == fieldKey }
    }

    func visibleColumns(for layout: WorkbenchLayout) -> [DeploymentWorkbenchColumnProjection] {
        let definitionsByKey = Dictionary(uniqueKeysWithValues: definitions.map { ($0.fieldKey, $0) })
        return layout.columns
            .filter(\.visible)
            .sorted { lhs, rhs in
                if lhs.pinned != rhs.pinned {
                    return lhs.pinned
                }
                return lhs.order < rhs.order
            }
            .compactMap { column in
                guard let definition = definitionsByKey[column.fieldKey] else {
                    return nil
                }
                return DeploymentWorkbenchColumnProjection(field: definition, layoutColumn: column)
            }
    }

    func layoutWithColumnVisibility(
        _ fieldKey: String,
        isVisible: Bool,
        in layout: WorkbenchLayout
    ) -> WorkbenchLayout {
        var copy = layout
        if let index = copy.columns.firstIndex(where: { $0.fieldKey == fieldKey }) {
            copy.columns[index].visible = isVisible
        } else if let definition = definition(for: fieldKey) {
            copy.columns.append(
                WorkbenchLayoutColumn(
                    fieldKey: fieldKey,
                    visible: isVisible,
                    order: nextOrder(in: copy),
                    width: definition.defaultWidth,
                    pinned: false
                )
            )
        }
        copy.columns = normalizedColumns(copy.columns)
        return copy
    }

    func layoutByMovingColumn(
        fieldKey: String,
        toVisibleIndex targetIndex: Int,
        in layout: WorkbenchLayout
    ) -> WorkbenchLayout {
        var copy = layout
        var visibleColumns = copy.columns
            .filter(\.visible)
            .sorted { $0.order < $1.order }

        guard let currentIndex = visibleColumns.firstIndex(where: { $0.fieldKey == fieldKey }) else {
            return copy
        }

        let column = visibleColumns.remove(at: currentIndex)
        let clampedIndex = max(0, min(targetIndex, visibleColumns.count))
        visibleColumns.insert(column, at: clampedIndex)

        for (index, column) in visibleColumns.enumerated() {
            if let layoutIndex = copy.columns.firstIndex(where: { $0.fieldKey == column.fieldKey }) {
                copy.columns[layoutIndex].order = index + 1
            }
        }

        copy.columns = normalizedColumns(copy.columns)
        return copy
    }

    func layoutByResizingColumn(
        fieldKey: String,
        width: Double,
        in layout: WorkbenchLayout
    ) -> WorkbenchLayout {
        var copy = layout
        guard let index = copy.columns.firstIndex(where: { $0.fieldKey == fieldKey }) else {
            return copy
        }
        copy.columns[index].width = max(80, min(width, 480))
        return copy
    }

    func layoutByPinningColumn(
        fieldKey: String,
        isPinned: Bool,
        in layout: WorkbenchLayout
    ) -> WorkbenchLayout {
        var copy = layout
        guard let index = copy.columns.firstIndex(where: { $0.fieldKey == fieldKey }) else {
            return copy
        }
        copy.columns[index].pinned = isPinned
        return copy
    }

    func workbookDefaultLayout() -> WorkbenchLayout {
        DeploymentTrackerSeedData.workbookDefaultLayout
    }

    nonisolated private func nextOrder(in layout: WorkbenchLayout) -> Int {
        (layout.columns.map(\.order).max() ?? 0) + 1
    }

    nonisolated private func normalizedColumns(_ columns: [WorkbenchLayoutColumn]) -> [WorkbenchLayoutColumn] {
        var orderedColumns = columns.sorted { lhs, rhs in
            if lhs.visible != rhs.visible {
                return lhs.visible
            }
            return lhs.order < rhs.order
        }

        var nextVisibleOrder = 1
        var nextHiddenOrder = orderedColumns.filter(\.visible).count + 1
        for index in orderedColumns.indices {
            if orderedColumns[index].visible {
                orderedColumns[index].order = nextVisibleOrder
                nextVisibleOrder += 1
            } else {
                orderedColumns[index].order = nextHiddenOrder
                nextHiddenOrder += 1
            }
        }
        return orderedColumns
    }
}
