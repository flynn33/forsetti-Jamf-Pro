import SwiftUI

/// Layout constants shared across Support Technician view components.
private enum SupportTechnicianLayout {
    /// Minimum height for control buttons to ensure comfortable tap targets.
    static let controlButtonHeight: CGFloat = 50
}


/// The primary view for the Support Technician module.
///
/// Uses a `NavigationSplitView` to present a sidebar with search controls and results
/// alongside a detail pane showing device diagnostics, category frames, and management
/// actions. Destructive actions require typing "confirm" in `SupportTypedConfirmationSheet`
/// before execution. The whole module shares a Metal-rendered backdrop via
/// `ForsettiMetalBackgroundView`.
struct SupportTechnicianView: View {
    /// The view model that owns all published state and business logic for this screen.
    @StateObject private var viewModel: SupportTechnicianViewModel

    /// The destructive action awaiting typed "confirm" approval. Driven by
    /// `action.confirmationStrength == .typed`, which covers every
    /// destructive command in the redesigned module.
    @State private var pendingTypedConfirmAction: SupportManagementAction?

    /// The technician's typed input for the destructive-action sheet.
    @State private var typedConfirmationText = ""

    /// Controls the sidebar/detail column visibility state.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    /// Drives the presentation of the Application Manager sheet from the
    /// detail pane.
    @State private var isApplicationManagerPresented = false

    /// Drives the SD+ Ticket unavailable-in-this-build alert from the sidebar.
    @State private var showSDPlusUnavailableAlert = false

