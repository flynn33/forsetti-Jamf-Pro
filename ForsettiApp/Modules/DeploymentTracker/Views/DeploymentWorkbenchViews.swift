import SwiftUI
import UniformTypeIdentifiers

// MARK: - In-Progress Workbench
//
// The Workbench is the technician's primary operating surface. It combines a
// configurable grid, validation drawer, row inspector, export previews, and
// service-backed action buttons while keeping all mutations routed through the
// DeploymentTrackerViewModel.
struct DeploymentInProgressWorkbenchView: View {
    @ObservedObject var viewModel: DeploymentTrackerViewModel

    var body: some View {
        DeploymentWorkspaceChrome(
            title: "In-Progress Workbench Demo",
            subtitle: "Review, edit, validate, and run simulated actions on active Demo deployment devices. Dummy data only. No live Jamf actions.",
            workspace: .inProgress,
            activeScenario: viewModel.activeDemoScenario,
            isScenarioPaused: viewModel.isDemoScenarioPaused,
            guideTopicID: "workbench",
            openGuide: { viewModel.openGuide(topicID: $0, sourceWorkspace: .inProgress) },
            runDemo: { viewModel.startDemoScenario(for: .inProgress) }
        ) {
            VStack(alignment: .leading, spacing: ForsettiTheme.Spacing.section) {
                InProgressOnboardingStrip(viewModel: viewModel)
                InProgressToolbarView(viewModel: viewModel)

                if let loadErrorMessage = viewModel.loadErrorMessage {
                    DeploymentUserFacingErrorView(message: loadErrorMessage, viewModel: viewModel)
                }

                InProgressGridView(viewModel: viewModel)

                if !viewModel.projection.validationMessages.isEmpty {
                    InProgressValidationDrawer(messages: viewModel.projection.validationMessages, viewModel: viewModel)
                }

                if let selectedRow = viewModel.selectedRow {
                    InProgressInspectorView(row: selectedRow, fieldDefinitions: viewModel.fieldDefinitions)
                }

                if let exportPreview = viewModel.exportPreview {
                    InProgressExportPreviewView(csv: exportPreview)
                }
            }
        }
        .sheet(isPresented: $viewModel.isFieldCatalogPresented) {
            // The Field Catalog is a sheet instead of an inline panel so the
            // grid stays stable while column visibility, order, width, and
            // pinned state are being edited.
            InProgressFieldCatalogPanel(viewModel: viewModel)
                .frame(minWidth: 560, minHeight: 640)
        }
    }
}

// Short orientation strip for the Workbench. It keeps the most important next
// actions visible without burying them inside the larger toolbar.
private struct InProgressOnboardingStrip: View {
    @ObservedObject var viewModel: DeploymentTrackerViewModel

    var body: some View {
        HStack(alignment: .top, spacing: ForsettiTheme.Spacing.item) {
            Image(systemName: "wand.and.stars")
                .font(.title3)
                .foregroundStyle(ForsettiTheme.accent)
            Text("Use this workbench to review, edit, validate, and run simulated actions on active Demo deployment devices. Select rows to preview Jamf Preload, ABM Verification, SD+ Export, or shipping actions. Dummy data only. No live Jamf actions.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: ForsettiTheme.Spacing.item)
            Button {
                viewModel.openGuide(topicID: "workbench", sourceWorkspace: .inProgress)
            } label: {
                Label("Open Guide", systemImage: "questionmark.circle")
            }
            Button {
                viewModel.showFieldCatalog()
            } label: {
                Label("Customize Columns", systemImage: "rectangle.grid.2x2")
            }
            Button {
                viewModel.selectWorkspace(.intakeImports)
            } label: {
                Label("Import Devices", systemImage: "tray.and.arrow.down")
            }
        }
        .padding(12)
        .forsettiCardSurface()
    }
}

// Toolbar for layout management and batch actions. Every button delegates to the
// view model so validation, diagnostics, persistence, and projection refresh
// behavior stay centralized.
private struct InProgressToolbarView: View {
    @ObservedObject var viewModel: DeploymentTrackerViewModel

