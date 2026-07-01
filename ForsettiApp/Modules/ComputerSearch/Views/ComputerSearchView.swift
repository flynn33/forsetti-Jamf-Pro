import SwiftUI
import UniformTypeIdentifiers

// "End of Line"

/// The primary view for the Computer Search module, providing a search interface,
/// profile management, and a results list for Jamf Pro computer inventory queries.
///
/// This view is organized into three sections:
/// 1. **Search** -- A text field for the query, a profile picker, field catalog access, and a search button.
/// 2. **Search Profiles** -- A list of saved profiles that can be tapped to apply or swiped to delete.
/// 3. **Results** -- The list of `ComputerRecord` rows returned by the most recent search.
///
/// The view also presents a sheet for the field catalog and an alert for saving new profiles.
struct ComputerSearchView: View {
    /// The view model that drives search execution, profile management, and state.
    @StateObject private var viewModel: ComputerSearchViewModel

    /// Live state for the Advanced Search sheet. Created on demand so each open
    /// starts from the current field selection without retaining stale state.
    @State private var advancedSearchViewModel: ComputerAdvancedSearchViewModel?

    /// Whether the results list is in multi-select (share) mode.
    @State private var isSelecting = false
    /// IDs of records currently selected for sharing.
    @State private var selectedIDs: Set<String> = []
    /// Drives the `.fileExporter` Save panel (both platforms).
    @State private var isExporting = false

