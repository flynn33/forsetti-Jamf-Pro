import SwiftUI

/// Command/action explorer: pick a Jamf Dashboard action and see the Jamf Pro
/// privileges, endpoints, and verification notes it requires. Side-by-side when
/// the area is wide enough; a stacked, fully-scrollable master→detail otherwise
/// (iPhone, and iPad in portrait).
struct PermissionsMatrixCommandExplorerView: View {
    @ObservedObject var viewModel: PermissionsMatrixViewModel

    /// Minimum width to host list + permissions + diagram side-by-side. Below this
    /// (iPhone, iPad portrait) the layout stacks and scrolls instead of cramming
    /// three columns into too little width. Tuned so iPad 11"/13" landscape
    /// (measured width ≈1162/1334 after the root padding) clear it with margin,
    /// while every portrait device and iPhone stay stacked.
    private static let wideThreshold: CGFloat = 1040

    var body: some View {
        GeometryReader { proxy in
            content(width: proxy.size.width, height: proxy.size.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// iPad orientation is not a size-class change (iPad is `.regular` in both
    /// orientations), so layout is driven by the available width, not the size class.
    @ViewBuilder
    private func content(width: CGFloat, height: CGFloat) -> some View {
        if width >= Self.wideThreshold {
            regularBody
        } else {
            narrowBody(diagramHeight: max(360, min(height * 0.62, 560)))
        }
    }

    // MARK: - Regular (side-by-side)

    private var regularBody: some View {
        HStack(alignment: .top, spacing: PHMetrics.gap) {
            listPane
                .frame(minWidth: 300, idealWidth: 340, maxWidth: 380)
            regularDetail
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var regularDetail: some View {
        if let action = viewModel.selectedAction {
            VStack(alignment: .leading, spacing: PHMetrics.gap) {
                detailHeader(action)
                HStack(alignment: .top, spacing: PHMetrics.gap) {
                    ScrollView {
                        detailSections(action)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    PermissionHelperPhase3VisualMatrixPanel(viewModel: viewModel)
                        .frame(maxWidth: .infinity, alignment: .top)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            emptyDetail
        }
    }

    // MARK: - Narrow (stacked master → detail, fully scrollable)

    @ViewBuilder
    private func narrowBody(diagramHeight: CGFloat) -> some View {
        if let action = viewModel.selectedAction {
            ScrollView {
                VStack(alignment: .leading, spacing: PHMetrics.gap) {
                    Button { viewModel.selectedActionID = nil } label: {
                        Label("Actions", systemImage: "chevron.left")
                    }
                    .buttonStyle(.borderless).controlSize(.small)
                    detailHeader(action)
                    detailSections(action)
                    PermissionHelperPhase3VisualMatrixPanel(viewModel: viewModel, diagramHeight: diagramHeight)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 4)
            }
        } else {
            listPane
        }
    }

    // MARK: - List pane

    private var listPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            PHSearchField(placeholder: "Search actions, privileges, endpoints",
                          text: $viewModel.commandSearchText,
                          accessibilityLabelText: "Search actions")

            HStack(spacing: 8) {
                Picker("Module", selection: $viewModel.moduleFilter) {
                    Text("All modules").tag(String?.none)
                    ForEach(viewModel.availableModules, id: \.self) { module in
                        Text(module).tag(String?.some(module))
                    }
                }
                .labelsHidden().pickerStyle(.menu).controlSize(.small)

                Picker("Device", selection: $viewModel.deviceFamilyFilter) {
                    Text("All devices").tag(String?.none)
                    ForEach(viewModel.availableDeviceFamilies, id: \.self) { family in
                        Text(viewModel.deviceFamilyLabel(family)).tag(String?.some(family))
                    }
                }
                .labelsHidden().pickerStyle(.menu).controlSize(.small)
            }

            HStack(spacing: 6) {
                PHToggleChip(label: "Destructive", systemImage: "exclamationmark.triangle.fill", isOn: $viewModel.destructiveOnly)
                PHToggleChip(label: "Tenant check", systemImage: "checkmark.shield", isOn: $viewModel.tenantVerificationOnly)
            }

            Text("\(viewModel.filteredActions.count) action(s)")
                .font(.caption2).foregroundStyle(.secondary)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(viewModel.filteredActions) { action in
                            PHSelectRow(isSelected: viewModel.selectedActionID == action.commandID,
                                        action: { viewModel.selectedActionID = action.commandID }) {
                                actionRow(action)
                            }
                            .id(action.commandID)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: .infinity)
                .onChange(of: viewModel.selectedActionID) { _, id in
                    guard let id else { return }
                    withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
    }

    private func actionRow(_ action: PermissionsMatrixAction) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(action.resolvedDisplayName).font(.callout.weight(.semibold)).lineLimit(1)
                if action.destructive {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2).foregroundStyle(.orange)
                        .accessibilityLabel("Destructive action")
                }
                if action.deprecatedOrLegacy {
                    PermissionsMatrixTagChip(text: "Legacy", tint: .gray)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                if let module = action.module {
                    Label(module, systemImage: "square.grid.2x2")
                        .font(.caption2).foregroundStyle(.secondary).labelStyle(.titleAndIcon)
                }
                Text(action.deviceFamilyLabel).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Detail sections

    private var emptyDetail: some View {
        VStack(spacing: 10) {
            Image(systemName: "hand.tap").font(.largeTitle).foregroundStyle(.secondary)
            Text("Select an action to see its required Jamf Pro privileges.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func detailSections(_ action: PermissionsMatrixAction) -> some View {
        VStack(alignment: .leading, spacing: PHMetrics.gap) {
            requirementsSection(action)
            endpointsSection(action)
            notesSection(action)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detailHeader(_ action: PermissionsMatrixAction) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(action.resolvedDisplayName).font(.title2.bold())
            FlowLayout(spacing: 6) {
                if let module = action.module { PermissionsMatrixTagChip(text: module, tint: Color(red: 0.40, green: 0.82, blue: 0.88)) }
                if let category = action.category { PermissionsMatrixTagChip(text: category, tint: Color(red: 0.58, green: 0.55, blue: 1.0)) }
                PermissionsMatrixTagChip(text: action.deviceFamilyLabel, tint: .gray)
                if let type = action.actionType { PermissionsMatrixTagChip(text: type, tint: DashboardColors.bluePrimary) }
                if action.destructive { PermissionsMatrixTagChip(text: "Destructive", tint: .orange) }
                if action.localOnly { PermissionsMatrixTagChip(text: "Local only", tint: Color(red: 0.40, green: 0.86, blue: 0.58)) }
            }

            HStack(spacing: 8) {
                Button { viewModel.copyRequiredPrivileges(for: action) } label: {
                    Label("Copy Privileges", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered).controlSize(.small).tint(DashboardColors.bluePrimary)
                .disabled(action.allPrivilegeNames.isEmpty)
                .accessibilityLabel("Copy required privileges for \(action.resolvedDisplayName)")

                Button { viewModel.copyEndpointList(for: action) } label: {
                    Label("Copy Endpoints", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered).controlSize(.small).tint(DashboardColors.bluePrimary)
                .disabled(action.endpoints.isEmpty)
                .accessibilityLabel("Copy endpoint list for \(action.resolvedDisplayName)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .phCard()
    }

    @ViewBuilder
    private func requirementsSection(_ action: PermissionsMatrixAction) -> some View {
        PHSectionCard(title: "Required Privileges", systemImage: "key.fill") {
            if action.requiredPrivilegeRequirements.isEmpty {
                Text(action.localOnly
                     ? "Local-only action — no Jamf Pro privileges required."
                     : "No privilege requirements recorded.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(action.requiredPrivilegeRequirements.enumerated()), id: \.offset) { _, requirement in
                        requirementCard(requirement)
                    }
                }
            }
        }
    }

    private func requirementCard(_ requirement: PrivilegeRequirement) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(requirement.modeDescription).font(.subheadline.weight(.semibold))
                Spacer()
                if let confidence = requirement.confidence {
                    PermissionsMatrixTagChip(
                        text: confidence.replacingOccurrences(of: "_", with: " "),
                        tint: requirement.needsTenantVerification ? .orange : Color(red: 0.40, green: 0.86, blue: 0.58)
                    )
                }
            }

            if let privileges = requirement.privileges, privileges.isEmpty == false {
                privilegeList(privileges)
            }
            if let sets = requirement.privilegeSets, sets.isEmpty == false {
                ForEach(Array(sets.enumerated()), id: \.offset) { index, set in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Set \(index + 1)").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        privilegeList(set)
                    }
                }
            }
            if let computer = requirement.computerPrivileges, computer.isEmpty == false {
                labeledPrivileges("Computer", computer)
            }
            if let mobile = requirement.mobileDevicePrivileges, mobile.isEmpty == false {
                labeledPrivileges("Mobile Device", mobile)
            }
            if let mixed = requirement.mixedOrGroupPrivileges, mixed.isEmpty == false {
                labeledPrivileges("Mixed / Group", mixed)
            }

            if let note = requirement.note {
                Text(note).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .phInnerCard()
    }

    private func labeledPrivileges(_ label: String, _ privileges: [String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            privilegeList(privileges)
        }
    }

    private func privilegeList(_ privileges: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(privileges, id: \.self) { privilege in
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "key.fill")
                        .font(.caption2).foregroundStyle(Color(red: 0.40, green: 0.82, blue: 0.88))
                    Text(privilege).font(.callout).textSelection(.enabled)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    @ViewBuilder
    private func endpointsSection(_ action: PermissionsMatrixAction) -> some View {
        if action.endpoints.isEmpty == false {
            PHSectionCard(title: "Endpoints", systemImage: "network") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(action.endpoints) { endpoint in
                        PermissionsMatrixEndpointBadge(method: endpoint.method, path: endpoint.path, isClassic: endpoint.isClassic)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func notesSection(_ action: PermissionsMatrixAction) -> some View {
        if action.needsTenantVerification || action.notes.isEmpty == false {
            PHSectionCard(title: "Notes & Verification", systemImage: "exclamationmark.circle", accent: .orange) {
                VStack(alignment: .leading, spacing: 6) {
                    if action.needsTenantVerification {
                        Label("Confirm against your tenant /api/doc — some requirements are tenant-verified.", systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    ForEach(action.notes, id: \.self) { note in
                        Text("• \(note)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