    var body: some View {
        HStack(spacing: ForsettiTheme.Spacing.item) {
            Picker("Workspace layout", selection: Binding(get: { viewModel.workbenchLayout.id }, set: { viewModel.selectLayout(id: $0) })) {
                ForEach(viewModel.workbenchLayouts) { layout in
                    Text(layout.displayName).tag(layout.id)
                }
            }
            .labelsHidden()
            .frame(width: 190)

            Button {
                viewModel.showFieldCatalog()
            } label: {
                Label("Customize Columns", systemImage: "rectangle.grid.2x2")
            }
            .help("Open searchable Field Catalog")

            Button {
                viewModel.saveCurrentLayout()
            } label: {
                Label("Save Current Layout", systemImage: "square.and.arrow.down")
            }
            .help("Save Current Layout")

            Button {
                viewModel.savePersonalLayoutCopy()
            } label: {
                Label("Save Personal Layout", systemImage: "person.crop.rectangle.stack")
            }
            .help("Create Project-Specific or Personal Layout")

            Button {
                viewModel.resetWorkbookDefaultLayout()
            } label: {
                Label("Reset to Workbook Default", systemImage: "arrow.counterclockwise")
            }
            .help("Reset to Workbook Default")

            Button {
                viewModel.validateSelectedForPreload()
            } label: {
                Label("Validate Demo Devices", systemImage: "checklist")
            }
            .help("Validate Demo Devices")

            Button {
                viewModel.verifySelectedWithABM()
            } label: {
                Label("Run Demo ABM Verification", systemImage: "checkmark.shield")
            }
            .help("Run Demo ABM Verification")

            Button {
                viewModel.lookupSinglePreloadSerial()
            } label: {
                Label("Simulate Jamf Preload Lookup", systemImage: "magnifyingglass")
            }
            .help("Simulate Jamf Preload Lookup")

            Button {
                viewModel.sendSelectedInventoryPreload()
            } label: {
                Label("Simulate Jamf Preload Submission", systemImage: "paperplane")
            }
            .help("Simulate Jamf Preload Submission. No live Jamf actions.")

            Button {
                viewModel.createPreloadUpdateBatch()
            } label: {
                Label("Preview Demo Preload Update Batch", systemImage: "arrow.triangle.2.circlepath")
            }
            .help("Preview Demo Preload Update Batch")

            Button {
                viewModel.generateSDPlusExport()
            } label: {
                Label("Generate Demo SD+ Export", systemImage: "square.and.arrow.up")
            }
            .help("Generate Demo SD+ Export")

            Button {
                viewModel.generateCurrentViewExportPreview()
            } label: {
                Label("Preview Demo Current View", systemImage: "doc.on.doc")
            }
            .help("Preview Demo Current View")

            Button {
                if let selectedDeviceID = viewModel.selectedDeviceID {
                    viewModel.archiveDevice(id: selectedDeviceID)
                }
            } label: {
                Label("Archive Demo Record", systemImage: "archivebox")
            }
            .disabled(viewModel.selectedDeviceID == nil)
            .help("Archive Demo Record")

            Spacer(minLength: ForsettiTheme.Spacing.item)

            TextField(
                "Filter",
                text: Binding(
                    get: { viewModel.filterText },
                    set: { viewModel.updateFilterText($0) }
                )
            )
            .textFieldStyle(.roundedBorder)
            .frame(width: 260)
        }
        .padding(12)
        .forsettiCardSurface()
    }
}

// Scrollable configurable grid. Columns come from the active Workbench layout;
// rows come from the projection service after filters and display formatting are
// applied. This view owns only gesture state for drag reorder and resize.
private struct InProgressGridView: View {
    @ObservedObject var viewModel: DeploymentTrackerViewModel
    @State private var draggedFieldKey: String?
    @State private var resizeStartWidth: Double?