    /// Creates the search view with an injected view model.
    ///
    /// - Parameter viewModel: The `ComputerSearchViewModel` that manages all search logic and state.
    init(viewModel: ComputerSearchViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        List {
            // MARK: - Search Input Section
            Section("Search") {
                HStack(spacing: 8) {
                    TextField("Computer name, serial, username, email", text: $viewModel.query.strippingControlCharacters())
                        .dashboardNoAutoCorrectionTextInput()

                    // Barcode/QR scanner button for quick serial or asset tag entry
                    ScanIntoTextFieldButton(text: $viewModel.query.strippingControlCharacters())
                }

                Picker("Search Profile", selection: $viewModel.selectedProfileID) {
                    Text("None").tag(nil as UUID?)
                    ForEach(viewModel.profiles) { profile in
                        Text(profile.name).tag(profile.id as UUID?)
                    }
                }
                .pickerStyle(.menu)

                HStack {
                    Button("Fields") {
                        viewModel.isFieldCatalogPresented = true
                    }
                    .buttonStyle(.dashboardSecondary)

                    // Opens the multi-criteria Advanced Search sheet
                    Button("Advanced") {
                        advancedSearchViewModel = viewModel.makeAdvancedSearchViewModel()
                        viewModel.isAdvancedSearchPresented = true
                    }
                    .buttonStyle(.dashboardSecondary)

                    Spacer()

                    Button {
                        Task {
                            await viewModel.executeSearch()
                        }
                    } label: {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.dashboardPrimary)
                }
            }

            // MARK: - Error Display
            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            // MARK: - Decoding Notice (non-fatal degraded response)
            if let notice = viewModel.decodingNoticeMessage {
                Section {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }

            // MARK: - Saved Profiles Section
            if viewModel.profiles.isEmpty == false {
                Section("Search Profiles") {
                    ForEach(viewModel.profiles) { profile in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(profile.name)
                                Text("\(profile.fieldKeys.count) fields")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            // Checkmark badge indicates the currently active profile
                            if viewModel.selectedProfileID == profile.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(DashboardColors.greenPrimary)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.selectedProfileID = profile.id
                            viewModel.applySelectedProfileFields()
                        }
                    }
                    .onDelete(perform: viewModel.deleteProfiles)
                }
            }

            // MARK: - Smart Filters Section
            if viewModel.smartFilters.isEmpty == false {
                Section("Smart Filters") {
                    SmartFilterListView(
                        filters: viewModel.smartFilters,
                        onSelect: { filter in
                            advancedSearchViewModel = viewModel.loadSmartFilterIntoAdvancedSearch(filter)
                            viewModel.isAdvancedSearchPresented = true
                        },
                        onDelete: viewModel.deleteSmartFilters(at:)
                    )
                }
            }

            // MARK: - Results Section
            Section("Results") {
                if viewModel.isSearching {
                    ProgressView("Searching Jamf Pro...")
                } else if viewModel.searchResults.isEmpty {
                    Text("No results yet. Run a search to view computers.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.searchResults) { record in
                        resultRow(for: record)
                    }
                }
            }
        }
        .dashboardInsetGroupedListStyle()
        .toolbar {
            if isSelecting {
                ToolbarItem(placement: .dashboardTopBarLeading) {
                    Button("Cancel") { exitSelection() }
                }
                ToolbarItemGroup(placement: .dashboardTopBarTrailing) {
                    Button(allSelected ? "Deselect All" : "Select All") { toggleSelectAll() }
                        .disabled(viewModel.searchResults.isEmpty)

                    if selectedIDs.isEmpty == false {
                        // Shares the selected records' Markdown as plain text, so the share
                        // sheet's Copy behaves as normal text copy/paste; Save writes the file.
                        ShareLink(item: RecordMarkdown.document(for: selectedRecords)) {
                            Label("Share \(selectedIDs.count)", systemImage: "square.and.arrow.up")
                        }
                    } else {
                        Button { } label: { Label("Share", systemImage: "square.and.arrow.up") }
                            .disabled(true)
                    }

                    Button { isExporting = true } label: {
                        Label("Save", systemImage: "square.and.arrow.down")
                    }
                    .disabled(selectedIDs.isEmpty)
                }
            } else {
                ToolbarItem(placement: .dashboardTopBarTrailing) {
                    Button { isSelecting = true } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .disabled(viewModel.searchResults.isEmpty)
                }
            }
        }
        .onChange(of: viewModel.searchResults.map(\.id)) { _, _ in
            if isSelecting { exitSelection() }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: TextFileDocument(text: RecordMarkdown.document(for: selectedRecords)),
            contentType: .dashboardMarkdown,
            defaultFilename: "Computers"
        ) { _ in isExporting = false }
        .navigationDestination(for: ComputerRecordRoute.self) { route in
            ComputerDetailView(viewModel: viewModel, recordID: route.id)
        }
        .task {
            // Load saved profiles and smart filters from disk, and hydrate the
            // tenant's extension attributes, on first appearance.
            await viewModel.loadProfiles()
            await viewModel.loadSmartFilters()
            await viewModel.loadExtensionAttributes()
        }
        .onChange(of: viewModel.selectedProfileID) { _, _ in
            viewModel.applySelectedProfileFields()
        }
        .sheet(isPresented: $viewModel.isFieldCatalogPresented) {
            ComputerFieldCatalogView(
                selectedFieldKeys: $viewModel.selectedFieldKeys,
                availableFields: viewModel.allCatalogFields,
                onSaveProfileRequested: {
                    viewModel.isFieldCatalogPresented = false

                    // Brief delay to let the sheet dismissal animation complete before showing the alert
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 200_000_000)
                        viewModel.presentSaveProfilePrompt()
                    }
                }
            )
            #if os(macOS)
            .frame(minWidth: 720, idealWidth: 820, minHeight: 600, idealHeight: 720)
            #endif
        }
        .sheet(isPresented: $viewModel.isAdvancedSearchPresented, onDismiss: {
            advancedSearchViewModel = nil
        }) {
            if let advancedSearchViewModel {
                ComputerAdvancedSearchView(
                    viewModel: advancedSearchViewModel,
                    onSearch: { result, fieldKeys in
                        viewModel.isAdvancedSearchPresented = false
                        Task {
                            await viewModel.executeAdvancedSearch(result, fieldKeys: fieldKeys)
                        }
                    },
                    onSaveSmartFilter: { filter in
                        Task {
                            await viewModel.saveOrUpdateSmartFilter(filter)
                        }
                    }
                )
            }
        }
        .alert("Save Search Profile", isPresented: $viewModel.isSaveProfilePromptPresented) {
            TextField("Profile name", text: $viewModel.pendingProfileName)

            Button("Cancel", role: .cancel) { }
            Button("Save") {
                Task {
                    await viewModel.saveProfileFromPrompt()
                }
            }
        } message: {
            Text("This profile stores the currently selected field toggles.")
        }
    }

    // MARK: - Multi-select sharing

    /// Records currently selected, in results order.
    private var selectedRecords: [ComputerRecord] {
        viewModel.searchResults.filter { selectedIDs.contains($0.id) }
    }

    /// Whether every visible result is selected.
    private var allSelected: Bool {
        viewModel.searchResults.isEmpty == false && selectedIDs.count == viewModel.searchResults.count
    }

    /// A results row: a selectable button in selection mode, otherwise the navigating link.
    @ViewBuilder
    private func resultRow(for record: ComputerRecord) -> some View {
        if isSelecting {
            Button {
                toggleSelection(record.id)
            } label: {
                HStack(spacing: 12) {
                    SelectionCircle(isSelected: selectedIDs.contains(record.id))
                    ComputerResultRow(record: record, fields: viewModel.resultFields)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: ComputerRecordRoute(id: record.id)) {
                ComputerResultRow(record: record, fields: viewModel.resultFields)
            }
        }
    }

    private func toggleSelection(_ id: String) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
    }

    private func toggleSelectAll() {
        if allSelected { selectedIDs.removeAll() }
        else { selectedIDs = Set(viewModel.searchResults.map(\.id)) }
    }

    /// Leaves selection mode and clears the current selection.
    private func exitSelection() {
        isSelecting = false
        selectedIDs.removeAll()
    }
}

