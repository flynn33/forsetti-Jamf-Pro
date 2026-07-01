import SwiftUI
import UniformTypeIdentifiers

/// The primary view for the Mobile Device Search module.
///
/// `MobileDeviceSearchView` presents a search interface that lets users query the
/// Jamf Pro inventory by serial number or username, select a search profile to control
/// which fields appear in results, and view matching device records. It also provides
/// profile management (selecting, creating, and deleting saved profiles), a sheet
/// for the full field catalog, and an Advanced Search builder backed by RSQL.
///
/// Tapping a result row pushes a `MobileDeviceDetailView` onto the enclosing
/// `NavigationStack` (provided by `DashboardView`).
struct MobileDeviceSearchView: View {
    /// The view model that drives all search logic, profile management, and result state.
    @StateObject private var viewModel: MobileDeviceSearchViewModel

    /// Live state for the Advanced Search sheet. Created on demand so each open
    /// starts from the user's current field selections without retaining stale state.
    @State private var advancedSearchViewModel: AdvancedSearchViewModel?

    /// Whether the results list is in multi-select (share) mode.
    @State private var isSelecting = false
    /// IDs of records currently selected for sharing.
    @State private var selectedIDs: Set<String> = []
    /// Drives the `.fileExporter` Save panel (both platforms).
    @State private var isExporting = false

    /// Creates the search view with the given view model.
    ///
    /// The view model is wrapped in a `StateObject` to ensure it survives SwiftUI
    /// view re-creation while remaining owned by this view's lifecycle.
    ///
    /// - Parameter viewModel: The pre-configured view model instance.
    init(viewModel: MobileDeviceSearchViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    // "Would you like to play a game?"

    var body: some View {
        List {
            // MARK: - Search Input Section
            Section("Search") {
                HStack(spacing: 8) {
                    TextField("Serial number or username", text: $viewModel.query.strippingControlCharacters())
                        .dashboardNoAutoCorrectionTextInput()

                    // Barcode/QR scanner button for quick serial number entry
                    ScanIntoTextFieldButton(text: $viewModel.query.strippingControlCharacters())
                }

                // Profile picker lets the user switch between saved field configurations
                Picker("Search Profile", selection: $viewModel.selectedProfileID) {
                    Text("None").tag(nil as UUID?)
                    ForEach(viewModel.profiles) { profile in
                        Text(profile.name).tag(profile.id as UUID?)
                    }
                }
                .pickerStyle(.menu)

                HStack {
                    // Opens the field catalog sheet for fine-grained field selection
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

                    // Triggers the async search against the Jamf Pro API
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
                    Text("No results yet. Run a search to view devices.")
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
                        // Share the selected records' Markdown as plain text so the share
                        // sheet's Copy behaves as normal text copy/paste. Saving the `.md`
                        // file is handled by the Save button.
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
            defaultFilename: "Devices"
        ) { _ in isExporting = false }
        .navigationDestination(for: MobileDeviceRecordRoute.self) { route in
            MobileDeviceDetailView(viewModel: viewModel, recordID: route.id)
        }
        .task {
            // Load saved profiles, smart filters, and tenant extension
            // attributes on first appearance. EAs feed the Advanced Search
            // field picker; failure to load is logged but doesn't block the
            // UI — Advanced Search still works against built-in fields.
            await viewModel.loadProfiles()
            await viewModel.loadSmartFilters()
            await viewModel.loadExtensionAttributes()
        }
        .onChange(of: viewModel.selectedProfileID) { _, _ in
            // Sync selected field keys whenever the user picks a different profile
            viewModel.applySelectedProfileFields()
        }
        .sheet(isPresented: $viewModel.isFieldCatalogPresented) {
            FieldCatalogView(
                selectedFieldKeys: $viewModel.selectedFieldKeys,
                onSaveProfileRequested: {
                    viewModel.isFieldCatalogPresented = false

                    // Brief delay allows the sheet dismissal animation to complete
                    // before presenting the save-profile alert
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
                AdvancedSearchView(
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
    private var selectedRecords: [MobileDeviceRecord] {
        viewModel.searchResults.filter { selectedIDs.contains($0.id) }
    }

    /// Whether every visible result is selected.
    private var allSelected: Bool {
        viewModel.searchResults.isEmpty == false && selectedIDs.count == viewModel.searchResults.count
    }

    /// A results row: a selectable button in selection mode, otherwise the navigating link.
    @ViewBuilder
    private func resultRow(for record: MobileDeviceRecord) -> some View {
        if isSelecting {
            Button {
                toggleSelection(record.id)
            } label: {
                HStack(spacing: 12) {
                    SelectionCircle(isSelected: selectedIDs.contains(record.id))
                    MobileDeviceResultRow(record: record, fields: viewModel.resultFields)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            NavigationLink(value: MobileDeviceRecordRoute(id: record.id)) {
                MobileDeviceResultRow(record: record, fields: viewModel.resultFields)
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

//endofline