    private var projection: DeploymentWorkbenchProjection {
        viewModel.projection
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if projection.columns.isEmpty {
                DeploymentWorkbenchEmptyState(
                    title: "No visible fields",
                    message: "Open Customize Columns and enable at least one field.",
                    primaryLabel: "Customize Columns",
                    primarySystemImage: "rectangle.grid.2x2",
                    primaryAction: { viewModel.showFieldCatalog() },
                    secondaryLabel: "Open Guide",
                    secondarySystemImage: "questionmark.circle",
                    secondaryAction: { viewModel.openGuide(topicID: "customize-columns", sourceWorkspace: .inProgress) }
                )
            } else {
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        headerRow
                        Divider()
                        if projection.rows.isEmpty {
                            DeploymentWorkbenchEmptyState(
                                title: "No active devices match this view",
                                message: "Clear the filter, import device records, or create a device before running workbench actions.",
                                primaryLabel: "Clear Filter",
                                primarySystemImage: "line.3.horizontal.decrease.circle",
                                primaryAction: { viewModel.updateFilterText("") },
                                secondaryLabel: "Import Devices",
                                secondarySystemImage: "tray.and.arrow.down",
                                secondaryAction: { viewModel.selectWorkspace(.intakeImports) }
                            )
                            .frame(width: max(CGFloat(520), projection.columns.reduce(CGFloat(0)) { $0 + columnWidth($1) }))
                        } else {
                            ForEach(projection.rows) { row in
                                rowView(row)
                                Divider()
                            }
                        }
                    }
                    .padding(1)
                }
                .frame(minHeight: 320, maxHeight: 520)
            }
        }
        .forsettiCardSurface()
    }

    private var headerRow: some View {
        // Header cells expose source-of-truth, pinning, drag reorder, and edge
        // resizing. The actual layout math remains in DeploymentFieldCatalogService.
        HStack(spacing: 0) {
            ForEach(projection.columns) { column in
                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(column.field.displayName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(column.field.sourceOfTruth.rawValue)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(ForsettiTheme.surface)
                        .clipShape(Capsule())
                    if column.layoutColumn.pinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(ForsettiTheme.accent)
                    }
                    Spacer(minLength: 0)
                    Button {
                        viewModel.setColumnPinned(column.field.fieldKey, isPinned: !column.layoutColumn.pinned)
                    } label: {
                        Image(systemName: column.layoutColumn.pinned ? "pin.slash" : "pin")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                    .help(column.layoutColumn.pinned ? "Unpin Column" : "Pin Column")
                }
                .frame(width: columnWidth(column), height: 38, alignment: .leading)
                .padding(.horizontal, 10)
                .background(ForsettiTheme.groupedSurface)
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(ForsettiTheme.border)
                        .frame(width: 4)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 2)
                                .onChanged { value in
                                    let start = resizeStartWidth ?? column.layoutColumn.width
                                    resizeStartWidth = start
                                    viewModel.setColumnWidth(column.field.fieldKey, width: start + value.translation.width)
                                }
                                .onEnded { _ in
                                    resizeStartWidth = nil
                                }
                        )
                }
                .onDrag {
                    draggedFieldKey = column.field.fieldKey
                    return NSItemProvider(object: column.field.fieldKey as NSString)
                }
                .onDrop(
                    of: [.text],
                    delegate: DeploymentColumnDropDelegate(
                        targetFieldKey: column.field.fieldKey,
                        draggedFieldKey: $draggedFieldKey,
                        viewModel: viewModel
                    )
                )
                .help("\(column.field.displayName) • \(column.field.sourceOfTruth.rawValue) • Drag to reorder, drag the right edge to resize.")
            }
        }
    }

    private func rowView(_ row: DeploymentWorkbenchRowProjection) -> some View {
        // Rows render from projected cells so editable values, read-only
        // snapshots, and derived display values all use the same formatting path
        // as exports and inspectors.
        HStack(spacing: 0) {
            ForEach(projection.columns) { column in
                let cell = row.cell(for: column.field.fieldKey)
                DeploymentWorkbenchEditableCell(
                    row: row,
                    field: column.field,
                    cell: cell,
                    viewModel: viewModel
                )
                .frame(width: columnWidth(column), height: 38, alignment: .leading)
                .padding(.horizontal, 8)
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(ForsettiTheme.border.opacity(0.75))
                        .frame(width: 1)
                }
            }
        }
        .background(row.id == viewModel.selectedDeviceID ? ForsettiTheme.accent.opacity(0.14) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.selectRow(id: row.id)
        }
        .contextMenu {
            Button("Validate Demo Jamf Preload") { viewModel.validateSelectedForPreload() }
            Button("Simulate Jamf Preload Lookup") { viewModel.lookupSinglePreloadSerial() }
            Button("Simulate Demo Reconciliation") { viewModel.reconcileSelectedPreload() }
            Divider()
            Button("Archive Demo Record") { viewModel.archiveDevice(id: row.id) }
        }
    }

    private func columnWidth(_ column: DeploymentWorkbenchColumnProjection) -> CGFloat {
        CGFloat(column.layoutColumn.width)
    }
}

// Drop delegate for column reordering. The delegate performs the reorder as the
// drag enters a target header so users get immediate visual feedback.
private struct DeploymentColumnDropDelegate: DropDelegate {
    let targetFieldKey: String
    @Binding var draggedFieldKey: String?
    @ObservedObject var viewModel: DeploymentTrackerViewModel

    func dropEntered(info: DropInfo) {
        guard let draggedFieldKey, draggedFieldKey != targetFieldKey else {
            return
        }
        viewModel.moveVisibleColumn(draggedFieldKey, before: targetFieldKey)
        self.draggedFieldKey = targetFieldKey
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedFieldKey = nil
        return true
    }
}

// Shared empty-state block for cases where no fields are visible or no rows
// match the current filter. Primary and secondary actions keep the user moving
// toward the next useful workspace action.
private struct DeploymentWorkbenchEmptyState: View {
    let title: String
    let message: String
    let primaryLabel: String
    let primarySystemImage: String
    let primaryAction: () -> Void
    let secondaryLabel: String
    let secondarySystemImage: String
    let secondaryAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ForsettiTheme.Spacing.compact) {
            Label(title, systemImage: "tray")
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(action: primaryAction) {
                    Label(primaryLabel, systemImage: primarySystemImage)
                }
                Button(action: secondaryAction) {
                    Label(secondaryLabel, systemImage: secondarySystemImage)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .center)
        .padding(18)
    }
}

