import SwiftUI

/// Root view of the Permissions Matrix module.
///
/// Shows a metadata header, a segmented section picker, and the active section.
/// All sections browse the static matrix offline; runtime comparison is optional.
struct PermissionsMatrixView: View {
    @StateObject var viewModel: PermissionsMatrixViewModel

    // NOTE: No NavigationStack here on purpose. `DashboardView` already hosts each
    // module inside its own NavigationStack and pushes this view via
    // `.navigationDestination`. Nesting a second NavigationStack inside that
    // destination renders blank on macOS (the view loads but never draws), so we
    // use a plain container like the other simple modules do.
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if let loadError = viewModel.loadError {
                PermissionsMatrixErrorView(error: loadError)
            } else if viewModel.document == nil && viewModel.isLoading {
                ProgressView("Loading permissions data…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.document != nil {
                PermissionsMatrixMetadataBar(viewModel: viewModel)

                Picker("Section", selection: $viewModel.selectedSection) {
                    ForEach(PermissionsMatrixSection.allCases) { section in
                        Label(section.rawValue, systemImage: section.systemImage).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                sectionContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(moduleBackground)
        // One cohesive premium dark surface for the whole module (matching the dark
        // diagram canvas), so cards/pills read consistently regardless of app scheme.
        .environment(\.colorScheme, .dark)
        // Cap Dynamic Type so the dense dashboard geometry degrades predictably.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .task { await viewModel.load() }
    }

    private var moduleBackground: some View {
        LinearGradient(
            colors: [Color(red: 0.06, green: 0.08, blue: 0.13), Color(red: 0.03, green: 0.04, blue: 0.08)],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Permissions Helper")
                .font(.largeTitle.bold())
            Text("Look up the Jamf Pro privileges required for Forsetti Jamf Pro actions and API endpoints.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Advisory only — Jamf Pro remains the source of truth for API privileges.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Advisory only. Jamf Pro remains the source of truth for API privileges.")
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch viewModel.selectedSection {
        case .commands:
            PermissionsMatrixCommandExplorerView(viewModel: viewModel)
        case .endpoints:
            PermissionsMatrixEndpointCatalogView(viewModel: viewModel)
        case .privileges:
            PermissionsMatrixPrivilegeCatalogView(viewModel: viewModel)
        case .runtime:
            PermissionsMatrixRuntimeVerificationView(viewModel: viewModel)
        }
    }
}

// MARK: - Metadata bar

/// Compact summary of matrix coverage shown beneath the header.
struct PermissionsMatrixMetadataBar: View {
    @ObservedObject var viewModel: PermissionsMatrixViewModel

    var body: some View {
        let document = viewModel.document
        let summary = viewModel.verificationSummary
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                PHStatTile(title: "Actions", value: count(summary?.actions, fallback: document?.actions.count),
                           systemImage: "command", tint: DashboardColors.bluePrimary)
                PHStatTile(title: "Privileges", value: count(summary?.privileges, fallback: document?.privileges.count),
                           systemImage: "key.fill", tint: Color(red: 0.40, green: 0.82, blue: 0.88))
                PHStatTile(title: "Modern API", value: count(summary?.modernEndpointCatalogEntries, fallback: document?.endpointCatalog.modernJamfProAPI.count),
                           systemImage: "network", tint: Color(red: 0.50, green: 0.66, blue: 1.0))
                PHStatTile(title: "Classic API", value: count(summary?.classicEndpointCatalogEntries, fallback: document?.endpointCatalog.classicAPI.count),
                           systemImage: "building.columns", tint: Color(red: 0.74, green: 0.56, blue: 1.0))
                PHStatTile(title: "MDM overlays", value: count(summary?.mdmCommandTypeOverlays, fallback: document?.endpointCatalog.mdmCommandTypeOverlays.count),
                           systemImage: "plus.rectangle.on.rectangle", tint: Color(red: 0.46, green: 0.64, blue: 1.0))
                if viewModel.uncoveredSourceEndpointCount > 0 {
                    PHStatTile(title: "Uncovered", value: String(viewModel.uncoveredSourceEndpointCount),
                               systemImage: "exclamationmark.triangle.fill", tint: .orange)
                }
            }
            .padding(.vertical, 2)
        }
        // Trailing fade hints at off-screen tiles on narrow (iPhone) widths.
        .mask(
            LinearGradient(stops: [
                .init(color: .black, location: 0.0),
                .init(color: .black, location: 0.93),
                .init(color: .clear, location: 1.0)
            ], startPoint: .leading, endPoint: .trailing)
        )
    }

    private func count(_ value: Int?, fallback: Int?) -> String {
        if let value { return String(value) }
        if let fallback { return String(fallback) }
        return "—"
    }
}

// MARK: - Shared components

/// Renders a structured, actionable error following the module error spec.
struct PermissionsMatrixErrorView: View {
    let error: PermissionsMatrixUserFacingError

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(error.title, systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)

            Text(error.summary)
                .font(.body)

            if error.requiredPrivileges.isEmpty == false {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Likely required Jamf Pro privileges")
                        .font(.caption.weight(.semibold))
                    ForEach(error.requiredPrivileges, id: \.self) { privilege in
                        Text("• \(privilege)").font(.caption.monospaced())
                    }
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                if let endpoint = error.endpoint { detailRow("Endpoint", endpoint) }
                if let cause = error.technicalCause { detailRow("Technical cause", cause) }
                detailRow("Affected system", error.affectedSystem)
                detailRow("Local data changed", error.localDataChanged ? "Yes" : "No")
                detailRow("Jamf data changed", error.jamfDataChanged ? "Yes" : "No")
                detailRow("Safe to retry", error.safeToRetry ? "Yes" : "No")
                detailRow("Diagnostics", "\(error.diagnosticsSource) / \(error.diagnosticsCategory)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(error.recommendedAction)
                .font(.callout.weight(.medium))
                .padding(.top, 2)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.orange.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.orange.opacity(0.4), lineWidth: 1))
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(label + ":").fontWeight(.semibold)
            Text(value).textSelection(.enabled)
        }
    }
}