/// A row view that displays a single computer record in the search results list.
///
/// Renders the computer name and serial number as the header, then the active
/// profile's fields with non-empty values resolved dynamically through
/// `ComputerRecord.value(for:)`, plus the Pre-Stage Enrollment composite when
/// present. Columns track the user's field selection rather than a fixed layout.
private struct ComputerResultRow: View {
    /// The computer record to display.
    let record: ComputerRecord

    /// The active catalog fields whose values should render as detail rows.
    let fields: [ComputerField]

    /// Field keys already represented by the row header (name + serial); skipped
    /// in the dynamic detail list to avoid duplication.
    private static let headerFieldKeys: Set<String> = [
        "id",
        "general.name",
        "computerName",
        "hardware.serialNumber",
        "serialNumber"
    ]

    private var displayTitle: String {
        record.value(for: "general.name") ?? record.computerName
    }

    private var visibleFields: [ComputerField] {
        fields.filter { field in
            guard Self.headerFieldKeys.contains(field.key) == false else {
                return false
            }
            guard let value = record.value(for: field.key) else { return false }
            return value.isEmpty == false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Primary identifier: the computer's display name
            Text(displayTitle)
                .font(DashboardSearchResultTypography.headline())

            // Always show the serial number as the secondary identifier
            Text("Serial: \(record.serialNumber)")
                .font(DashboardSearchResultTypography.subheadline())

            // Dynamic detail rows for each selected field with a non-empty value
            ForEach(visibleFields) { field in
                if let value = record.value(for: field.key) {
                    Text("\(field.displayName): \(value)")
                        .font(DashboardSearchResultTypography.caption())
                        .foregroundStyle(.secondary)
                }
            }

            // Pre-Stage Enrollment is resolved from first-class properties rather
            // than the field catalog, so it renders independently of selection.
            if let prestageDisplay = record.prestageDisplayValue, prestageDisplay.isEmpty == false {
                Text("Pre-Stage Enrollment: \(prestageDisplay)")
                    .font(DashboardSearchResultTypography.caption())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

//endofline