// Grid cell renderer. Editable Tracker-owned fields get controls; read-only
// Jamf, ABM, audit, system, or derived fields render as text or visual binary
// indicators to reinforce source-of-truth boundaries.
private struct DeploymentWorkbenchEditableCell: View {
    let row: DeploymentWorkbenchRowProjection
    let field: DeploymentFieldDefinition
    let cell: DeploymentWorkbenchCellProjection?
    @ObservedObject var viewModel: DeploymentTrackerViewModel
    @State private var draftValue: String

    init(
        row: DeploymentWorkbenchRowProjection,
        field: DeploymentFieldDefinition,
        cell: DeploymentWorkbenchCellProjection?,
        viewModel: DeploymentTrackerViewModel
    ) {
        self.row = row
        self.field = field
        self.cell = cell
        self.viewModel = viewModel
        _draftValue = State(initialValue: cell?.rawValue ?? "")
    }

    var body: some View {
        Group {
            if field.editable && field.sourceOfTruth == .deploymentTracker {
                editor
            } else {
                readOnlyCell
            }
        }
        .onChange(of: cell?.rawValue ?? "") { _, newValue in
            draftValue = newValue
        }
    }

    @ViewBuilder
    private var editor: some View {
        // Field type drives the inline editor. Boolean fields use toggles,
        // reference fields use data-backed pickers, and free-form fields commit
        // on return so rapid grid navigation remains lightweight.
        switch field.fieldType {
        case .boolean:
            Toggle(
                "",
                isOn: Binding(
                    get: { draftValue == "true" },
                    set: { newValue in
                        draftValue = newValue ? "true" : "false"
                        viewModel.updateDeviceField(deviceId: row.id, field: field, rawValue: draftValue)
                    }
                )
            )
            .labelsHidden()
        case .reference:
            Picker(
                "",
                selection: Binding(
                    get: { draftValue },
                    set: { newValue in
                        draftValue = newValue
                        viewModel.updateDeviceField(deviceId: row.id, field: field, rawValue: newValue)
                    }
                )
            ) {
                Text("None").tag("")
                ForEach(viewModel.referenceOptions(for: field)) { value in
                    Text(value.displayName).tag(value.id)
                }
            }
            .labelsHidden()
        case .date, .dateTime:
            TextField(
                "",
                text: Binding(
                    get: { draftValue },
                    set: { draftValue = $0 }
                ),
                onCommit: {
                    viewModel.updateDeviceField(deviceId: row.id, field: field, rawValue: draftValue)
                }
            )
            .textFieldStyle(.plain)
        default:
            TextField(
                "",
                text: Binding(
                    get: { draftValue },
                    set: { draftValue = $0 }
                ),
                onCommit: {
                    viewModel.updateDeviceField(deviceId: row.id, field: field, rawValue: draftValue)
                }
            )
            .textFieldStyle(.plain)
        }
    }