    /// Creates the view with an already-configured view model.
    ///
    /// - Parameter viewModel: The fully initialized `SupportTechnicianViewModel`.
    init(viewModel: SupportTechnicianViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            // Wrap the detail in its own NavigationStack so push-style flows
            // (Application Manager, etc.) work consistently on macOS, iPadOS,
            // and iOS.
            NavigationStack {
                detailPane
            }
        }
        .background(
            // Module-wide Metal backdrop. Sits behind both columns so the
            // ticket entry, search, sidebar, and detail panes all share the
            // animated Metal identity.
            ForsettiMetalBackgroundView()
                .ignoresSafeArea()
        )
        .onChange(of: viewModel.selectedResultID) { _, _ in
            Task {
                await viewModel.loadSelectedDeviceDetail()
            }
        }
        .onChange(of: viewModel.searchScope) { _, _ in
            viewModel.resetForScopeChange()
        }
        // Single typed-confirm sheet covering every destructive action.
        // Required word comes from `action.requiredTypedPhrase` which
        // returns "confirm" (lowercase) per the redesign spec.
        .sheet(item: $pendingTypedConfirmAction) { action in
            SupportTypedConfirmationSheet(
                action: action,
                requiredPhrase: action.requiredTypedPhrase ?? "confirm",
                confirmationText: $typedConfirmationText,
                onCancel: {
                    pendingTypedConfirmAction = nil
                    typedConfirmationText = ""
                },
                onConfirm: {
                    pendingTypedConfirmAction = nil
                    typedConfirmationText = ""
                    Task {
                        await viewModel.performAction(action)
                    }
                }
            )
        }
        // Per-row password reset typed-confirm sheet (User Accounts
        // frame). Bound to `viewModel.passwordResetCandidate`, set by
        // `requestPasswordReset(for:)` from the per-row Reset Password
        // button. Uses the same `SupportTypedConfirmationSheet` widget
        // as destructive actions so the gate experience is consistent.
        // The synthetic action is `.rotateLAPSPassword` because the
        // per-row reset is semantically a LAPS rotate on a specific
        // non-default account; the existing typed-confirm sheet renders
        // its title and confirmation copy from the `SupportManagementAction`.
        .sheet(item: $viewModel.passwordResetCandidate) { user in
            SupportTypedConfirmationSheet(
                action: .rotateLAPSPassword,
                requiredPhrase: "confirm",
                confirmationText: $viewModel.passwordResetConfirmationText,
                accountName: user.username,
                onCancel: {
                    viewModel.cancelPasswordReset()
                },
                onConfirm: {
                    Task {
                        await viewModel.executePasswordReset()
                    }
                }
            )
        }
        .alert("SD+ Ticket integration", isPresented: $showSDPlusUnavailableAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("SD+ ticket creation is not available in this build. No ticket was created, and no SD+ integration call was made.")
        }
        // Verbose failure popup — fires when an MDM command 403s, 404s,
        // or otherwise fails. Shows the action that failed, the likely
        // privilege Jamf wants, a remediation suggestion, and the raw
        // response body for advanced debugging. Two buttons:
        //   - OK (default): acknowledges and dismisses
        //   - Back (cancel role): explicit "go back to the device view"
        //     affordance so technicians don't get stuck staring at an alert
        //     wondering whether OK retries or dismisses.
        .alert(item: $viewModel.actionFailurePopup) { failure in
            Alert(
                title: Text("\(failure.actionTitle) failed"),
                message: Text(failure.alertBody),
                primaryButton: .default(Text("OK")) {
                    viewModel.actionFailurePopup = nil
                },
                secondaryButton: .cancel(Text("Back")) {
                    viewModel.actionFailurePopup = nil
                }
            )
        }
    }

    // MARK: - Sidebar (search + ticket entry)

    private var sidebar: some View {
        List {
            // -- Ticket reference --
            Section {
                TextField("Ticket reference (optional)", text: $viewModel.ticketReference)
                    .textFieldStyle(.roundedBorder)
                    .forsettiNoAutoCorrectionTextInput()

                Button {
                    showSDPlusUnavailableAlert = true
                } label: {
                    Label("SD+ Ticket", systemImage: "ticket")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.forsettiSecondary)
                .frame(maxWidth: .infinity, minHeight: SupportTechnicianLayout.controlButtonHeight)
                .help("SD+ ticket creation is not available in this build.")
            } header: {
                SupportSectionHeader(title: "Ticket")
            }

            // -- Search controls --
            Section {
                HStack(spacing: 10) {
                    TextField("Username or serial number", text: $viewModel.query.strippingControlCharacters())
                        .textFieldStyle(.roundedBorder)
                        .forsettiNoAutoCorrectionTextInput()

                    ScanIntoTextFieldButton(text: $viewModel.query.strippingControlCharacters())
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Search Scope")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Picker("Scope", selection: $viewModel.searchScope) {
                        ForEach(SupportSearchScope.allCases) { scope in
                            Text(scope.title).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Button {
                    Task {
                        await viewModel.executeSearch()
                    }
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.forsettiPrimary)
                .frame(maxWidth: .infinity, minHeight: SupportTechnicianLayout.controlButtonHeight)
                .disabled(viewModel.isSearching)
            } header: {
                SupportSectionHeader(title: "Search")
            }

            // -- Loading / status / error banners --
            if viewModel.isSearching {
                Section {
                    ProgressView("Searching Jamf Pro...")
                }
            }
            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            if let statusMessage = viewModel.statusMessage {
                Section {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            // -- Search results --
            Section {
                if viewModel.searchResults.isEmpty {
                    Text("No results yet. Run a search to find managed assets.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.searchResults) { result in
                        Button {
                            viewModel.selectedResultID = result.id
                        } label: {
                            SupportSearchResultRow(
                                result: result,
                                isSelected: viewModel.selectedResultID == result.id
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(viewModel.isLoadingDetail || viewModel.isSearching)
                    }
                }
            } header: {
                SupportSectionHeader(title: "Results")
            }
        }
        .forsettiInsetGroupedListStyle()
        .scrollContentBackground(.hidden)
        .navigationTitle("Support Technician")
#if os(macOS)
        .navigationSplitViewColumnWidth(min: 430, ideal: 500, max: 620)
#endif
    }

    // MARK: - Detail pane

    @ViewBuilder
    private var detailPane: some View {
        if let selectedDetail = viewModel.selectedDetail {
            SupportDeviceDetailView(
                detail: selectedDetail,
                actions: viewModel.availableActions,
                isLoadingDetail: viewModel.isLoadingDetail,
                isPerformingAction: viewModel.isPerformingAction,
                commandLifecycle: viewModel.commandLifecycle,
                onRefresh: {
                    Task { await viewModel.refreshSelectedDeviceDetail() }
                },
                onClearCache: {
                    Task { await viewModel.clearLocalCache() }
                },
                onOpenInJamf: {
                    Task { await viewModel.openSelectedDeviceInJamf() }
                },
                onAction: routeAction(_:),
                onDismissLifecycle: {
                    viewModel.dismissCommandLifecycle()
                },
                onResetUserPassword: { user in
                    viewModel.requestPasswordReset(for: user)
                },
                installedApplications: viewModel.installedApplications,
                isLoadingInstalledApplications: viewModel.isLoadingInstalledApplications,
                onLoadInstalledApplications: {
                    Task { await viewModel.loadInstalledApplications() }
                },
                isPerformingAppAction: viewModel.isPerformingAppAction,
                onAppAction: { appAction in
                    Task { await viewModel.performAppAction(appAction) }
                },
                applicationManagerMissingPrivileges: viewModel.applicationManagerMissingPrivileges,
                isCheckingApplicationManagerPrivileges: viewModel.isCheckingApplicationManagerPrivileges,
                onCheckApplicationManagerPrivileges: {
                    Task { await viewModel.checkApplicationManagerPrivileges() }
                },
                applicationActionVerification: viewModel.applicationActionVerification,
                statusMessage: viewModel.statusMessage,
                errorMessage: viewModel.errorMessage,
                isApplicationManagerPresented: $isApplicationManagerPresented,
                commandHistory: viewModel.commandHistory,
                isLoadingCommandHistory: viewModel.isLoadingCommandHistory,
                commandHistoryError: viewModel.commandHistoryError,
                onLoadCommandHistory: {
                    Task { await viewModel.loadCommandHistory() }
                },
                allPolicies: viewModel.allPolicies,
                isLoadingAllPolicies: viewModel.isLoadingAllPolicies,
                allPoliciesError: viewModel.allPoliciesError,
                onLoadAllPolicies: {
                    Task { await viewModel.loadAllPolicies() }
                }
            )
            .navigationTitle(selectedDetail.summary.displayName)
            .forsettiInlineNavigationTitle()
        } else if viewModel.isLoadingDetail {
            ProgressView("Loading device detail...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView(
                "Select a Device",
                systemImage: "wrench.and.screwdriver",
                description: Text("Select a search result to load diagnostics, full device data, and management actions.")
            )
        }
    }

    /// Routes a button tap into either the typed-confirm sheet or
    /// direct execution depending on `action.confirmationStrength`.
    /// Every destructive action goes through the typed sheet per the
    /// redesign spec.
    private func routeAction(_ action: SupportManagementAction) {
        switch action.confirmationStrength {
        case .none, .alertOnly:
            Task {
                await viewModel.performAction(action)
            }
        case .typed:
            typedConfirmationText = ""
            pendingTypedConfirmAction = action
        }
    }
}

/// A single row in the search results list, showing the device name, serial number,
/// asset type badge, user, model, and OS version.
private struct SupportSearchResultRow: View {
    /// The search result to display.
    let result: SupportSearchResult

    /// Whether this result is currently selected for detail viewing.
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: ForsettiTheme.Spacing.compact) {
            HStack(spacing: 8) {
                Image(systemName: result.assetType.iconSystemName)
                    .foregroundStyle(.tint)
                    .frame(width: 22)

                Text(result.displayName)
                    .font(ForsettiSearchResultTypography.headline())

                Spacer(minLength: 0)

                Text(result.assetType.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(ForsettiTheme.groupedSurface)
                    .clipShape(Capsule())

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(ForsettiColors.greenPrimary)
                }
            }

            Text("Serial: \(result.serialNumber)")
                .font(ForsettiSearchResultTypography.subheadline())

            if let username = result.username, username.isEmpty == false {
                Text("User: \(username)")
                    .font(ForsettiSearchResultTypography.caption())
                    .foregroundStyle(.secondary)
            }
            if let model = result.model, model.isEmpty == false {
                Text("Model: \(model)")
                    .font(ForsettiSearchResultTypography.caption())
                    .foregroundStyle(.secondary)
            }
            if let osVersion = result.osVersion, osVersion.isEmpty == false {
                Text("OS: \(osVersion)")
                    .font(ForsettiSearchResultTypography.caption())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}

/// The redesigned device-detail view — a scrolling stack of category
/// frames topped by a Metal command-lifecycle indicator. Replaces the
/// previous single-`List` layout whose section priorities were string-
/// matched at render time.
private struct SupportDeviceDetailView: View {
    let detail: SupportDeviceDetail
    let actions: [SupportManagementAction]
    let isLoadingDetail: Bool
    let isPerformingAction: Bool
    let commandLifecycle: CommandLifecyclePhase
    let onRefresh: () -> Void
    let onClearCache: () -> Void
    let onOpenInJamf: () -> Void
    let onAction: (SupportManagementAction) -> Void
    let onDismissLifecycle: () -> Void

    /// Per-row password-reset callback for the User Accounts frame.
    /// Captures the user the technician tapped Reset Password on so the
    /// parent view can present the typed-confirm sheet bound to that
    /// user. See `SupportTechnicianViewModel.requestPasswordReset(for:)`.
    let onResetUserPassword: (SupportLocalUser) -> Void

    // Application Manager wiring
    let installedApplications: [DeviceApplication]
    let isLoadingInstalledApplications: Bool
    let onLoadInstalledApplications: () -> Void
    let isPerformingAppAction: Bool
    let onAppAction: (ApplicationAction) -> Void
    let applicationManagerMissingPrivileges: [String]?
    let isCheckingApplicationManagerPrivileges: Bool
    let onCheckApplicationManagerPrivileges: () -> Void
    let applicationActionVerification: ApplicationActionVerificationState
    let statusMessage: String?
    let errorMessage: String?
    @Binding var isApplicationManagerPresented: Bool

    // Command history wiring (3.22.1)
    let commandHistory: SupportMDMCommandHistory
    let isLoadingCommandHistory: Bool
    let commandHistoryError: String?
    let onLoadCommandHistory: () -> Void

    // Tenant-wide policy frame wiring (3.22.2)
    let allPolicies: [SupportPolicy]
    let isLoadingAllPolicies: Bool
    let allPoliciesError: String?
    let onLoadAllPolicies: () -> Void

    /// Tracks first-appear command-history auto-load so the user doesn't
    /// see an empty frame on initial device selection. SwiftUI re-runs
    /// `onAppear` on every view rebuild, so we gate the load with a
    /// per-device flag.
    @State private var lastHistoryLoadDeviceID: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // MDM command status indicator was removed per user
                // direction — the thin single-row version felt cramped
                // and the larger 3-node visual took too much vertical
                // space. Status info still surfaces through
                // `statusMessage` (success), `actionResult.sensitiveValue`
                // (one-time credential displays), the `actionFailurePopup`
                // alert (failures), and the diagnostics export.
                //
                // `CommandStatusIndicatorView` and the underlying Metal
                // renderer + SwiftUI fallback remain in the codebase
                // (`DesignSystem/Commands/`) in case a future visual
                // surface wants them.

                // Status / error banners — kept above the frames so the
                // technician sees inline feedback for both command-result
                // and non-command flows (detail-load errors, etc.). The
                // previous code gated `statusMessage` behind
                // `commandLifecycle == .idle` so the visual indicator
                // owned the in-flight surface; now that the indicator is
                // gone the banner is the primary surface for command
                // success messages and runs unconditionally.
                if let errorMessage, errorMessage.isEmpty == false {
                    bannerCard(text: errorMessage, color: .red, icon: "exclamationmark.triangle.fill")
                }
                if let statusMessage, statusMessage.isEmpty == false {
                    bannerCard(text: statusMessage, color: .secondary, icon: "info.circle")
                }

                PrimaryActionBand(
                    detail: detail,
                    actions: primaryContextActions,
                    isActionBusy: isPerformingAction || isLoadingDetail,
                    isLoadingCommandHistory: isLoadingCommandHistory,
                    onAction: onAction,
                    onReloadDetail: onRefresh,
                    onLoadCommandHistory: onLoadCommandHistory,
                    onOpenInJamf: onOpenInJamf
                )

                // Diagnostics frame, always visible (even when empty).
                DiagnosticsFrame(diagnostics: detail.diagnostics)

                // Category frames in their declared order. `.applications`
                // always renders so the Manage Applications entry is
                // discoverable; other categories without content render an
                // empty-state placeholder via `GenericSectionsFrame`.
                ForEach(orderedCategories, id: \.self) { category in
                    SupportCategoryFrameView(
                        category: category,
                        detail: detail,
                        availableActions: actions,
                        isPerformingAction: isPerformingAction || isLoadingDetail,
                        onAction: onAction,
                        installedAppsCount: installedApplications.count,
                        onManageApplications: {
                            isApplicationManagerPresented = true
                        },
                        allPolicies: allPolicies,
                        isLoadingAllPolicies: isLoadingAllPolicies,
                        allPoliciesError: allPoliciesError,
                        onLoadAllPolicies: onLoadAllPolicies,
                        onResetUserPassword: onResetUserPassword
                    )
                }

                CommandHistoryFrame(
                    history: commandHistory,
                    isLoading: isLoadingCommandHistory,
                    errorMessage: commandHistoryError,
                    onRefresh: onLoadCommandHistory
                )

                // Secondary reload-detail hook so technicians can re-fetch
                // the local detail record without queuing an inventory command.
                Button {
                    onRefresh()
                } label: {
                    Label("Reload Device Detail", systemImage: "arrow.clockwise")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.forsettiSecondary)
                .frame(maxWidth: .infinity, minHeight: SupportTechnicianLayout.controlButtonHeight)
                .disabled(isLoadingDetail || isPerformingAction)
            }
            .padding(20)
        }
        .scrollContentBackground(.hidden)
        .toolbar {
            // Cache controls — explicit Refresh re-fetches just this
            // device's detail (bypasses the persistent cache); Clear
            // Cache wipes every cached payload + tenant policy list.
            // Both live at the leading end of the toolbar so they sit
            // next to the device-detail content, not buried among the
            // MDM command buttons.
            ToolbarItemGroup(placement: .cancellationAction) {
                Button {
                    onRefresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise.circle")
                }
                .disabled(isLoadingDetail)
                .help("Re-fetch this device from Jamf Pro (bypass local cache).")

                Button {
                    onClearCache()
                } label: {
                    Label("Clear Cache", systemImage: "xmark.circle")
                }
                .help("Wipe every cached device payload and the tenant policy list.")
            }

            ToolbarItemGroup(placement: .primaryAction) {
                ForEach(universalToolbarActions) { action in
                    let availability = action.availability(for: detail)
                    Button {
                        onAction(action)
                    } label: {
                        Label(action.title, systemImage: action.systemImage)
                    }
                    .disabled(isPerformingAction || isLoadingDetail || availability.isAvailable == false)
                    .help("\(action.subtitle)\n\(availability.helpText)")
                }
            }
        }
        .onAppear {
            if lastHistoryLoadDeviceID != detail.summary.id {
                lastHistoryLoadDeviceID = detail.summary.id
                onLoadCommandHistory()
            }
        }
        .onChange(of: detail.summary.id) { _, newID in
            if lastHistoryLoadDeviceID != newID {
                lastHistoryLoadDeviceID = newID
                onLoadCommandHistory()
            }
        }
        // Application Manager modal — kept as a sheet for cross-platform
        // reliability. NavigationLink and `.navigationDestination` are both
        // flaky inside `NavigationSplitView`'s detail column on macOS.
        .sheet(isPresented: $isApplicationManagerPresented) {
            NavigationStack {
                ApplicationManagerView(
                    deviceName: detail.summary.displayName,
                    serialNumber: detail.summary.serialNumber,
                    assetType: detail.summary.assetType,
                    installedApplications: installedApplications,
                    isLoadingInstalledApplications: isLoadingInstalledApplications,
                    isPerformingAppAction: isPerformingAppAction,
                    missingPrivileges: applicationManagerMissingPrivileges,
                    isCheckingPrivileges: isCheckingApplicationManagerPrivileges,
                    verificationState: applicationActionVerification,
                    statusMessage: statusMessage,
                    errorMessage: errorMessage,
                    onLoad: onLoadInstalledApplications,
                    onAppAction: onAppAction,
                    onCheckPrivileges: onCheckApplicationManagerPrivileges
                )
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button {
                            isApplicationManagerPresented = false
                        } label: {
                            Label("Back", systemImage: "chevron.left")
                                .labelStyle(.titleAndIcon)
                        }
                    }
                }
            }
#if os(macOS)
            .frame(minWidth: 720, idealWidth: 820, minHeight: 520, idealHeight: 640)
#endif
        }
    }

    /// Categories rendered in their `defaultOrder` so the layout is stable
    /// regardless of dictionary iteration.
    private var orderedCategories: [SupportDeviceCategory] {
        // `.hardware` and `.storage` are no longer standalone frames as of
        // 3.22.9 — their data lives inside the General frame as tappable
        // cards (CPU / GPU / RAM / Storage / Battery). `.other` is removed
        // entirely per earlier redesign.
        let hidden: Set<SupportDeviceCategory> = [.other, .hardware, .storage]
        return SupportDeviceCategory.allCases
            .filter { hidden.contains($0) == false }
            .sorted { $0.defaultOrder < $1.defaultOrder }
    }

    /// The three universal commands that always appear in the toolbar
    /// regardless of which frame the technician is scrolled to.
    private var universalToolbarActions: [SupportManagementAction] {
        actions.filter { $0.isUniversalToolbarAction }
    }

    /// Primary device-context commands shown near the top of the detail pane.
    /// This intentionally reuses the existing action enum and service dispatch
    /// path instead of introducing parallel command logic.
    private var primaryContextActions: [SupportManagementAction] {
        let preferred: [SupportManagementAction] = [
            .refreshInventory,
            .blankPush,
            .discoverApplications
        ]
        return preferred.filter { actions.contains($0) }
    }

    private func bannerCard(text: String, color: Color, icon: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(text)
                .font(.footnote)
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(ForsettiTheme.groupedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10).stroke(ForsettiTheme.border, lineWidth: 1)
        )
    }
}

