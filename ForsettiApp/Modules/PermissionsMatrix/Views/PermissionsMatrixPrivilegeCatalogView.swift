import SwiftUI

/// Privilege catalog: browse Jamf Pro privilege names and see which Forsetti
/// actions and API endpoints depend on each one. Side-by-side when wide enough;
/// a stacked, fully-scrollable master→detail otherwise (iPhone, iPad portrait).
struct PermissionsMatrixPrivilegeCatalogView: View {
    @ObservedObject var viewModel: PermissionsMatrixViewModel

    // Tuned so iPad landscape clears it with margin while portrait devices and
    // iPhone stay stacked (see CommandExplorer for the device-width rationale).
    private static let wideThreshold: CGFloat = 1040

    var body: some View {
        GeometryReader { proxy in
            content(width: proxy.size.width, height: proxy.size.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// Width-driven (iPad is `.regular` in both orientations, so size class alone
    /// can't distinguish portrait from landscape).
    @ViewBuilder
    private func content(width: CGFloat, height: CGFloat) -> some View {
        if width >= Self.wideThreshold {
            regularBody
        } else {
            narrowBody(diagramHeight: max(360, min(height * 0.62, 560)))
        }
    }

    private var regularBody: some View {
        HStack(alignment: .top, spacing: PHMetrics.gap) {
            listPane
                .frame(minWidth: 280, idealWidth: 320, maxWidth: 360)
            regularDetail
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    @ViewBuilder
    private var regularDetail: some View {
        if let privilege = viewModel.selectedPrivilege {
            VStack(alignment: .leading, spacing: PHMetrics.gap) {
                detailHeader(privilege)
                HStack(alignment: .top, spacing: PHMetrics.gap) {
                    ScrollView {
                        detailSections(privilege)
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

    @ViewBuilder
    private func narrowBody(diagramHeight: CGFloat) -> some View {
        if let privilege = viewModel.selectedPrivilege {
            ScrollView {
                VStack(alignment: .leading, spacing: PHMetrics.gap) {
                    Button { viewModel.selectedPrivilege = nil } label: {
                        Label("Privileges", systemImage: "chevron.left")
                    }
                    .buttonStyle(.borderless).controlSize(.small)
                    detailHeader(privilege)
                    detailSections(privilege)
                    PermissionHelperPhase3VisualMatrixPanel(viewModel: viewModel, diagramHeight: diagramHeight)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 4)
            }
        } else {
            listPane
        }
    }

    private var listPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            PHSearchField(placeholder: "Search privileges",
                          text: $viewModel.privilegeSearchText,
                          accessibilityLabelText: "Search privileges")

            Text("\(viewModel.filteredPrivileges.count) privilege(s)")
                .font(.caption2).foregroundStyle(.secondary)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(viewModel.filteredPrivileges, id: \.self) { privilege in
                            PHSelectRow(isSelected: viewModel.selectedPrivilege == privilege,
                                        action: { viewModel.selectedPrivilege = privilege }) {
                                HStack(spacing: 7) {
                                    Image(systemName: "key.fill")
                                        .font(.caption2).foregroundStyle(Color(red: 0.40, green: 0.82, blue: 0.88))
                                    Text(privilege).font(.callout).lineLimit(2)
                                    Spacer(minLength: 0)
                                }
                            }
                            .id(privilege)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: .infinity)
                .onChange(of: viewModel.selectedPrivilege) { _, value in
                    guard let value else { return }
                    withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(value, anchor: .center) }
                }
            }
        }
    }

    private var emptyDetail: some View {
        VStack(spacing: 10) {
            Image(systemName: "key").font(.largeTitle).foregroundStyle(.secondary)
            Text("Select a privilege to see related actions and endpoints.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func detailHeader(_ privilege: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "key.fill")
                .font(.title3).foregroundStyle(Color(red: 0.40, green: 0.82, blue: 0.88))
            Text(privilege).font(.title3.bold()).textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button { viewModel.copyPrivilegeName(privilege) } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .buttonStyle(.bordered).controlSize(.small).tint(DashboardColors.bluePrimary)
            .accessibilityLabel("Copy privilege name \(privilege)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .phCard()
    }

    private func detailSections(_ privilege: String) -> some View {
        VStack(alignment: .leading, spacing: PHMetrics.gap) {
            relatedActions(privilege)
            relatedEndpoints(privilege)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func relatedActions(_ privilege: String) -> some View {
        let actions = viewModel.actions(requiring: privilege)
        PHSectionCard(title: "Forsetti actions (\(actions.count))", systemImage: "command") {
            if actions.isEmpty {
                Text("No Forsetti actions reference this privilege.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 4) {
                    ForEach(actions) { action in
                        PHSelectRow(isSelected: false, accessibilityHint: "Opens in the Commands tab", action: {
                            viewModel.selectedActionID = action.commandID
                            viewModel.selectedSection = .commands
                        }) {
                            HStack(spacing: 7) {
                                Image(systemName: "command").font(.caption2).foregroundStyle(.secondary)
                                Text(action.resolvedDisplayName).font(.callout)
                                if let module = action.module {
                                    Text(module).font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func relatedEndpoints(_ privilege: String) -> some View {
        let endpoints = viewModel.endpoints(requiring: privilege)
        PHSectionCard(title: "API endpoints (\(endpoints.count))", systemImage: "network") {
            if endpoints.isEmpty {
                Text("No catalogued endpoints list this privilege.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(endpoints) { entry in
                        PermissionsMatrixEndpointBadge(method: entry.method, path: entry.path, isClassic: entry.isClassic)
                    }
                }
            }
        }
    }
}