    private var readOnlyCell: some View {
        // Binary read-only values are shown as icon labels so technicians can
        // scan true/false state quickly without parsing raw text.
        Group {
            if field.fieldType == .boolean {
                Label(booleanLabel, systemImage: booleanIcon)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(booleanColor)
            } else {
                Text(cell?.displayValue.isEmpty == false ? cell?.displayValue ?? "" : " ")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .help(field.sourceOfTruth == .deploymentTracker ? "Read-only field" : "Read-only \(field.sourceOfTruth.rawValue) snapshot")
    }

    private var booleanLabel: String {
        let value = (cell?.rawValue ?? cell?.displayValue ?? "").lowercased()
        return ["true", "yes", "1", "active"].contains(value) ? "Yes" : "No"
    }

    private var booleanIcon: String {
        booleanLabel == "Yes" ? "checkmark.circle.fill" : "xmark.circle"
    }

    private var booleanColor: Color {
        booleanLabel == "Yes" ? .green : .secondary
    }
}

// Searchable catalog for field visibility and layout controls. It gives the
// same fields multiple discovery paths: category, source system, visibility, and
// editability.
private struct InProgressFieldCatalogPanel: View {
    @ObservedObject var viewModel: DeploymentTrackerViewModel
    @State private var searchText = ""
    @State private var selectedCategory = "All"
    @State private var selectedSource = "All"
    @State private var selectedVisibility = "All"
    @State private var selectedEditability = "All"

    var body: some View {
        VStack(alignment: .leading, spacing: ForsettiTheme.Spacing.section) {
            HStack {
                Label("Field Catalog", systemImage: "rectangle.grid.2x2")
                    .font(.system(.title2, design: .rounded).weight(.semibold))
                Spacer()
                Button {
                    viewModel.isFieldCatalogPresented = false
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Close")
            }

            VStack(alignment: .leading, spacing: ForsettiTheme.Spacing.compact) {
                TextField("Search fields by name, key, category, source, or type", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Search Field Catalog")

                HStack(spacing: ForsettiTheme.Spacing.item) {
                    Picker("Category", selection: $selectedCategory) {
                        Text("All Categories").tag("All")
                        ForEach(categories, id: \.self) { category in
                            Text(category).tag(category)
                        }
                    }
                    Picker("Source", selection: $selectedSource) {
                        Text("All Sources").tag("All")
                        ForEach(DeploymentFieldSourceOfTruth.allCases, id: \.rawValue) { source in
                            Text(source.rawValue).tag(source.rawValue)
                        }
                    }
                    Picker("Visibility", selection: $selectedVisibility) {
                        Text("All Fields").tag("All")
                        Text("Visible").tag("Visible")
                        Text("Hidden").tag("Hidden")
                    }
                    Picker("Editability", selection: $selectedEditability) {
                        Text("Editable and Read-only").tag("All")
                        Text("Editable").tag("Editable")
                        Text("Read-only").tag("Read-only")
                    }
                }
            }

            ScrollView {
                if groupedFields.isEmpty {
                    ContentUnavailableView(
                        "No Matching Fields",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("Clear the search or loosen a filter.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 260)
                } else {
                    VStack(alignment: .leading, spacing: ForsettiTheme.Spacing.section) {
                        ForEach(groupedFields) { group in
                            VStack(alignment: .leading, spacing: ForsettiTheme.Spacing.compact) {
                                Text(group.category)
                                    .font(.headline)

                                ForEach(group.fields) { field in
                                    fieldRow(field)
                                }
                            }
                        }
                    }
                    .padding(.trailing, 4)
                }
            }
        }
        .padding(ForsettiTheme.Spacing.section)
        .background(ForsettiTheme.groupedSurface)
    }

    private var categories: [String] {
        Array(Set(viewModel.fieldDefinitions.map(\.category))).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    private var matchingFields: [DeploymentFieldDefinition] {
        // Filter locally for immediate response while editing catalog controls.
        // The field catalog operates on definitions, not device rows, so this
        // search has no dependency on Jamf, ABM, or imported snapshots.
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return viewModel.fieldDefinitions.filter { field in
            let matchesQuery = query.isEmpty || [
                field.displayName,
                field.fieldKey,
                field.category,
                field.sourceOfTruth.rawValue,
                field.fieldType.rawValue
            ]
            .joined(separator: " ")
            .lowercased()
            .contains(query)
            let matchesCategory = selectedCategory == "All" || field.category == selectedCategory
            let matchesSource = selectedSource == "All" || field.sourceOfTruth.rawValue == selectedSource
            let matchesVisibility = selectedVisibility == "All"
                || (selectedVisibility == "Visible" && viewModel.isFieldVisible(field.fieldKey))
                || (selectedVisibility == "Hidden" && !viewModel.isFieldVisible(field.fieldKey))
            let matchesEditability = selectedEditability == "All"
                || (selectedEditability == "Editable" && field.editable && field.sourceOfTruth == .deploymentTracker)
                || (selectedEditability == "Read-only" && !(field.editable && field.sourceOfTruth == .deploymentTracker))
            return matchesQuery && matchesCategory && matchesSource && matchesVisibility && matchesEditability
        }
    }

    private var groupedFields: [DeploymentFieldCatalogGroup] {
        // Grouping by definition category matches the way inspectors and guide
        // topics explain the data, which keeps customization aligned with the
        // rest of the Workbench.
        let grouped = Dictionary(grouping: matchingFields) { $0.category }
        return grouped.keys.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
        .map { category in
            DeploymentFieldCatalogGroup(
                category: category,
                fields: grouped[category, default: []].sorted {
                    $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                }
            )
        }
    }

    private func fieldRow(_ field: DeploymentFieldDefinition) -> some View {
        // A field row edits only layout metadata. It never mutates device data,
        // external snapshots, or field definitions.
        HStack(alignment: .center, spacing: ForsettiTheme.Spacing.compact) {
            Toggle(
                isOn: Binding(
                    get: { viewModel.isFieldVisible(field.fieldKey) },
                    set: { viewModel.setColumnVisible(field.fieldKey, isVisible: $0) }
                )
            ) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(field.displayName)
                        .font(.callout.weight(.medium))
                    HStack(spacing: 6) {
                        Text(field.sourceOfTruth.rawValue)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(ForsettiTheme.groupedSurface)
                            .clipShape(Capsule())
                        Text(field.fieldType.rawValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(field.editable && field.sourceOfTruth == .deploymentTracker ? "Editable" : "Read-only")
                            .font(.caption)
                            .foregroundStyle(field.editable && field.sourceOfTruth == .deploymentTracker ? .green : .secondary)
                    }
                }
            }

            Spacer(minLength: ForsettiTheme.Spacing.compact)

            Button {
                viewModel.moveVisibleColumn(field.fieldKey, offset: -1)
            } label: {
                Image(systemName: "arrow.left")
            }
            .disabled(!viewModel.isFieldVisible(field.fieldKey))
            .help("Move Left")

            Button {
                viewModel.moveVisibleColumn(field.fieldKey, offset: 1)
            } label: {
                Image(systemName: "arrow.right")
            }
            .disabled(!viewModel.isFieldVisible(field.fieldKey))
            .help("Move Right")

            Button {
                viewModel.resizeColumn(field.fieldKey, by: -24)
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .disabled(!viewModel.isFieldVisible(field.fieldKey))
            .help("Narrow Column")

            Button {
                viewModel.resizeColumn(field.fieldKey, by: 24)
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .disabled(!viewModel.isFieldVisible(field.fieldKey))
            .help("Widen Column")

            Button {
                viewModel.setColumnPinned(field.fieldKey, isPinned: !viewModel.isFieldPinned(field.fieldKey))
            } label: {
                Image(systemName: viewModel.isFieldPinned(field.fieldKey) ? "pin.slash" : "pin")
            }
            .disabled(!viewModel.isFieldVisible(field.fieldKey))
            .help(viewModel.isFieldPinned(field.fieldKey) ? "Unpin Column" : "Pin Column")
        }
        .padding(10)
        .background(ForsettiTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: ForsettiTheme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: ForsettiTheme.Radius.card, style: .continuous)
                .stroke(ForsettiTheme.border, lineWidth: 1)
        }
    }
}

// Simple grouping model for the Field Catalog. The id is the visible category
// title so SwiftUI can keep category sections stable across filter updates.
private struct DeploymentFieldCatalogGroup: Identifiable {
    let category: String
    let fields: [DeploymentFieldDefinition]

    var id: String { category }
}

// Inspector shows the selected row grouped by technician intent rather than raw
// column order. It is read-only because inline edits are handled directly inside
// the Workbench grid.
private struct InProgressInspectorView: View {
    let row: DeploymentWorkbenchRowProjection
    let fieldDefinitions: [DeploymentFieldDefinition]

    var body: some View {
        VStack(alignment: .leading, spacing: ForsettiTheme.Spacing.compact) {
            Label("Inspector", systemImage: "sidebar.right")
                .font(.headline)

            ForEach(groupedCells) { group in
                VStack(alignment: .leading, spacing: ForsettiTheme.Spacing.compact) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(group.title)
                            .font(.subheadline.weight(.semibold))
                        Text(group.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), alignment: .leading)], alignment: .leading, spacing: ForsettiTheme.Spacing.compact) {
                        ForEach(group.items) { item in
                            InspectorFieldTile(item: item)
                        }
                    }
                }
            }
        }
        .padding(14)
        .forsettiCardSurface()
    }

    private var definitionsByKey: [String: DeploymentFieldDefinition] {
        Dictionary(uniqueKeysWithValues: fieldDefinitions.map { ($0.fieldKey, $0) })
    }

    private var groupedCells: [InspectorGroup] {
        // Convert projected cells back to field-aware items, then apply the
        // curated group definitions below. Missing definitions are skipped
        // instead of crashing so older persisted layouts stay survivable.
        let items = row.cells.compactMap { cell -> InspectorFieldItem? in
            guard let field = definitionsByKey[cell.fieldKey] else {
                return nil
            }
            return InspectorFieldItem(cell: cell, field: field)
        }
        return InspectorGroupDefinition.all.compactMap { definition in
            let matched = items.filter { definition.matches($0.field) }
            guard matched.isEmpty == false else {
                return nil
            }
            return InspectorGroup(title: definition.title, summary: definition.summary, items: matched)
        }
    }
}

// Inspector groups carry a title, explanation, and display-ready fields for one
// section in the selected-row detail panel.
private struct InspectorGroup: Identifiable {
    var id: String { title }
    let title: String
    let summary: String
    let items: [InspectorFieldItem]
}

// Field item joins a projected cell with its field definition so the tile can
// render display value, binary state, required-state warnings, and source labels.
private struct InspectorFieldItem: Identifiable {
    var id: String { field.fieldKey }
    let cell: DeploymentWorkbenchCellProjection
    let field: DeploymentFieldDefinition

    var displayValue: String {
        cell.displayValue.isEmpty ? "Empty" : cell.displayValue
    }

    var booleanDisplayValue: String {
        let value = cell.rawValue.lowercased()
        return ["true", "yes", "1", "active"].contains(value) ? "Yes" : "No"
    }

    var stateLabel: String {
        if field.required && cell.displayValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Missing required"
        }
        return field.editable && field.sourceOfTruth == .deploymentTracker ? "Editable" : "Read-only"
    }
}

// Curated grouping rules for inspector sections. These rules intentionally use
// stable field keys and categories rather than visible column order so hidden
// fields can still appear in the inspector when they are operationally relevant.
private struct InspectorGroupDefinition {
    let title: String
    let summary: String
    let matcher: (DeploymentFieldDefinition) -> Bool

    func matches(_ field: DeploymentFieldDefinition) -> Bool {
        matcher(field)
    }

    static let all: [InspectorGroupDefinition] = [
        InspectorGroupDefinition(title: "Summary", summary: "Primary row identity.") { field in
            ["device.serialNumber", "device.assetTag", "device.model", "device.deviceTypeId"].contains(field.fieldKey)
        },
        InspectorGroupDefinition(title: "Required Next Action", summary: "Status, blocking state, and immediate gates.") { field in
            field.fieldKey.contains("workflowStatus") || field.category == "Exceptions" || field.fieldKey.contains("Exception")
        },
        InspectorGroupDefinition(title: "Identity", summary: "Serial, replacement, user, and local identifiers.") { field in
            field.category == "Identity" || field.category == "User Assignment"
        },
        InspectorGroupDefinition(title: "Project", summary: "Project and ticket context.") { field in
            field.category == "Project" || field.fieldKey.contains("ticket")
        },
        InspectorGroupDefinition(title: "Workflow", summary: "Tracker workflow and local operational state.") { field in
            field.category == "Workflow"
        },
        InspectorGroupDefinition(title: "Jamf Preload", summary: "Inventory Preload and Jamf snapshot data.") { field in
            field.category.contains("Jamf") || field.fieldKey.lowercased().contains("jamf")
        },
        InspectorGroupDefinition(title: "ABM Snapshot", summary: "Read-only Apple Business verification data.") { field in
            field.category.contains("ABM") || field.sourceOfTruth == .abm
        },
        InspectorGroupDefinition(title: "SD+ Export", summary: "ServiceDesk Plus export state.") { field in
            field.category.contains("SD+") || field.fieldKey.lowercased().contains("sdplus")
        },
        InspectorGroupDefinition(title: "Shipping", summary: "Outbound, return, and delivery fields.") { field in
            field.category == "Shipping" || field.category == "Returns" || field.fieldKey.lowercased().contains("tracking")
        },
        InspectorGroupDefinition(title: "Exceptions", summary: "Local exception counters and blockers.") { field in
            field.category == "Exceptions"
        },
        InspectorGroupDefinition(title: "Audit Summary", summary: "System, derived, notes, and audit-supporting fields.") { field in
            field.sourceOfTruth == .audit || field.sourceOfTruth == .system || field.sourceOfTruth == .derived || field.category == "Notes"
        }
    ]
}

// Compact field tile for inspector values. Boolean fields render as visual
// indicators, required empty fields are flagged, and source labels keep local
// Tracker data distinct from external snapshots.
private struct InspectorFieldTile: View {
    let item: InspectorFieldItem

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(item.field.displayName)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text(item.field.sourceOfTruth.rawValue)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(ForsettiTheme.surface)
                    .clipShape(Capsule())
            }
            if item.field.fieldType == .boolean {
                Label(item.booleanDisplayValue, systemImage: item.booleanDisplayValue == "Yes" ? "checkmark.circle.fill" : "xmark.circle")
                    .font(.callout.weight(.medium))
                    .foregroundStyle(item.booleanDisplayValue == "Yes" ? .green : .secondary)
            } else {
                Text(item.displayValue)
                    .font(.callout)
                    .lineLimit(2)
            }
            Label(item.stateLabel, systemImage: item.stateLabel == "Missing required" ? "exclamationmark.triangle" : "circle.fill")
                .font(.caption2)
                .foregroundStyle(item.stateLabel == "Missing required" ? .orange : .secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(ForsettiTheme.groupedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

// Validation drawer groups raw validation strings into actionable categories so
// technicians can tell whether the next step is data entry, external mismatch
// review, permission repair, or normal warning review.
private struct InProgressValidationDrawer: View {
    let messages: [String]
    @ObservedObject var viewModel: DeploymentTrackerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: ForsettiTheme.Spacing.compact) {
            Label("Validation", systemImage: "checklist")
                .font(.headline)

            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label(group.title, systemImage: group.systemImage)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(group.color)
                        Spacer()
                        Button {
                            viewModel.openGuide(topicID: group.guideTopicID, sourceWorkspace: .inProgress)
                        } label: {
                            Label("Guide", systemImage: "questionmark.circle")
                        }
                        .font(.caption)
                    }
                    Text(group.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    ForEach(group.messages, id: \.self) { message in
                        Label(message, systemImage: "circle.fill")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(ForsettiTheme.groupedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .padding(14)
        .forsettiCardSurface()
    }

    private var groups: [ValidationMessageGroup] {
        Dictionary(grouping: messages, by: ValidationMessageGroup.classify)
            .map { category, messages in
                category.withMessages(messages.sorted())
            }
            .sorted { $0.sortOrder < $1.sortOrder }
    }
}

// Classification model for validation messages. It is intentionally simple and
// string-based because validation services already produce user-facing messages;
// this layer only needs enough classification to choose a heading, icon, color,
// and guide topic.
private struct ValidationMessageGroup: Identifiable {
    enum Category: Int {
        case ready = 0
        case missingRequired = 1
        case externalMismatch = 2
        case permissionBlocked = 3
        case warnings = 4
        case blocked = 5

        func withMessages(_ messages: [String]) -> ValidationMessageGroup {
            switch self {
            case .ready:
                return ValidationMessageGroup(title: "Ready", summary: "Rows or fields are ready for the next action.", systemImage: "checkmark.circle", color: .green, guideTopicID: "workbench", sortOrder: rawValue, messages: messages)
            case .missingRequired:
                return ValidationMessageGroup(title: "Missing Required Fields", summary: "Complete these fields before running the action.", systemImage: "exclamationmark.triangle", color: .orange, guideTopicID: "exceptions-validation", sortOrder: rawValue, messages: messages)
            case .externalMismatch:
                return ValidationMessageGroup(title: "External Mismatches", summary: "Review read-only Jamf or ABM snapshot differences.", systemImage: "arrow.left.arrow.right.circle", color: .orange, guideTopicID: "abm-verification", sortOrder: rawValue, messages: messages)
            case .permissionBlocked:
                return ValidationMessageGroup(title: "Permission Blocked", summary: "Jamf role privileges are missing or need review.", systemImage: "lock.shield", color: .red, guideTopicID: "jamf-permissions", sortOrder: rawValue, messages: messages)
            case .warnings:
                return ValidationMessageGroup(title: "Warnings", summary: "The action may run, but these values should be reviewed.", systemImage: "exclamationmark.triangle", color: .orange, guideTopicID: "exceptions-validation", sortOrder: rawValue, messages: messages)
            case .blocked:
                return ValidationMessageGroup(title: "Blocked", summary: "The action should not continue until these issues are resolved.", systemImage: "xmark.octagon", color: .red, guideTopicID: "exceptions-validation", sortOrder: rawValue, messages: messages)
            }
        }
    }

    let title: String
    let summary: String
    let systemImage: String
    let color: Color
    let guideTopicID: String
    let sortOrder: Int
    let messages: [String]

    var id: String { title }

    nonisolated static func classify(_ message: String) -> Category {
        let lowercased = message.lowercased()
        if lowercased.contains("ready") {
            return .ready
        }
        if lowercased.contains("missing") || lowercased.contains("required") || lowercased.contains("empty") {
            return .missingRequired
        }
        if lowercased.contains("permission") || lowercased.contains("privilege") || lowercased.contains("403") {
            return .permissionBlocked
        }
        if lowercased.contains("abm") || lowercased.contains("jamf") || lowercased.contains("mismatch") || lowercased.contains("snapshot") {
            return .externalMismatch
        }
        if lowercased.contains("warning") || lowercased.contains("warn") {
            return .warnings
        }
        return .blocked
    }
}

// Fallback refresh error shown inside the Workbench when persistence reloads or
// projection setup fails. Structured integration errors use the richer root
// error card in DeploymentTrackerModule.swift.
private struct DeploymentUserFacingErrorView: View {
    let message: String
    @ObservedObject var viewModel: DeploymentTrackerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: ForsettiTheme.Spacing.compact) {
            Label("Workbench data could not refresh", systemImage: "exclamationmark.octagon")
                .font(.headline)
                .foregroundStyle(.red)
            Text(message)
                .font(.callout)
            Text("Local data changed: No • External data changed: No • Safe to retry: Yes")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button {
                    Task { await viewModel.loadWorkbench() }
                } label: {
                    Label("Retry Refresh", systemImage: "arrow.clockwise")
                }
                Button {
                    viewModel.openGuide(topicID: "diagnostics", sourceWorkspace: .inProgress)
                } label: {
                    Label("Open Diagnostics Guide", systemImage: "questionmark.circle")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .forsettiCardSurface()
    }
}

// Inline export preview for the current Workbench view. It is intentionally a
// preview surface, not a file writer, so the user can inspect exactly which
// visible rows and columns are about to be exported.
private struct InProgressExportPreviewView: View {
    let csv: String

    var body: some View {
        VStack(alignment: .leading, spacing: ForsettiTheme.Spacing.compact) {
            Label("Export Preview", systemImage: "doc.plaintext")
                .font(.headline)
            ScrollView(.horizontal) {
                Text(csv.isEmpty ? "No rows" : csv)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
            }
            .frame(maxHeight: 160)
            .background(ForsettiTheme.groupedSurface)
            .clipShape(RoundedRectangle(cornerRadius: ForsettiTheme.Radius.card, style: .continuous))
        }
        .padding(14)
        .forsettiCardSurface()
    }
}
