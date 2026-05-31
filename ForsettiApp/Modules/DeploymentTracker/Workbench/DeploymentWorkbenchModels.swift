import Foundation

// MARK: - Workbench projection models
//
// These lightweight models are display projections, not persistence records.
// They let the Workbench render stable columns, rows, cells, filters, sorting,
// Dashboard KPIs, and validation messages without exposing raw Core Data or
// service internals to SwiftUI.
nonisolated enum DeploymentWorkbenchSortDirection: String, Codable, CaseIterable, Sendable {
    case ascending
    case descending
}

nonisolated struct DeploymentWorkbenchSort: Equatable, Sendable {
    var fieldKey: String
    var direction: DeploymentWorkbenchSortDirection
}

nonisolated struct DeploymentWorkbenchFilter: Equatable, Sendable {
    var fieldKey: String
    var query: String
}

nonisolated struct DeploymentWorkbenchColumnProjection: Identifiable, Equatable, Sendable {
    var id: String { field.fieldKey }
    let field: DeploymentFieldDefinition
    let layoutColumn: WorkbenchLayoutColumn
}

nonisolated struct DeploymentWorkbenchCellProjection: Identifiable, Equatable, Sendable {
    var id: String { fieldKey }
    let fieldKey: String
    let displayValue: String
    let rawValue: String
    let isEditable: Bool
}

nonisolated struct DeploymentWorkbenchRowProjection: Identifiable, Equatable, Sendable {
    let id: String
    let device: DeploymentDevice
    let cells: [DeploymentWorkbenchCellProjection]

    func cell(for fieldKey: String) -> DeploymentWorkbenchCellProjection? {
        cells.first { $0.fieldKey == fieldKey }
    }
}

nonisolated struct DeploymentWorkbenchProjection: Equatable, Sendable {
    let layout: WorkbenchLayout
    let columns: [DeploymentWorkbenchColumnProjection]
    let rows: [DeploymentWorkbenchRowProjection]
    let hiddenFieldCount: Int
    let validationMessages: [String]
}
