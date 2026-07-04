import SwiftUI

/// Dedicated Apple-native Remote Support frame for the selected Mac in Support Technician.
///
/// Renders eligibility, connection target, state-aware controls (each with a disabled reason),
/// operational guidance, and a diagnostics summary. Controls are driven entirely by the
/// `SupportRemoteSupportController` state — queueing never opens Screen Sharing, and the
/// `vnc://` launch only fires from the explicit Open control once the state reaches Ready to
/// Open. Uses the existing `CategoryFrame` chrome (no new visual language), adapts between a
/// two-column and a single-column layout to fit the available width, and is intentionally
/// static (no required motion) so Reduce Motion needs no special fallback.
struct SupportRemoteSupportFrame: View {
    @ObservedObject var controller: SupportRemoteSupportController

    /// The frame conveys state entirely through static text/pills/fields — no animation is
    /// required to understand it, so Reduce Motion needs no special fallback.
    static var usesRequiredMotion: Bool { false }

    var body: some View {
        CategoryFrame(
            iconSystemName: "display",
            title: "Remote Support",
            subtitle: "Apple Screen Sharing / Remote Management",
            bodyMaxHeight: 900
        ) {
            VStack(alignment: .leading, spacing: 16) {
                statusRow

                ViewThatFits(in: .horizontal) {
                    // Two columns when there is room (iPad landscape / Mac Catalyst).
                    HStack(alignment: .top, spacing: 20) {
                        VStack(alignment: .leading, spacing: 16) {
                            eligibilitySection
                            targetSection
                        }
                        .frame(minWidth: 300, maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .leading, spacing: 16) {
                            actionsSection
                            guidanceSection
                            diagnosticsSummarySection
                        }
                        .frame(minWidth: 300, maxWidth: .infinity, alignment: .leading)
                    }

                    // Single column (iPhone / iPad portrait / narrow split).
                    VStack(alignment: .leading, spacing: 16) {
                        eligibilitySection
                        targetSection
                        actionsSection
                        guidanceSection
                        diagnosticsSummarySection
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Status

    private var statusRow: some View {
        HStack(spacing: 8) {
            Text(pillText)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(statusColor.opacity(0.18), in: Capsule())
                .foregroundStyle(statusColor)
            if controller.state.isBusy || controller.isCheckingReadiness {
                ProgressView().controlSize(.small)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Remote Support status")
        .accessibilityValue(controller.state.headline)
    }

    // MARK: - Eligibility

    @ViewBuilder
    private var eligibilitySection: some View {
        sectionCard(title: "Eligibility") {
            CategoryFieldRow(label: "Device", value: controller.session?.displayName ?? "—")
            CategoryFieldRow(label: "Type", value: "Mac")
            CategoryFieldRow(label: "Management ID", value: managementIDStatus)
            CategoryFieldRow(label: "Workflow state", value: controller.state.headline)
            CategoryFieldRow(label: "Required privilege", value: "Send Computer Remote Desktop Command")

            if let report = controller.readinessReport {
                CategoryFieldRow(label: "Command status", value: report.commandReadiness.label)
                CategoryFieldRow(label: "Reachability", value: report.reachability.label)
                Text(report.summary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Readiness summary")
                    .accessibilityValue(report.summary)
            }
        }
    }

    private var managementIDStatus: String {
        if let id = controller.session?.managementID, id.isEmpty == false { return "Present" }
        return "Missing"
    }

    // MARK: - Target

    @ViewBuilder
    private var targetSection: some View {
        sectionCard(title: "Connection target") {
            if let target = controller.resolvedTarget {
                CategoryFieldRow(label: "Target", value: target.host)
                CategoryFieldRow(label: "Source", value: target.source.label)
                CategoryFieldRow(label: "Confidence", value: target.confidence.label)
            } else {
                CategoryFieldRow(label: "Target", value: "Unavailable")
                Text(controller.state.target == nil
                     ? "No usable target resolved from inventory. Enter a hostname or IP below."
                     : "—")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                TextField("Hostname or IP override", text: $controller.manualTargetOverride)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Connection target override")
                Button("Apply") { controller.applyTargetOverride() }
                    .buttonStyle(.dashboardSecondary)
                    .frame(minHeight: 44)
                    .disabled(controller.manualTargetOverride.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityLabel("Apply connection target override")
            }

            Button {
                controller.copyConnectionTarget()
            } label: {
                Label("Copy Target", systemImage: "doc.on.doc")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(.dashboardSecondary)
            .frame(minHeight: 44)
            .disabled(controller.resolvedTarget == nil)
            .accessibilityLabel("Copy connection target")
            .accessibilityHint(controller.resolvedTarget == nil ? "No target to copy yet." : "")
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private var actionsSection: some View {
        sectionCard(title: "Actions") {
            actionControl(
                "Enable Remote Management",
                systemImage: "display",
                isEnabled: controller.state.allowsEnable,
                disabledReason: enableDisabledReason,
                role: .primary
            ) { controller.enableRemoteManagement() }

            actionControl(
                "Check Readiness",
                systemImage: "checkmark.seal",
                isEnabled: checkReadinessEnabled && controller.isCheckingReadiness == false,
                disabledReason: controller.isCheckingReadiness
                    ? "Checking readiness…"
                    : "Available after the enable command is queued."
            ) { controller.checkReadiness() }

            actionControl(
                "Open Screen Sharing",
                systemImage: "arrow.up.forward.app",
                isEnabled: controller.state.canOpenScreenSharing,
                disabledReason: "Available once the Mac is ready and a connection target is resolved.",
                role: .primary
            ) { controller.openScreenSharing() }

            actionControl(
                "Disable Remote Management",
                systemImage: "display.trianglebadge.exclamationmark",
                isEnabled: controller.state.allowsDisable,
                disabledReason: "Available after a session is launched, if cleanup is required.",
                role: .danger
            ) { controller.disableRemoteManagement() }

            if controller.state.allowsRetry {
                actionControl("Retry", systemImage: "arrow.clockwise", isEnabled: true, disabledReason: nil) {
                    controller.retry()
                }
            }
        }
    }

    private var enableDisabledReason: String {
        switch controller.state {
        case .needsManagementID: return "A Jamf management ID is required."
        case .unsupported:       return "Remote Support is available for Macs only."
        default:                 return "Already enabled or in progress."
        }
    }

    private var checkReadinessEnabled: Bool {
        switch controller.state {
        case .queuedWaitingForCheckIn, .readinessUnknown: return true
        default: return false
        }
    }

    // MARK: - Guidance

    @ViewBuilder
    private var guidanceSection: some View {
        sectionCard(title: "Guidance") {
            guidanceLine("Jamf queued the command; the Mac must check in before Remote Management changes.")
            guidanceLine("If the connection target doesn’t resolve, use the last-known IP or ask the user to connect VPN.")
            guidanceLine("Disable Remote Management when temporary access is complete if tenant policy requires cleanup.")
        }
    }

    private func guidanceLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle").font(.caption2).foregroundStyle(.secondary)
            Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Diagnostics summary

    @ViewBuilder
    private var diagnosticsSummarySection: some View {
        sectionCard(title: "Diagnostics") {
            if case let .failed(failure) = controller.state {
                Text(failure.summary).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                if let privilege = failure.requiredPrivilege {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Required Jamf privilege:")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(privilege)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Required Jamf privilege")
                    .accessibilityValue(privilege)
                }
                Text(failure.recommendation).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Remote Support events are recorded in Diagnostics.").font(.caption).foregroundStyle(.secondary)
            }
            Button {
                controller.viewDiagnostics()
            } label: {
                Label("View Diagnostics", systemImage: "stethoscope")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(.dashboardSecondary)
            .frame(minHeight: 44)
            .accessibilityLabel("View diagnostics")
        }
    }

    // MARK: - Building blocks

    private enum ControlRole { case primary, secondary, danger }

    @ViewBuilder
    private func actionControl(
        _ title: String,
        systemImage: String,
        isEnabled: Bool,
        disabledReason: String?,
        role: ControlRole = .secondary,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            let label = Label(title, systemImage: systemImage).frame(maxWidth: .infinity, alignment: .center)
            Group {
                switch role {
                case .primary:   Button(action: action) { label }.buttonStyle(.dashboardPrimary)
                case .secondary: Button(action: action) { label }.buttonStyle(.dashboardSecondary)
                case .danger:    Button(action: action) { label }.buttonStyle(.dashboardDanger)
                }
            }
            .frame(minHeight: 44)
            .disabled(isEnabled == false)
            .accessibilityLabel(title)
            .accessibilityHint(isEnabled ? "" : (disabledReason ?? ""))

            if isEnabled == false, let disabledReason {
                Text(disabledReason).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            content()
        }
    }

    // MARK: - Status presentation

    private var presentation: SupportRemoteSupportStatusPresentation {
        SupportRemoteSupportStatusPresentation.make(for: controller.state)
    }

    private var pillText: String { presentation.badge }

    private var statusColor: Color {
        switch presentation.tone {
        case .success: return DashboardColors.greenPrimary
        case .active:  return .orange
        case .danger:  return .red
        case .neutral: return .secondary
        }
    }
}

//endofline