/// A small premium capsule used to display a privilege or tag.
struct PermissionsMatrixTagChip: View {
    let text: String
    var tint: Color = DashboardColors.bluePrimary

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule(style: .continuous).fill(tint.opacity(0.16)))
            .overlay(Capsule(style: .continuous).strokeBorder(tint.opacity(0.4), lineWidth: 0.75))
    }
}

/// A method+path badge that visibly distinguishes modern vs Classic surfaces, with
/// the HTTP verb color-coded for fast scanning.
struct PermissionsMatrixEndpointBadge: View {
    let method: String
    let path: String
    let isClassic: Bool

    var body: some View {
        HStack(spacing: 7) {
            Text(method.uppercased())
                .font(.caption2.monospaced().weight(.bold))
                .foregroundStyle(methodColor)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(methodColor.opacity(0.16)))
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(methodColor.opacity(0.35), lineWidth: 0.75))
            Text(path)
                .font(.caption.monospaced())
                .foregroundStyle(.primary)
                .textSelection(.enabled)
            PermissionsMatrixTagChip(text: isClassic ? "Classic" : "Modern",
                                     tint: isClassic ? Color(red: 0.74, green: 0.56, blue: 1.0) : DashboardColors.bluePrimary)
        }
    }

    private var methodColor: Color {
        switch method.uppercased() {
        case "GET": return Color(red: 0.50, green: 0.66, blue: 1.0)
        case "POST": return Color(red: 0.40, green: 0.86, blue: 0.58)
        case "PUT", "PATCH": return Color(red: 1.0, green: 0.78, blue: 0.40)
        case "DELETE": return Color(red: 1.0, green: 0.46, blue: 0.46)
        default: return .secondary
        }
    }
}

//endofline