private struct PrimaryActionBand: View {
    let detail: SupportDeviceDetail
    let actions: [SupportManagementAction]
    let isActionBusy: Bool
    let isLoadingCommandHistory: Bool
    let onAction: (SupportManagementAction) -> Void
    let onReloadDetail: () -> Void
    let onLoadCommandHistory: () -> Void
    let onOpenInJamf: () -> Void

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 220), spacing: 8, alignment: .top)]
    }

    private var hasInventoryID: Bool {
        detail.summary.inventoryID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    var body: some View {
        CategoryFrame(
            category: .general,
            titleOverride: "Primary Actions",
            subtitle: "\(detail.summary.assetType.title) workflow",
            bodyMaxHeight: 260
        ) {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(actions) { action in
                    PrimaryManagementActionButton(
                        action: action,
                        detail: detail,
                        isBusy: isActionBusy,
                        onAction: onAction
                    )
                }

                PrimaryLocalActionButton(
                    title: "Reload Device Detail",
                    subtitle: "Re-fetch Jamf detail only",
                    status: "Does not queue inventory",
                    systemImage: "arrow.clockwise.circle",
                    isDisabled: isActionBusy,
                    helpText: "Re-fetches this device from Jamf Pro and bypasses local cache. This is separate from Update Inventory.",
                    action: onReloadDetail
                )

                PrimaryLocalActionButton(
                    title: "Load Command History",
                    subtitle: "Refresh recent MDM commands",
                    status: isLoadingCommandHistory ? "Running" : "Available",
                    systemImage: "clock.arrow.circlepath",
                    isDisabled: isLoadingCommandHistory,
                    helpText: "Loads recent Jamf MDM command history for this device.",
                    action: onLoadCommandHistory
                )

                PrimaryLocalActionButton(
                    title: "Open in Jamf",
                    subtitle: "Open native management page",
                    status: hasInventoryID ? "Available" : "Requires inventory ID",
                    systemImage: "arrow.up.right.square",
                    isDisabled: hasInventoryID == false,
                    helpText: "Opens this device's Jamf Pro management page in the default browser.",
                    action: onOpenInJamf
                )
            }
        }
    }
}

