import SwiftUI
import UniformTypeIdentifiers

struct ComputerSearchView: View {
    @StateObject private var viewModel: ComputerSearchViewModel
    @State private var advancedSearchViewModel: ComputerAdvancedSearchViewModel?
    @State private var isSelecting = false
    @State private var selectedIDs: Set<String> = []
    @State private var isExporting = false
    @State private var selectedRecordID: String?

    init(viewModel: ComputerSearchViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        GeometryReader { proxy in
            let showsInspector = proxy.size.width >= DashboardTheme.Layout.inspectorBreakpoint

            HStack(alignment: .top, spacing: DashboardTheme.Spacing.lg) {
                ScrollView {
                    VStack(alignment: .leading, spacing: DashboardTheme.Spacing.xl) {
                        headerPanel
                        searchToolbar
                        stateBanners
                        metricStrip
                        resultsPanel
                        profileAndFilterPanels

                        if showsInspector == false {
                            selectedComputerInspector
                        }
                    }
                    .padding(DashboardTheme.Spacing.screenPaddingRegular)
                }

                if showsInspector {
                    selectedComputerInspector
                        .frame(width: DashboardTheme.Layout.rightInspectorWidth)
                        .padding(.vertical, DashboardTheme.Spacing.screenPaddingRegular)
                        .padding(.trailing, DashboardTheme.Spacing.screenPaddingRegular)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .dashboardAppBackground()
        .navigationTitle("Computer Search")
        .toolbar { selectionToolbar }
        .onChange(of: viewModel.searchResults.map(\.id)) { _, ids in
            if isSelecting { exitSelection() }
            if let selectedRecordID, ids.contains(selectedRecordID) {
                return
            }
            selectedRecordID = ids.first
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

    @ToolbarContentBuilder
    private var selectionToolbar: some ToolbarContent {
        if isSelecting {
            ToolbarItem(placement: .dashboardTopBarLeading) {
                Button("Cancel") { exitSelection() }
            }
            ToolbarItemGroup(placement: .dashboardTopBarTrailing) {
                Button(allSelected ? "Deselect All" : "Select All") { toggleSelectAll() }
                    .disabled(viewModel.searchResults.isEmpty)

                if selectedIDs.isEmpty == false {
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

    private var headerPanel: some View {
        HStack(alignment: .center, spacing: DashboardTheme.Spacing.lg) {
            VStack(alignment: .leading, spacing: DashboardTheme.Spacing.sm) {
                HStack(spacing: DashboardTheme.Spacing.sm) {
                    Text("Computer Search")
                        .font(DashboardTheme.Typography.screenTitle)
                        .foregroundStyle(DashboardColors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    ForsettiStatusPill(status: viewModel.isSearching ? .querying : .ready)
                }

                Text("Search Jamf Pro computer inventory, apply saved profiles, inspect selected Macs, and export result sets.")
                    .font(.subheadline)
                    .foregroundStyle(DashboardColors.textSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: DashboardTheme.Spacing.lg)

            Button {
                viewModel.isFieldCatalogPresented = true
            } label: {
                Label("Columns", systemImage: "tablecells")
            }
            .buttonStyle(.dashboardSecondary)
        }
        .forsettiGlassPanel(padding: .roomy, isActive: true)
    }

    private var searchToolbar: some View {
        VStack(alignment: .leading, spacing: DashboardTheme.Spacing.md) {
            HStack(spacing: DashboardTheme.Spacing.md) {
                Picker("Search Profile", selection: $viewModel.selectedProfileID) {
                    Text("None").tag(nil as UUID?)
                    ForEach(viewModel.profiles) { profile in
                        Text(profile.name).tag(profile.id as UUID?)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 220)

                ForsettiSearchInput(
                    placeholder: "Computer name, serial, username, email",
                    text: $viewModel.query.strippingControlCharacters()
                )

                ScanIntoTextFieldButton(text: $viewModel.query.strippingControlCharacters())

                Button {
                    advancedSearchViewModel = viewModel.makeAdvancedSearchViewModel()
                    viewModel.isAdvancedSearchPresented = true
                } label: {
                    Label("Advanced", systemImage: "line.3.horizontal.decrease.circle")
                }
                .buttonStyle(.dashboardSecondary)

                Button {
                    Task {
                        await viewModel.executeSearch()
                    }
                } label: {
                    Label(viewModel.isSearching ? "Searching" : "Run Search", systemImage: "magnifyingglass")
                }
                .buttonStyle(.dashboardPrimary)
                .disabled(viewModel.isSearching)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DashboardTheme.Spacing.sm) {
                    ForsettiFilterChip(title: "Profile", value: activeProfileName, systemImage: "bookmark")
                    ForsettiFilterChip(title: "Columns", value: "\(viewModel.resultFields.count)", systemImage: "tablecells")
                    ForsettiFilterChip(title: "Smart Filters", value: "\(viewModel.smartFilters.count)", systemImage: "line.3.horizontal.decrease")
                    ForsettiFilterChip(title: "Mode", value: isSelecting ? "Selecting" : "Inspect", systemImage: "cursorarrow.rays")
                }
            }
        }
        .forsettiGlassPanel(padding: .standard)
    }

    @ViewBuilder
    private var stateBanners: some View {
        if let errorMessage = viewModel.errorMessage {
            banner(title: "Search Error", message: errorMessage, status: .failed)
        }

        if let notice = viewModel.decodingNoticeMessage {
            banner(title: "Response Notice", message: notice, status: .warning)
        }
    }

    private var metricStrip: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 176), spacing: DashboardTheme.Spacing.lg)],
            alignment: .leading,
            spacing: DashboardTheme.Spacing.lg
        ) {
            ForsettiMetricCard(
                title: "Total Results",
                value: "\(viewModel.searchResults.count)",
                subtitle: viewModel.isSearching ? "query running" : "current result set",
                systemImage: "desktopcomputer",
                status: viewModel.isSearching ? .querying : .ready
            )
            ForsettiMetricCard(
                title: "Reachable",
                value: "\(reachableComputerCount)",
                subtitle: "reported IP address",
                systemImage: "antenna.radiowaves.left.and.right",
                status: reachableComputerCount > 0 ? .reachable : .stale
            )
            ForsettiMetricCard(
                title: "PreStage",
                value: "\(prestageComputerCount)",
                subtitle: "enrollment data",
                systemImage: "checkmark.seal.fill",
                status: prestageComputerCount > 0 ? .enrolled : .pending
            )
            ForsettiMetricCard(
                title: "Selected",
                value: "\(selectedIDs.count)",
                subtitle: isSelecting ? "sharing set" : "inspector focus",
                systemImage: "checkmark.circle",
                status: selectedIDs.isEmpty ? .ready : .active
            )
        }
    }

    private var resultsPanel: some View {
        VStack(alignment: .leading, spacing: DashboardTheme.Spacing.lg) {
            HStack {
                Label("Results", systemImage: "list.bullet.rectangle")
                    .font(DashboardTheme.Typography.sectionTitle)
                    .foregroundStyle(DashboardColors.textPrimary)
                Spacer()
                Text("\(viewModel.searchResults.count) computers")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(DashboardColors.textTertiary)
            }

            ForsettiDataTable(
                rows: viewModel.searchResults,
                selectedID: selectedRecordID,
                onSelect: { record in
                    if isSelecting {
                        toggleSelection(record.id)
                    } else {
                        selectedRecordID = record.id
                    }
                },
                header: {
                    computerTableHeader
                },
                rowContent: { record in
                    computerTableRow(record)
                },
                emptyContent: {
                    emptyResultsContent
                }
            )
        }
        .forsettiGlassPanel(padding: .standard)
    }

    private var computerTableHeader: some View {
        HStack(spacing: DashboardTheme.Spacing.md) {
            if isSelecting {
                Text("").frame(width: 24)
            }
            Text("Computer").frame(maxWidth: .infinity, alignment: .leading)
            Text("Serial").frame(width: 130, alignment: .leading)
            Text("User").frame(width: 130, alignment: .leading)
            Text("macOS").frame(width: 82, alignment: .leading)
            Text("PreStage").frame(width: 128, alignment: .leading)
            Text("").frame(width: 34)
        }
    }

    private func computerTableRow(_ record: ComputerRecord) -> some View {
        HStack(spacing: DashboardTheme.Spacing.md) {
            if isSelecting {
                SelectionCircle(isSelected: selectedIDs.contains(record.id))
                    .frame(width: 24)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName(for: record))
                    .font(DashboardTheme.Typography.tableBody.weight(.semibold))
                    .foregroundStyle(DashboardColors.textPrimary)
                    .lineLimit(1)
                Text(record.model ?? record.modelIdentifier ?? "Model unavailable")
                    .font(.caption2)
                    .foregroundStyle(DashboardColors.textTertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(record.serialNumber)
                .font(.caption.monospacedDigit())
                .foregroundStyle(DashboardColors.textSecondary)
                .frame(width: 130, alignment: .leading)
                .lineLimit(1)

            Text(record.username ?? record.email ?? "Unassigned")
                .font(.caption)
                .foregroundStyle(DashboardColors.textSecondary)
                .frame(width: 130, alignment: .leading)
                .lineLimit(1)

            Text(record.osVersion ?? "--")
                .font(.caption.monospacedDigit())
                .foregroundStyle(DashboardColors.textSecondary)
                .frame(width: 82, alignment: .leading)
                .lineLimit(1)

            ForsettiStatusPill(
                status: record.prestageDisplayValue == nil ? .pending : .enrolled,
                text: record.prestageDisplayValue == nil ? "Unknown" : "Enrolled"
            )
            .frame(width: 128, alignment: .leading)

            NavigationLink(value: ComputerRecordRoute(id: record.id)) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(DashboardColors.accentCyan)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("Open computer detail")
            .accessibilityLabel("Open detail for \(displayName(for: record))")
        }
        .accessibilityElement(children: .combine)
    }

    private var emptyResultsContent: some View {
        VStack(spacing: DashboardTheme.Spacing.sm) {
            Image(systemName: viewModel.isSearching ? "magnifyingglass" : "desktopcomputer")
                .font(.title2)
                .foregroundStyle(DashboardColors.accentCyan)
            Text(viewModel.isSearching ? "Searching Jamf Pro..." : "No results yet")
                .font(.headline)
                .foregroundStyle(DashboardColors.textPrimary)
            Text("Run a search to populate the computer table.")
                .font(.caption)
                .foregroundStyle(DashboardColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var profileAndFilterPanels: some View {
        HStack(alignment: .top, spacing: DashboardTheme.Spacing.lg) {
            savedProfilesPanel
            smartFiltersPanel
        }
    }

    private var savedProfilesPanel: some View {
        VStack(alignment: .leading, spacing: DashboardTheme.Spacing.md) {
            Label("Search Profiles", systemImage: "bookmark.fill")
                .font(DashboardTheme.Typography.sectionTitle)
                .foregroundStyle(DashboardColors.textPrimary)

            if viewModel.profiles.isEmpty {
                Text("No saved profiles.")
                    .font(.caption)
                    .foregroundStyle(DashboardColors.textSecondary)
            } else {
                ForEach(viewModel.profiles) { profile in
                    HStack(spacing: DashboardTheme.Spacing.md) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.name)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(DashboardColors.textPrimary)
                                .lineLimit(1)
                            Text("\(profile.fieldKeys.count) fields")
                                .font(.caption2)
                                .foregroundStyle(DashboardColors.textTertiary)
                        }

                        Spacer(minLength: 0)

                        if viewModel.selectedProfileID == profile.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(DashboardColors.success)
                        }

                        Button(role: .destructive) {
                            deleteProfile(profile)
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(DashboardColors.danger)
                        .help("Delete profile")
                    }
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.selectedProfileID = profile.id
                        viewModel.applySelectedProfileFields()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .forsettiGlassPanel(padding: .standard)
    }

    private var smartFiltersPanel: some View {
        VStack(alignment: .leading, spacing: DashboardTheme.Spacing.md) {
            Label("Smart Filters", systemImage: "line.3.horizontal.decrease.circle.fill")
                .font(DashboardTheme.Typography.sectionTitle)
                .foregroundStyle(DashboardColors.textPrimary)

            if viewModel.smartFilters.isEmpty {
                Text("No smart filters saved.")
                    .font(.caption)
                    .foregroundStyle(DashboardColors.textSecondary)
            } else {
                ForEach(viewModel.smartFilters) { filter in
                    smartFilterRow(filter)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .forsettiGlassPanel(padding: .standard)
    }

    private func smartFilterRow(_ filter: SmartFilter) -> some View {
        HStack(spacing: DashboardTheme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(filter.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DashboardColors.textPrimary)
                    .lineLimit(1)
                Text("\(filter.query.groups.reduce(0) { $0 + $1.criteria.count }) criteria · \(filter.fieldKeys.count) columns")
                    .font(.caption2)
                    .foregroundStyle(DashboardColors.textTertiary)
            }

            Spacer(minLength: 0)

            Button {
                advancedSearchViewModel = viewModel.loadSmartFilterIntoAdvancedSearch(filter)
                viewModel.isAdvancedSearchPresented = true
            } label: {
                Image(systemName: "arrow.up.forward.app")
            }
            .buttonStyle(.plain)
            .foregroundStyle(DashboardColors.accentCyan)
            .help("Open smart filter")

            Button(role: .destructive) {
                deleteSmartFilter(filter)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(DashboardColors.danger)
            .help("Delete smart filter")
        }
        .padding(.vertical, 5)
    }

    private var selectedComputerInspector: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DashboardTheme.Spacing.lg) {
                if let record = selectedRecord {
                    computerHero(record)
                    ForsettiInspectorSection(title: "Quick Actions", systemImage: "bolt.fill") {
                        NavigationLink(value: ComputerRecordRoute(id: record.id)) {
                            Label("Open Full Detail", systemImage: "arrow.up.forward.app")
                        }
                        .buttonStyle(.dashboardPrimary)

                        ForsettiQuickActionRow(
                            title: "Refresh Hardware",
                            subtitle: "Load expanded inventory where available",
                            systemImage: "arrow.clockwise",
                            tint: DashboardColors.accentCyan,
                            action: {
                                Task {
                                    try? await viewModel.refreshComputerHardware(id: record.id)
                                }
                            }
                        )
                    }

                    ForsettiInspectorSection(title: "Hardware", systemImage: "desktopcomputer") {
                        ForsettiKeyValueRow(key: "Model", value: record.model ?? record.modelIdentifier ?? "Unknown")
                        ForsettiKeyValueRow(key: "Serial", value: record.serialNumber)
                        ForsettiKeyValueRow(key: "macOS", value: record.osVersion ?? "Unknown")
                        ForsettiKeyValueRow(key: "IP Address", value: record.lastIpAddress ?? "Not reported")
                    }

                    ForsettiInspectorSection(title: "Assignment", systemImage: "person.crop.circle") {
                        ForsettiKeyValueRow(key: "User", value: record.username ?? "Unassigned")
                        ForsettiKeyValueRow(key: "Email", value: record.email ?? "Not reported")
                        ForsettiKeyValueRow(key: "Asset Tag", value: record.assetTag ?? "Not reported")
                        ForsettiKeyValueRow(key: "PreStage", value: record.prestageDisplayValue ?? "Unknown", status: record.prestageDisplayValue == nil ? .pending : .enrolled)
                    }
                } else {
                    ForsettiInspectorSection(title: "Selected Computer", systemImage: "cursorarrow.rays") {
                        Text("Select a computer row to inspect hardware, user, compliance, and PreStage context.")
                            .font(.caption)
                            .foregroundStyle(DashboardColors.textSecondary)
                    }
                }
            }
            .padding(.bottom, DashboardTheme.Spacing.xl)
        }
    }

    private func computerHero(_ record: ComputerRecord) -> some View {
        VStack(alignment: .leading, spacing: DashboardTheme.Spacing.md) {
            HStack(alignment: .top, spacing: DashboardTheme.Spacing.md) {
                Image(systemName: "desktopcomputer")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(DashboardColors.accentCyan)
                    .frame(width: 58, height: 58)
                    .background(RoundedRectangle(cornerRadius: DashboardTheme.Radius.card, style: .continuous).fill(DashboardColors.accentCyan.opacity(0.14)))
                    .overlay(RoundedRectangle(cornerRadius: DashboardTheme.Radius.card, style: .continuous).stroke(DashboardColors.accentCyan.opacity(0.38), lineWidth: 1))

                VStack(alignment: .leading, spacing: 4) {
                    Text(displayName(for: record))
                        .font(.headline.weight(.bold))
                        .foregroundStyle(DashboardColors.textPrimary)
                        .lineLimit(2)
                    Text(record.serialNumber)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(DashboardColors.textSecondary)
                    ForsettiStatusPill(status: record.lastIpAddress == nil ? .stale : .reachable)
                }
            }
        }
        .forsettiGlassPanel(padding: .standard, isActive: true)
    }

    private func banner(title: String, message: String, status: ForsettiSemanticStatus) -> some View {
        HStack(alignment: .top, spacing: DashboardTheme.Spacing.md) {
            Image(systemName: status.symbolName)
                .foregroundStyle(status.color)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(DashboardColors.textPrimary)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(DashboardColors.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .forsettiGlassPanel(padding: .dense, statusTint: status.color)
    }

    private var selectedRecords: [ComputerRecord] {
        viewModel.searchResults.filter { selectedIDs.contains($0.id) }
    }

    private var selectedRecord: ComputerRecord? {
        if let selectedRecordID,
           let record = viewModel.searchResults.first(where: { $0.id == selectedRecordID }) {
            return record
        }
        return viewModel.searchResults.first
    }

    private var allSelected: Bool {
        viewModel.searchResults.isEmpty == false && selectedIDs.count == viewModel.searchResults.count
    }

    private var activeProfileName: String {
        guard let selectedProfileID = viewModel.selectedProfileID,
              let profile = viewModel.profiles.first(where: { $0.id == selectedProfileID }) else {
            return "None"
        }
        return profile.name
    }

    private var reachableComputerCount: Int {
        viewModel.searchResults.filter { ($0.lastIpAddress ?? "").isEmpty == false }.count
    }

    private var prestageComputerCount: Int {
        viewModel.searchResults.filter { $0.prestageDisplayValue != nil }.count
    }

    private func displayName(for record: ComputerRecord) -> String {
        record.value(for: "general.name") ?? record.computerName
    }

    private func toggleSelection(_ id: String) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
    }

    private func toggleSelectAll() {
        if allSelected { selectedIDs.removeAll() }
        else { selectedIDs = Set(viewModel.searchResults.map(\.id)) }
    }

    private func exitSelection() {
        isSelecting = false
        selectedIDs.removeAll()
    }

    private func deleteProfile(_ profile: ComputerSearchProfile) {
        guard let index = viewModel.profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        viewModel.deleteProfiles(at: IndexSet(integer: index))
    }

    private func deleteSmartFilter(_ filter: SmartFilter) {
        guard let index = viewModel.smartFilters.firstIndex(where: { $0.id == filter.id }) else { return }
        viewModel.deleteSmartFilters(at: IndexSet(integer: index))
    }
}

//endofline
