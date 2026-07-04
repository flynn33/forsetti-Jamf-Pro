import SwiftUI

// "End of Line"

/// The primary view for the Prestage Director module.
///
/// Displays a list of prestage enrollment profiles in a picker, the devices assigned to the
/// selected prestage, and an action bar for selecting, moving, or removing devices. Supports
/// a serial number search that can either filter the current prestage or search globally
/// across all prestages when a full serial is entered.
struct PrestageDirectorView: View {
    /// The view model that owns all published state and business logic for this screen.
    @StateObject private var viewModel: PrestageDirectorViewModel

    /// Creates the view with an already-configured view model.
    ///
    /// Uses `StateObject(wrappedValue:)` to hand ownership of the view model to SwiftUI
    /// so it survives view re-creation during body evaluations.
    ///
    /// - Parameter viewModel: The fully initialized `PrestageDirectorViewModel`.
    init(viewModel: PrestageDirectorViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    /// A two-way binding for the currently selected prestage ID.
    ///
    /// On write, it updates the view model's selection and kicks off an async task to
    /// reload the device list for the newly selected prestage.
    private var selectedPrestageBinding: Binding<String?> {
        Binding(
            get: { viewModel.selectedPrestageID },
            set: { newValue in
                viewModel.selectedPrestageID = newValue
                Task {
                    await viewModel.loadDevicesForSelectedPrestage()
                }
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DashboardTheme.Spacing.lg) {
                prestageHero
                prestagePickerPanel

                if viewModel.errorMessage != nil || viewModel.statusMessage != nil || viewModel.operationProgress != nil {
                    prestageStatusPanel
                }

                assignedDevicesPanel
            }
            .padding(DashboardTheme.Spacing.xl)
            .padding(.bottom, 96)
        }
        .dashboardAppBackground()
        .toolbar {
            ToolbarItem(placement: .dashboardTopBarTrailing) {
                // Share the selected in-view devices (of the current prestage) as plain
                // Markdown text, so the share sheet's Copy pastes normally.
                if selectedDevices.isEmpty == false {
                    ShareLink(item: RecordMarkdown.document(for: selectedDevices)) {
                        Label("Share \(selectedDevices.count)", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Button { } label: { Label("Share", systemImage: "square.and.arrow.up") }
                        .disabled(true)
                }
            }
        }
        .searchable(text: $viewModel.deviceSerialSearchText.strippingControlCharacters(), prompt: "Find serial number")
        .task {
            // Load prestages and their devices on first appearance
            await viewModel.loadInitialState()
            viewModel.handleDeviceSearchTextChanged()
        }
        .onChange(of: viewModel.deviceSerialSearchText) { _, _ in
            // Trigger local filtering or global search based on the new query
            viewModel.handleDeviceSearchTextChanged()
        }
        .safeAreaInset(edge: .bottom) {
            actionBar
        }
        .sheet(isPresented: $viewModel.isMoveDestinationPresented) {
            PrestageMoveDestinationView(
                prestages: viewModel.moveDestinationPrestages,
                isApplyingChanges: viewModel.isApplyingChanges,
                onConfirm: { selectedPrestage in
                    Task {
                        await viewModel.moveSelection(to: selectedPrestage)
                    }
                }
            )
            #if os(macOS)
            .frame(minWidth: 720, idealWidth: 820, minHeight: 600, idealHeight: 720)
            #endif
        }
    }

    private var prestageHero: some View {
        VStack(alignment: .leading, spacing: DashboardTheme.Spacing.lg) {
            HStack(alignment: .top, spacing: DashboardTheme.Spacing.lg) {
                Image(systemName: "rectangle.stack.badge.person.crop")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(DashboardColors.accentCyan)
                    .frame(width: 54, height: 54)
                    .background(RoundedRectangle(cornerRadius: DashboardTheme.Radius.medium, style: .continuous).fill(DashboardColors.accentCyan.opacity(0.14)))
                    .overlay(RoundedRectangle(cornerRadius: DashboardTheme.Radius.medium, style: .continuous).stroke(DashboardColors.accentCyan.opacity(0.42), lineWidth: 1))

                VStack(alignment: .leading, spacing: DashboardTheme.Spacing.xs) {
                    Text("PreStage Director")
                        .font(DashboardTheme.Typography.screenTitle)
                        .foregroundStyle(DashboardColors.textPrimary)
                    Text(selectedPrestage?.name ?? "Select a pre-stage enrollment profile")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DashboardColors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)
                ForsettiStatusPill(status: prestageOperationalStatus)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: DashboardTheme.Spacing.md)], spacing: DashboardTheme.Spacing.md) {
                ForsettiMetricCard(
                    title: "Profiles",
                    value: "\(viewModel.prestages.count)",
                    subtitle: viewModel.isLoadingPrestages ? "Loading profiles" : "Loaded from Jamf",
                    systemImage: "rectangle.stack",
                    status: viewModel.isLoadingPrestages ? .querying : .ready
                )

                ForsettiMetricCard(
                    title: "Devices",
                    value: "\(viewModel.filteredScopedDevices.count)",
                    subtitle: viewModel.isGlobalSearchActive ? "Cross-profile matches" : "Visible in scope",
                    systemImage: "ipad.and.iphone",
                    status: viewModel.isSearchingAcrossPrestages ? .querying : .healthy
                )

                ForsettiMetricCard(
                    title: "Selected",
                    value: "\(viewModel.selectedCount)",
                    subtitle: viewModel.selectedCount == 0 ? "No pending scope changes" : "Ready for move or remove",
                    systemImage: "checklist.checked",
                    status: viewModel.selectedCount == 0 ? .ready : .active
                )

                ForsettiMetricCard(
                    title: "Version",
                    value: selectedPrestageVersionText,
                    subtitle: "Scope mutation token",
                    systemImage: "lock.shield",
                    status: selectedPrestage?.versionLock == nil ? .warning : .trusted
                )
            }
        }
    }

    private var prestagePickerPanel: some View {
        VStack(alignment: .leading, spacing: DashboardTheme.Spacing.md) {
            ForsettiPanelHeader(
                title: "Pre-Stage Enrollment Profiles",
                subtitle: "Choose the source profile before selecting assigned devices",
                systemImage: "rectangle.stack"
            )

            if viewModel.isLoadingPrestages {
                HStack(spacing: DashboardTheme.Spacing.sm) {
                    ProgressView()
                    Text("Loading pre-stages...")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(DashboardColors.textSecondary)
                }
            }

            if viewModel.prestages.isEmpty {
                Text("No pre-stages loaded yet.")
                    .font(.footnote)
                    .foregroundStyle(DashboardColors.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            } else {
                Picker("Current Pre-Stage", selection: selectedPrestageBinding) {
                    ForEach(viewModel.prestages) { prestage in
                        Text(prestage.name).tag(prestage.id as String?)
                    }
                }
                .pickerStyle(.menu)
                .disabled(viewModel.isApplyingChanges)
            }

            HStack(spacing: DashboardTheme.Spacing.sm) {
                ForsettiFilterChip(title: "Destinations", value: "\(viewModel.moveDestinationPrestages.count)", systemImage: "arrow.triangle.branch")
                ForsettiFilterChip(title: "Visible", value: "\(viewModel.filteredScopedDevices.count)", systemImage: "rectangle.grid.1x2")
                Spacer(minLength: 0)
            }

            Button {
                Task {
                    await viewModel.refreshPrestages()
                }
            } label: {
                Label("Refresh Pre-Stages", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.dashboardSecondary)
            .frame(minHeight: 46)
            .disabled(viewModel.isLoadingPrestages || viewModel.isApplyingChanges)
        }
        .forsettiGlassPanel(padding: .standard, isActive: viewModel.isLoadingPrestages, statusTint: DashboardColors.accentCyan)
    }

    private var prestageStatusPanel: some View {
        VStack(alignment: .leading, spacing: DashboardTheme.Spacing.md) {
            if let errorMessage = viewModel.errorMessage {
                SupportTechnicianInlineBanner(
                    text: errorMessage,
                    status: .failed,
                    systemImage: "exclamationmark.triangle.fill"
                )
            }

            if let statusMessage = viewModel.statusMessage {
                SupportTechnicianInlineBanner(
                    text: statusMessage,
                    status: .ready,
                    systemImage: "info.circle"
                )
            }

            if let progress = viewModel.operationProgress {
                VStack(alignment: .leading, spacing: DashboardTheme.Spacing.sm) {
                    HStack(spacing: DashboardTheme.Spacing.sm) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(DashboardColors.accentCyan)
                        Text(progress.title)
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(DashboardColors.textPrimary)
                    }

                    ProgressView(value: progress.fractionCompleted, total: 1.0)
                        .tint(DashboardColors.accentCyan)

                    Text(progress.detail)
                        .font(.caption)
                        .foregroundStyle(DashboardColors.textSecondary)
                }
                .forsettiGlassPanel(padding: .dense, isActive: true, statusTint: DashboardColors.accentCyan)
            }
        }
    }

    private var assignedDevicesPanel: some View {
        VStack(alignment: .leading, spacing: DashboardTheme.Spacing.md) {
            ForsettiPanelHeader(
                title: "Assigned Devices",
                subtitle: assignedDevicesSubtitle,
                systemImage: "ipad.and.iphone"
            )

            if viewModel.isLoadingScopedDevices {
                HStack(spacing: DashboardTheme.Spacing.sm) {
                    ProgressView()
                    Text("Loading assigned devices...")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(DashboardColors.textSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else if viewModel.isSearchingAcrossPrestages {
                HStack(spacing: DashboardTheme.Spacing.sm) {
                    ProgressView()
                    Text("Searching all pre-stage profiles...")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(DashboardColors.textSecondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
            } else if viewModel.scopedDevices.isEmpty {
                emptyDeviceMessage("No devices assigned to this pre-stage.")
            } else if viewModel.filteredScopedDevices.isEmpty {
                emptyDeviceMessage("No devices match that serial number across any pre-stage profile.")
            } else {
                LazyVStack(spacing: DashboardTheme.Spacing.sm) {
                    ForEach(viewModel.filteredScopedDevices) { device in
                        Button {
                            viewModel.toggleSelection(for: device)
                        } label: {
                            PrestageDeviceRow(
                                device: device,
                                isSelected: viewModel.selectedDeviceKeys.contains(device.selectionKey),
                                currentPrestageID: viewModel.selectedPrestageID
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isApplyingChanges)
                    }
                }
            }
        }
        .forsettiGlassPanel(padding: .standard, isActive: viewModel.selectedCount > 0, statusTint: DashboardColors.accentCyan)
    }

    private func emptyDeviceMessage(_ message: String) -> some View {
        Text(message)
            .font(.footnote)
            .foregroundStyle(DashboardColors.textTertiary)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
    }

    private var selectedPrestage: PrestageSummary? {
        guard let selectedPrestageID = viewModel.selectedPrestageID else {
            return nil
        }
        return viewModel.prestages.first { $0.id == selectedPrestageID }
    }

    private var selectedPrestageVersionText: String {
        guard let versionLock = selectedPrestage?.versionLock else {
            return "Missing"
        }
        return "\(versionLock)"
    }

    private var assignedDevicesSubtitle: String {
        if viewModel.isGlobalSearchActive {
            return "Showing cross-profile serial matches"
        }
        if let selectedPrestage {
            return selectedPrestage.name
        }
        return "Select a profile to inspect assignments"
    }

    private var prestageOperationalStatus: ForsettiSemanticStatus {
        if viewModel.errorMessage != nil {
            return .failed
        }
        if viewModel.isApplyingChanges {
            return .sending
        }
        if viewModel.isLoadingPrestages || viewModel.isLoadingScopedDevices || viewModel.isSearchingAcrossPrestages {
            return .querying
        }
        if viewModel.selectedCount > 0 {
            return .active
        }
        return .ready
    }

    /// The in-view devices the technician has selected (within the current prestage),
    /// gathered for sharing. Intersects the selection keys with the filtered list so it
    /// only ever includes devices currently on screen.
    private var selectedDevices: [PrestageAssignedDevice] {
        viewModel.filteredScopedDevices.filter { viewModel.selectedDeviceKeys.contains($0.selectionKey) }
    }

    /// The bottom action bar containing selection controls and move/remove buttons.
    ///
    /// Provides a "Select All / Clear" toggle, a "Remove" button (danger-styled) to
    /// unassign devices from the current prestage, and a "Move" button to reassign
    /// them to a different prestage.
    private var actionBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: DashboardTheme.Spacing.sm) {
                ForsettiStatusPill(
                    status: viewModel.selectedCount == 0 ? .ready : .active,
                    text: "\(viewModel.selectedCount) selected"
                )

                if viewModel.isApplyingChanges {
                    ForsettiStatusPill(status: .sending, text: "Applying")
                }
            }

            HStack(spacing: 10) {
                Button {
                    viewModel.toggleSelectAll()
                } label: {
                    Label(viewModel.allDevicesSelected ? "Clear" : "Select All", systemImage: viewModel.allDevicesSelected ? "xmark.circle" : "checkmark.circle")
                }
                .buttonStyle(.dashboardSecondary)
                .disabled(
                    viewModel.filteredScopedDevices.isEmpty ||
                        viewModel.isLoadingScopedDevices ||
                        viewModel.isSearchingAcrossPrestages ||
                        viewModel.isApplyingChanges
                )

                Button {
                    Task {
                        await viewModel.confirmRemoval()
                    }
                } label: {
                    Label("Remove", systemImage: "minus.circle")
                }
                .buttonStyle(.dashboardDanger)
                .disabled(viewModel.canRemoveSelection == false)

                Button {
                    viewModel.presentMoveDestinationPicker()
                } label: {
                    Label("Move", systemImage: "arrow.right.circle")
                }
                .buttonStyle(.dashboardPrimary)
                .disabled(viewModel.canMoveSelection == false)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .dashboardBottomBarSurface()
    }
}

/// A single row in the assigned devices list, showing device name, serial number,
/// model, and UDID along with a selection checkmark indicator. When the device
/// belongs to a different pre-stage than the one currently being viewed (i.e. a
/// cross-pre-stage search result), the row also displays the assigned pre-stage
/// profile name so the user can see where the device lives.
private struct PrestageDeviceRow: View {
    /// The device to display in this row.
    let device: PrestageAssignedDevice

    /// Whether this device is currently selected for a move or remove operation.
    let isSelected: Bool

    /// The ID of the pre-stage currently selected in the picker. Used to decide
    /// whether to surface the device's assigned pre-stage name as a cross-scope
    /// badge (shown only when the device lives in a different pre-stage).
    let currentPrestageID: String?

    /// Whether this row represents a device from a pre-stage other than the
    /// currently-viewed one. The pre-stage name badge renders only in this case.
    private var isCrossScope: Bool {
        guard let devicePrestageID = device.prestageID else {
            return false
        }
        return devicePrestageID != currentPrestageID
    }

    var body: some View {
        HStack(alignment: .top, spacing: DashboardTheme.Spacing.md) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? DashboardColors.greenPrimary : DashboardColors.textTertiary)
                .font(DashboardSearchResultTypography.title3())
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: DashboardTheme.Spacing.sm) {
                    Text(device.deviceName)
                        .font(DashboardSearchResultTypography.headline())
                        .foregroundStyle(DashboardColors.textPrimary)
                        .lineLimit(1)

                    if isCrossScope, let prestageName = device.prestageName {
                        ForsettiStatusPill(status: .workflow, text: prestageName)
                    }
                }

                if isCrossScope, let prestageName = device.prestageName {
                    Text("Pre-Stage: \(prestageName)")
                        .font(DashboardSearchResultTypography.subheadline())
                        .foregroundStyle(DashboardColors.accentCyan)
                }

                if let serial = device.normalizedSerialNumber {
                    Text("Serial: \(serial)")
                        .font(DashboardSearchResultTypography.subheadline())
                        .foregroundStyle(DashboardColors.textSecondary)
                } else {
                    Text("Serial unavailable")
                        .font(DashboardSearchResultTypography.subheadline())
                        .foregroundStyle(DashboardColors.danger)
                }

                if let model = device.model {
                    Text("Model: \(model)")
                        .font(DashboardSearchResultTypography.caption())
                        .foregroundStyle(DashboardColors.textTertiary)
                }

                if let udid = device.udid {
                    Text("UDID: \(udid)")
                        .font(DashboardSearchResultTypography.caption2())
                        .foregroundStyle(DashboardColors.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(DashboardTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DashboardTheme.Radius.card, style: .continuous)
                .fill(isSelected ? DashboardColors.tableRowSelected.opacity(0.92) : DashboardColors.tableRow.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: DashboardTheme.Radius.card, style: .continuous)
                .stroke(isSelected ? DashboardColors.accentCyan.opacity(0.62) : DashboardColors.separator.opacity(0.28), lineWidth: 1)
        )
        .contentShape(Rectangle())
    }
}

/// A modal sheet that lets the user pick a destination prestage when moving devices.
///
/// Presents a searchable list of all prestages except the currently selected one.
/// The user selects a destination and taps "Confirm Move" to trigger the two-step
/// remove-then-add scope mutation handled by the view model.
private struct PrestageMoveDestinationView: View {
    @Environment(\.dismiss) private var dismiss

    /// All prestages available as move destinations (excludes the current source).
    let prestages: [PrestageSummary]

    /// Whether a move operation is currently in flight, used to disable controls.
    let isApplyingChanges: Bool

    /// Callback invoked with the chosen destination prestage when the user confirms.
    let onConfirm: (PrestageSummary) -> Void

    /// Local search text for filtering the destination prestage list.
    @State private var searchText = ""

    /// The ID of the destination prestage the user has selected, if any.
    @State private var selectedPrestageID: String?

    /// The subset of prestages whose names contain the current search text.
    private var filteredPrestages: [PrestageSummary] {
        guard searchText.isEmpty == false else {
            return prestages
        }

        let loweredSearch = searchText.localizedLowercase
        return prestages.filter { $0.name.localizedLowercase.contains(loweredSearch) }
    }

    /// The fully resolved `PrestageSummary` for the selected destination, or `nil`.
    private var selectedPrestage: PrestageSummary? {
        guard let selectedPrestageID else {
            return nil
        }

        return prestages.first(where: { $0.id == selectedPrestageID })
    }

    var body: some View {
        NavigationStack {
            // VStack(spacing: 0) keeps the destination List as the scroll
            // region and pins `moveConfirmationBar` beneath it on both
            // platforms. `.safeAreaInset(edge: .bottom)` placed on a List
            // inside a NavigationStack inside a sheet is unreliable on
            // macOS — the inset can collapse and the bar ends up rendered
            // inside the scroll content.
            VStack(spacing: 0) {
                List {
                    if filteredPrestages.isEmpty {
                        Text("No destination pre-stages match your search.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filteredPrestages) { prestage in
                            Button {
                                selectedPrestageID = prestage.id
                            } label: {
                                HStack(spacing: 12) {
                                    // Radio-style selection indicator
                                    Image(systemName: selectedPrestageID == prestage.id ? "largecircle.fill.circle" : "circle")
                                        .foregroundStyle(
                                            selectedPrestageID == prestage.id
                                                ? DashboardColors.greenPrimary
                                                : .secondary
                                        )
                                        .font(.title3)

                                    Text(prestage.name)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .dashboardInsetGroupedListStyle()
                .disabled(isApplyingChanges)
                .searchable(text: $searchText, prompt: "Find pre-stage")
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                moveConfirmationBar
            }
            .navigationTitle("Move To Pre-Stage")
            .dashboardInlineNavigationTitle()
            .toolbar {
                // Apple HIG: Cancel uses the semantic .cancellationAction
                // placement — leading, Escape-activated on macOS.
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    /// Bottom bar showing the selected destination name and a confirm button.
    private var moveConfirmationBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let selectedPrestage {
                Text("Destination: \(selectedPrestage.name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Select a destination pre-stage.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Confirm Move") {
                guard let selectedPrestage else {
                    return
                }

                onConfirm(selectedPrestage)
                dismiss()
            }
            .buttonStyle(.dashboardPrimary)
            .disabled(selectedPrestage == nil || isApplyingChanges)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .dashboardBottomBarSurface()
    }
}

//endofline