private struct PrimaryManagementActionButton: View {
    let action: SupportManagementAction
    let detail: SupportDeviceDetail
    let isBusy: Bool
    let onAction: (SupportManagementAction) -> Void

    private var availability: SupportActionAvailability {
        action.availability(for: detail)
    }

    private var statusText: String {
        if isBusy {
            return "Running"
        }
        return availability.helpText
    }

    @ViewBuilder
    var body: some View {
        if action == .refreshInventory {
            button
                .buttonStyle(.forsettiPrimary)
        } else {
            button
                .buttonStyle(.forsettiSecondary)
        }
    }

    private var button: some View {
        Button {
            onAction(action)
        } label: {
            PrimaryActionLabel(
                title: action.title,
                subtitle: action.subtitle,
                status: statusText,
                systemImage: action.systemImage,
                isBlocked: availability.isAvailable == false
            )
        }
        .frame(maxWidth: .infinity, minHeight: SupportTechnicianLayout.controlButtonHeight)
        .disabled(isBusy || availability.isAvailable == false)
        .help("\(action.subtitle)\n\(availability.helpText)")
    }
}

private struct PrimaryLocalActionButton: View {
    let title: String
    let subtitle: String
    let status: String
    let systemImage: String
    let isDisabled: Bool
    let helpText: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PrimaryActionLabel(
                title: title,
                subtitle: subtitle,
                status: status,
                systemImage: systemImage,
                isBlocked: isDisabled && status != "Running"
            )
        }
        .buttonStyle(.forsettiSecondary)
        .frame(maxWidth: .infinity, minHeight: SupportTechnicianLayout.controlButtonHeight)
        .disabled(isDisabled)
        .help(helpText)
    }
}

