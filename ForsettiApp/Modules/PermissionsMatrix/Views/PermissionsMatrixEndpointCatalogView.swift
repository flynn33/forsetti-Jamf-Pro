import SwiftUI

/// Endpoint catalog: search the modern `/api` and Classic `/JSSResource` privilege
/// catalogs and the MDM command-type overlays. Classic entries are shown honestly
/// because some Forsetti workflows still depend on Classic fallbacks.
struct PermissionsMatrixEndpointCatalogView: View {
    @ObservedObject var viewModel: PermissionsMatrixViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            controls

            Text("\(viewModel.filteredEndpoints.count) endpoint(s)")
                .font(.caption2).foregroundStyle(.secondary)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(viewModel.filteredEndpoints) { entry in
                        endpointCard(entry)
                    }
                    if shouldShowOverlays {
                        overlaysCard
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var shouldShowOverlays: Bool {
        viewModel.endpointSurfaceFilter != .classic
            && viewModel.endpointDeprecatedOnly == false
            && viewModel.mdmOverlays.isEmpty == false
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            PHSearchField(placeholder: "Search method, path, family, or privilege",
                          text: $viewModel.endpointSearchText,
                          accessibilityLabelText: "Search endpoints")

            Picker("Surface", selection: $viewModel.endpointSurfaceFilter) {
                ForEach(PermissionsMatrixEndpointSurfaceFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            HStack(spacing: 6) {
                PHToggleChip(label: "Tenant check", systemImage: "checkmark.shield", isOn: $viewModel.endpointTenantVerificationOnly)
                PHToggleChip(label: "Deprecated only", systemImage: "clock.badge.exclamationmark", isOn: $viewModel.endpointDeprecatedOnly)
            }
        }
    }

    private func endpointCard(_ entry: EndpointPrivilegeEntry) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            PermissionsMatrixEndpointBadge(method: entry.method, path: entry.path, isClassic: entry.isClassic)

            if (entry.family?.isEmpty == false) || (entry.purpose?.isEmpty == false) {
                HStack(spacing: 6) {
                    if let family = entry.family, family.isEmpty == false {
                        PermissionsMatrixTagChip(text: family, tint: Color(red: 0.58, green: 0.55, blue: 1.0))
                    }
                    if let purpose = entry.purpose, purpose.isEmpty == false {
                        Text(purpose).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            if entry.requiredPrivileges.isEmpty {
                Text("No specific privilege recorded (authenticated token).")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(entry.requiredPrivileges, id: \.self) { privilege in
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: "key.fill").font(.caption2).foregroundStyle(Color(red: 0.40, green: 0.82, blue: 0.88))
                        Text(privilege).font(.callout).textSelection(.enabled)
                        Spacer(minLength: 0)
                    }
                }
            }

            if entry.deprecationNote != nil || entry.needsTenantVerification {
                HStack(spacing: 6) {
                    if let deprecation = entry.deprecationNote {
                        PermissionsMatrixTagChip(text: "Deprecates \(deprecation)", tint: Color(red: 1.0, green: 0.46, blue: 0.46))
                    }
                    if entry.needsTenantVerification {
                        PermissionsMatrixTagChip(text: "Tenant verify", tint: .orange)
                    }
                }
            }

            ForEach(entry.notes, id: \.self) { note in
                Text("• \(note)").font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .phCard(padding: 12)
    }

    private var overlaysCard: some View {
        PHSectionCard(title: "MDM Command-Type Overlays", systemImage: "plus.rectangle.on.rectangle",
                      accent: Color(red: 0.74, green: 0.56, blue: 1.0)) {
            VStack(alignment: .leading, spacing: 10) {
                Text("These privileges layer on top of the endpoint-level requirement for POST /api/v2/mdm/commands.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(viewModel.mdmOverlays) { overlay in
                    overlayRow(overlay)
                }
            }
        }
    }

    private func overlayRow(_ overlay: MDMCommandOverlay) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(overlay.commandType).font(.callout.monospaced().weight(.semibold))
                ForEach(overlay.platforms, id: \.self) { platform in
                    PermissionsMatrixTagChip(text: platform, tint: .gray)
                }
                Spacer(minLength: 0)
            }
            ForEach(overlay.additionalRequiredPrivileges, id: \.self) { privilege in
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "plus.circle").font(.caption2).foregroundStyle(Color(red: 0.74, green: 0.56, blue: 1.0))
                    Text(privilege).font(.callout).textSelection(.enabled)
                    Spacer(minLength: 0)
                }
            }
            if let notes = overlay.notes, notes.isEmpty == false {
                Text(notes).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .phInnerCard(padding: 10)
    }
}
