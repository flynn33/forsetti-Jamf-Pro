import SwiftUI

/// Optional runtime verification: compare the selected action's required
/// privileges against the current Jamf Pro token. Never required for static
/// browsing; degrades gracefully when not connected.
struct PermissionsMatrixRuntimeVerificationView: View {
    @ObservedObject var viewModel: PermissionsMatrixViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PHMetrics.gap) {
                disclaimer
                statusCard
                if let result = viewModel.comparisonResult, result.userFacingError == nil {
                    comparisonOutput(result)
                }
                if let error = viewModel.comparisonResult?.userFacingError {
                    PermissionsMatrixErrorView(error: error)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var disclaimer: some View {
        Label("This comparison is advisory. Jamf Pro remains the source of truth for API privileges.",
              systemImage: "info.circle.fill")
            .font(.callout)
            .foregroundStyle(.secondary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(DashboardColors.bluePrimary.opacity(0.10)))
            .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(DashboardColors.bluePrimary.opacity(0.30), lineWidth: 1))
    }

    @ViewBuilder
    private var statusCard: some View {
        PHSectionCard(title: "Runtime token comparison", systemImage: "checkmark.shield") {
            VStack(alignment: .leading, spacing: 12) {
                if let action = viewModel.selectedAction {
                    HStack(spacing: 6) {
                        Image(systemName: "command").font(.caption).foregroundStyle(.secondary)
                        Text(action.resolvedDisplayName).font(.subheadline.weight(.semibold))
                    }
                } else {
                    Text("No action selected").font(.subheadline.weight(.semibold))
                    Text("Open the Commands tab and select an action, then return here to compare it against your live Jamf Pro token.")
                        .font(.callout).foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    statePill
                    Spacer()
                    Button {
                        Task { await viewModel.runComparison() }
                    } label: {
                        if isChecking {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Compare with live token", systemImage: "checkmark.shield")
                        }
                    }
                    .buttonStyle(.dashboardPrimary)
                    .disabled(viewModel.selectedAction == nil || viewModel.hasCredentials == false || isChecking)
                }

                if viewModel.hasCredentials == false {
                    Text("Connect to Jamf Pro (save verified credentials in Settings) or enable App Store Demo Mode to compare privileges.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var isChecking: Bool {
        viewModel.runtimeState == .checkingAuth || viewModel.runtimeState == .checkingPrivilegeCatalog
    }

    private var statePill: some View {
        let (text, symbol, tint) = stateLabel
        return PHStatusPill(text: text, systemImage: symbol, tint: tint)
    }

    private var stateLabel: (String, String, Color) {
        switch viewModel.runtimeState {
        case .notAuthenticated: return ("Not connected", "wifi.slash", .gray)
        case .readyToCheck: return ("Ready", "circle", DashboardColors.bluePrimary)
        case .checkingAuth: return ("Checking token…", "ellipsis.circle", DashboardColors.bluePrimary)
        case .checkingPrivilegeCatalog: return ("Checking catalog…", "ellipsis.circle", DashboardColors.bluePrimary)
        case .missingReadApiRoles: return ("Read API Roles missing", "exclamationmark.triangle.fill", .orange)
        case .comparisonComplete: return ("Comparison complete", "checkmark.circle.fill", Color(red: 0.40, green: 0.86, blue: 0.58))
        case .comparisonUnavailable: return ("Select an action", "hand.tap", .gray)
        case .comparisonFailed: return ("Comparison failed", "xmark.octagon.fill", Color(red: 1.0, green: 0.46, blue: 0.46))
        }
    }

    @ViewBuilder
    private func comparisonOutput(_ result: PermissionsMatrixComparisonResult) -> some View {
        PHSectionCard(title: "Comparison result", systemImage: "list.bullet.clipboard") {
            VStack(alignment: .leading, spacing: 14) {
                Text("Compared against \(result.tokenPrivilegeCount) privilege(s) on the current Jamf Pro token.")
                    .font(.caption).foregroundStyle(.secondary)

                if result.apiRoleCatalogAvailable == false {
                    Label("Live API role catalog could not be read. \"Read API Roles\" may be missing — the static matrix is still authoritative for required privileges.",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                }

                privilegeBucket(
                    title: "Confirmed present",
                    systemImage: "checkmark.circle.fill",
                    tint: Color(red: 0.40, green: 0.86, blue: 0.58),
                    privileges: result.confirmedPresent,
                    emptyText: "None of the required privileges were confirmed on the current token."
                )
                privilegeBucket(
                    title: "Not confirmed by current token / API role data",
                    systemImage: "questionmark.circle.fill",
                    tint: .orange,
                    privileges: result.notConfirmed,
                    emptyText: "All required privileges were confirmed."
                )
                if result.alternativesNotPresent.isEmpty == false {
                    privilegeBucket(
                        title: "Optional / alternative privileges (any may apply)",
                        systemImage: "circle.dashed",
                        tint: .gray,
                        privileges: result.alternativesNotPresent,
                        emptyText: ""
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func privilegeBucket(title: String, systemImage: String, tint: Color, privileges: [String], emptyText: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("\(title) (\(privileges.count))", systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(tint)
            if privileges.isEmpty {
                if emptyText.isEmpty == false {
                    Text(emptyText).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                ForEach(privileges, id: \.self) { privilege in
                    HStack(alignment: .top, spacing: 7) {
                        Image(systemName: "key.fill").font(.caption2).foregroundStyle(tint.opacity(0.8))
                        Text(privilege).font(.callout).textSelection(.enabled)
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }
}