private struct PrimaryActionLabel: View {
    let title: String
    let subtitle: String
    let status: String
    let systemImage: String
    let isBlocked: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(status)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(isBlocked ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Application Manager (v3.18+)

/// The Application Manager sub-view, presented as a navigation destination
/// from the device detail.
///
/// Shows the list of applications currently installed on the target Mac
/// (sourced from `GET /api/v1/computers-inventory/{id}?section=APPLICATIONS`)
/// and provides Install and Uninstall actions that trigger pre-existing
/// Jamf Pro policies via custom triggers (`install-<appName>`,
/// `uninstall-<appName>`).
///
/// Uninstall is intentionally a *reset*: the device's group-assigned policy
/// reinstalls the app on the next check-in. There is no permanent "Remove"
/// action — this view refuses to help with that by design.
///
/// Mobile devices are out of scope: the controls are hidden and an inline
/// note directs the technician to Jamf Pro's web console.
///
/// Install / Uninstall buttons are wired in later steps of the implementation
/// plan; this initial version renders the list read-only so the Jamf Pro
/// `APPLICATIONS` section fetch can be verified end-to-end in isolation.
private struct ApplicationManagerView: View {
    /// The device display name shown in the section header.
    let deviceName: String

    /// The target device's hardware serial number. Shown under the name
    /// so the technician can cross-check they're working on the right Mac.
    let serialNumber: String

    /// The asset type of the selected device. Mobile devices see a
    /// configuration banner instead of the installed-apps list.
    let assetType: SupportAssetType

    /// Installed applications, fetched from Jamf Pro on first appear / refresh.
    let installedApplications: [DeviceApplication]

    /// Whether `fetchInstalledApplications` is in flight.
    let isLoadingInstalledApplications: Bool

    /// Whether an install-or-uninstall action is in flight. Disables the
    /// per-row Uninstall buttons while a request is being dispatched.
    let isPerformingAppAction: Bool

    /// Missing privilege names from the Jamf Pro pre-flight. `nil` before
    /// the first check; `[]` when all privileges are present; non-empty
    /// when the banner should name the specific privileges to grant.
    let missingPrivileges: [String]?

    /// Whether the privilege pre-flight is running.
    let isCheckingPrivileges: Bool

    /// Post-action verification state rendered as a banner below the
    /// status/error banners. Transitions through queued → checkingIn →
    /// verified / timedOut.
    let verificationState: ApplicationActionVerificationState

    /// Status message for the banner at the top of the view.
    let statusMessage: String?

    /// Error message for the banner at the top of the view.
    let errorMessage: String?

    /// Fires on first appearance (auto-load) and when the Refresh button is tapped.
    let onLoad: () -> Void

    /// Fires when the user confirms an Install or Uninstall action.
    let onAppAction: (ApplicationAction) -> Void

    /// Fires on first appearance to run the privilege pre-flight.
    let onCheckPrivileges: () -> Void

    /// Tracks whether the auto-load has already fired so the view doesn't
    /// spam `onLoad()` every time SwiftUI rebuilds the destination.
    @State private var hasAutoLoaded = false

    /// Tracks whether the pre-flight privilege check has already fired.
    @State private var hasRunPrivilegeCheck = false

    /// The action awaiting confirmation. `nil` when no confirm dialog is shown.
    @State private var pendingAction: ApplicationAction?

    /// Text currently typed into the Install field. Bound to a `TextField`.
    @State private var installAppName: String = ""

    /// Whether Install / Uninstall are disabled because the pre-flight
    /// found missing privileges. Returns `false` when the check hasn't run
    /// yet (don't pre-emptively block; the user can still attempt and
    /// the action itself will 403 informatively).
    private var isGatedByMissingPrivileges: Bool {
        guard let missing = missingPrivileges else {
            return false
        }
        return missing.isEmpty == false
    }

    var body: some View {
        List {
            // -- Device identity header --
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(deviceName)
                        .font(.headline)
                    Text("Serial: \(serialNumber)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            // -- Status / error banners --
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            // -- Post-action verification banner --
            if let verificationText = Self.verificationBannerText(for: verificationState) {
                Section {
                    HStack(spacing: 8) {
                        Image(systemName: Self.verificationBannerIcon(for: verificationState))
                            .foregroundStyle(Self.verificationBannerTint(for: verificationState))
                        Text(verificationText)
                            .font(.footnote)
                    }
                }
            }

            // -- Privilege pre-flight banner --
            if let missing = missingPrivileges, missing.isEmpty == false {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Missing Jamf Pro privileges", systemImage: "exclamationmark.triangle.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.red)
                        Text("Install and Uninstall are disabled because the Forsetti API role is missing the following privileges on Jamf Pro:")
                            .font(.footnote)
                        ForEach(missing, id: \.self) { name in
                            Text("• \(name)")
                                .font(.footnote.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Text("Grant these privileges to the API role in Jamf Pro and try again.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } else if isCheckingPrivileges {
                Section {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Verifying Jamf Pro privileges…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // -- Mobile devices: out-of-scope note --
            if assetType == .mobileDevice {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Mobile devices not yet supported", systemImage: "iphone.gen3")
                            .font(.body.weight(.semibold))
                        Text("Application management for mobile devices is handled via Jamf Pro's app scope. Use the web console for now.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                // -- Install form --
                Section {
                    HStack(spacing: 10) {
                        TextField("Exact app name (e.g. Slack)", text: $installAppName)
                            .textFieldStyle(.roundedBorder)
                            .forsettiNoAutoCorrectionTextInput()

                        Button {
                            let trimmed = installAppName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard trimmed.isEmpty == false else { return }
                            pendingAction = .install(appName: trimmed)
                        } label: {
                            Label("Install", systemImage: "square.and.arrow.down")
                                .labelStyle(.titleAndIcon)
                        }
                        .buttonStyle(.forsettiPrimary)
                        .disabled(
                            installAppName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || isPerformingAppAction
                                || isGatedByMissingPrivileges
                        )
                    }
                } header: {
                    SupportSectionHeader(title: "Install Application")
                }

                // -- Progress banner while a Jamf Pro dispatch is in flight --
                if isPerformingAppAction {
                    Section {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Dispatching Application Manager action…")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // -- Installed applications list with Uninstall buttons --
                Section {
                    if isLoadingInstalledApplications {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Loading installed applications…")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    } else if installedApplications.isEmpty {
                        Text("No installed applications reported by Jamf Pro for this Mac. Tap Refresh to try again.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(installedApplications) { app in
                            ApplicationManagerRow(
                                application: app,
                                isActionInFlight: isPerformingAppAction,
                                isUninstallDisabled: isGatedByMissingPrivileges,
                                onUninstall: {
                                    pendingAction = .uninstall(appName: app.displayName)
                                }
                            )
                        }
                    }

                    Button {
                        onLoad()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.forsettiSecondary)
                    .disabled(isLoadingInstalledApplications || isPerformingAppAction)
                } header: {
                    SupportSectionHeader(title: "Installed Applications (\(installedApplications.count))")
                }
            }
        }
        .forsettiInsetGroupedListStyle()
        .navigationTitle("Application Manager")
        .forsettiInlineNavigationTitle()
        .onAppear {
            if assetType == .computer,
               hasAutoLoaded == false,
               isLoadingInstalledApplications == false
            {
                hasAutoLoaded = true
                onLoad()
            }

            if assetType == .computer,
               hasRunPrivilegeCheck == false,
               isCheckingPrivileges == false
            {
                hasRunPrivilegeCheck = true
                onCheckPrivileges()
            }
        }
        .alert(
            pendingAction?.confirmationTitle ?? "Confirm",
            isPresented: Binding(
                get: { pendingAction != nil },
                set: { isPresented in
                    if isPresented == false {
                        pendingAction = nil
                    }
                }
            )
        ) {
            Button("Cancel", role: .cancel) {
                pendingAction = nil
            }

            Button("Confirm") {
                guard let action = pendingAction else {
                    return
                }
                pendingAction = nil
                onAppAction(action)
            }
        } message: {
            Text(pendingAction?.confirmationMessage ?? "")
        }
    }

    // MARK: - Verification banner helpers

    private static func verificationBannerText(
        for state: ApplicationActionVerificationState
    ) -> String? {
        switch state {
        case .idle:
            return nil
        case let .queued(action, serialNumber, _):
            return "\(action.queuedVerb) queued for \(action.appName) on \(serialNumber). Waiting for the device to check in…"
        case let .checkingIn(action, serialNumber, _, attempt):
            return "\(action.queuedVerb) \(action.appName) on \(serialNumber): verifying (attempt \(attempt))…"
        case let .verified(action, serialNumber, duration):
            return "\(action.queuedVerb) verified for \(action.appName) on \(serialNumber) after \(Int(duration)) seconds."
        case let .timedOut(action, serialNumber):
            return "\(action.queuedVerb) for \(action.appName) on \(serialNumber) didn't verify within 10 minutes. Check Jamf Pro's device policy log."
        }
    }

    private static func verificationBannerIcon(
        for state: ApplicationActionVerificationState
    ) -> String {
        switch state {
        case .idle: return "info.circle"
        case .queued: return "clock"
        case .checkingIn: return "arrow.clockwise"
        case .verified: return "checkmark.seal.fill"
        case .timedOut: return "exclamationmark.triangle"
        }
    }

    private static func verificationBannerTint(
        for state: ApplicationActionVerificationState
    ) -> Color {
        switch state {
        case .idle: return .secondary
        case .queued: return ForsettiColors.bluePrimary
        case .checkingIn: return ForsettiColors.bluePrimary
        case .verified: return ForsettiColors.greenPrimary
        case .timedOut: return .orange
        }
    }
}

/// A single row in the Installed Applications list.
private struct ApplicationManagerRow: View {
    let application: DeviceApplication
    let isActionInFlight: Bool
    let isUninstallDisabled: Bool
    let onUninstall: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(application.displayName)
                        .font(.body.weight(.semibold))
                    if let version = application.version, version.isEmpty == false {
                        Text("·").foregroundStyle(.secondary)
                        Text(version)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if let path = application.path, path.isEmpty == false {
                    Text(path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                if let bundleIdentifier = application.bundleIdentifier,
                   bundleIdentifier.isEmpty == false
                {
                    Text(bundleIdentifier)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 0)

            Button {
                onUninstall()
            } label: {
                Label("Uninstall", systemImage: "arrow.down.circle")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.forsettiDanger)
            .disabled(isActionInFlight || isUninstallDisabled)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

/// A simple reusable section header for the sidebar lists. The
/// help-popover "info" button that previously decorated this header was
/// removed in the redesign; per-section help now lives in onboarding
/// docs, not inline UI noise.
private struct SupportSectionHeader: View {
    /// The section heading text.
    let title: String

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 0)
        }
        .textCase(nil)
    }
}

//endofline
