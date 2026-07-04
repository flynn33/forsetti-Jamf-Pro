import SwiftUI

// MARK: - Status presentation (pure, testable)

/// Visual tone for the status pill. Mapped to colors in the view so the mapping
/// logic stays free of SwiftUI and is unit-testable.
enum TemporaryAdminStatusTone: Equatable {
    case neutral
    case active
    case success
    case warning
    case danger
}

/// Pure mapping from a `TemporaryAdminElevationState` to display copy. Kept out
/// of the view so layout tests can assert the copy and badges deterministically.
struct TemporaryAdminStatusPresentation: Equatable {
    let title: String
    let description: String
    let badge: String
    let tone: TemporaryAdminStatusTone

    static func make(for state: TemporaryAdminElevationState) -> TemporaryAdminStatusPresentation {
        switch state {
        case .unavailable(let reason):
            return .init(title: "Unavailable", description: reason, badge: "Unavailable", tone: .neutral)
        case .notConfigured(let reason):
            return .init(title: "Not Configured", description: reason, badge: "Not Configured", tone: .warning)
        case .ready:
            return .init(
                title: "Ready",
                description: "This temporarily promotes the currently signed-in Mac user to local administrator.\n\nThe elevation is time-limited and audited. The Mac will remove the user from the local admin group automatically when the timer expires.",
                badge: "Ready",
                tone: .neutral
            )
        case .validating:
            return .init(title: "Validating", description: "Checking the request details.", badge: "Validating", tone: .active)
        case .requesting:
            return .init(title: "Requesting", description: "Adding the Mac to the configured request scope.", badge: "Requesting", tone: .active)
        case .waitingForCheckIn:
            return .init(
                title: "Waiting for Check-in",
                description: "Elevation requested. Waiting for the Mac to check in and run the approved Jamf policy.",
                badge: "Waiting",
                tone: .active
            )
        case .elevated(let user, let expiresAt, _):
            let suffix = expiresAt.map { " until \(Self.timeFormatter.string(from: $0))" } ?? ""
            return .init(
                title: "Elevated",
                description: "Temporary admin is active for \(user)\(suffix).",
                badge: "Elevated",
                tone: .success
            )
        case .alreadyAdmin(let user, _):
            return .init(
                title: "Already Admin",
                description: "The reported console user (\(user)) was already a local administrator. No temporary demotion timer was scheduled by this workflow.",
                badge: "Already Admin",
                tone: .warning
            )
        case .demotionRequested:
            return .init(
                title: "Demotion Requested",
                description: "Demotion requested. Waiting for the Mac to check in and run the demotion policy.",
                badge: "Demoting",
                tone: .active
            )
        case .demoted:
            return .init(title: "Demoted", description: "Temporary admin has ended.", badge: "Demoted", tone: .neutral)
        case .timedOut:
            return .init(
                title: "Timed Out",
                description: "Forsetti Jamf Pro could not confirm that the Mac ran the elevation policy.\n\nNo successful elevation has been confirmed. The Mac may be offline or has not checked in yet.",
                badge: "Timed Out",
                tone: .danger
            )
        case .failed(let message):
            return .init(title: "Failed", description: message, badge: "Failed", tone: .danger)
        case .permissionDenied:
            return .init(
                title: "Permission Required",
                description: "Jamf Pro rejected the request because the current API client does not appear to have permission to update the configured request scope. No Mac permissions were changed.",
                badge: "Permission Required",
                tone: .danger
            )
        case .cleanupWarning(let message, _):
            return .init(title: "Cleanup Warning", description: message, badge: "Cleanup Warning", tone: .warning)
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

// MARK: - Frame

/// The Support Technician frame for Temporary Admin Elevation.
///
/// Shown only for eligible managed Macs; mobile devices never render it. The
/// layout adapts from a two-column card (Mac / iPad landscape) to a single
/// stacked column (iPhone / iPad portrait) via `ViewThatFits`.
struct TemporaryAdminElevationFrame: View {
    @ObservedObject var controller: TemporaryAdminElevationController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Whether the animated "active" pulse should run. Disabled under Reduce
    /// Motion so the feature is fully usable without animation.
    static func countdownAnimationEnabled(reduceMotion: Bool) -> Bool {
        reduceMotion == false
    }

    private var presentation: TemporaryAdminStatusPresentation {
        TemporaryAdminStatusPresentation.make(for: controller.state)
    }

    private var showsControls: Bool {
        controller.configuration.isFullyConfigured && controller.isEligible
    }

    var body: some View {
        CategoryFrame(
            iconSystemName: "person.badge.key.fill",
            title: "Temporary Admin Elevation",
            subtitle: "Mac only · time-limited · audited",
            bodyMaxHeight: 520
        ) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) {
                    statusColumn
                    if showsControls { controlColumn }
                }
                VStack(alignment: .leading, spacing: 16) {
                    statusColumn
                    if showsControls { controlColumn }
                }
            }
            .accessibilityElement(children: .contain)
        }
        .sheet(isPresented: $controller.isConfirmationPresented) {
            TemporaryAdminConfirmationSheet(controller: controller)
        }
        .sheet(isPresented: $controller.isPrivilegesPresented) {
            TemporaryAdminPrivilegesSheet(privileges: controller.requiredPrivileges)
        }
        .alert(item: $controller.userFacingError) { error in
            Alert(
                title: Text(error.title),
                message: Text([error.summary, error.recommendedAction].joined(separator: "\n\n")),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    // MARK: Status column

    private var statusColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusPill
            Text(presentation.title)
                .font(.headline)
            Text(presentation.description)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            detailsGrid

            Button("View Required Privileges") { controller.showRequiredPrivileges() }
                .buttonStyle(.dashboardSecondary)
                .accessibilityLabel("View required Jamf privileges")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Temporary admin status")
    }

    private var statusPill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(toneColor)
                .frame(width: 10, height: 10)
                .opacity(pulse ? 0.45 : 1.0)
                .animation(
                    Self.countdownAnimationEnabled(reduceMotion: reduceMotion) && presentation.tone == .active
                        ? .easeInOut(duration: 0.9).repeatForever(autoreverses: true)
                        : nil,
                    value: pulse
                )
            Text(presentation.badge)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(toneColor.opacity(0.16))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(toneColor.opacity(0.40), lineWidth: 1))
        .onAppear { if presentation.tone == .active { pulse = true } }
        .accessibilityLabel("Status: \(presentation.badge)")
    }

    @State private var pulse = false

    private var detailsGrid: some View {
        VStack(alignment: .leading, spacing: 2) {
            CategoryFieldRow(label: "Selected Mac", value: controller.selectedMacName ?? "—")
            CategoryFieldRow(label: "Serial Number", value: controller.selectedMacSerial ?? "—")
            CategoryFieldRow(label: "Reported Status", value: controller.snapshot?.statusRawValue ?? "Not Reported")
            CategoryFieldRow(label: "Reported User", value: controller.snapshot?.user ?? "—")
            CategoryFieldRow(label: "Expires At", value: formatted(controller.snapshot?.expiresAt))
            CategoryFieldRow(label: "Last Change", value: formatted(controller.snapshot?.lastChange))
            CategoryFieldRow(label: "Mac-side Run ID", value: controller.snapshot?.runId ?? "—")
            CategoryFieldRow(label: "App Request State", value: controller.appRequestStateText)
        }
    }

    // MARK: Control column

    @ViewBuilder
    private var controlColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            durationPicker

            VStack(alignment: .leading, spacing: 4) {
                Text("Reason")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("Why is elevation needed?", text: $controller.reason, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                    .accessibilityLabel("Reason for elevation")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(controller.requiresTicket ? "Ticket / Reference (required)" : "Ticket / Reference")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField(controller.requiresTicket ? "Required" : "Optional", text: $controller.ticketReference)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Ticket reference")
            }

            actionButtons
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var durationPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Duration")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            // Segmented at normal sizes; falls back to a menu at accessibility
            // Dynamic Type sizes where segments would truncate.
            if dynamicTypeSize.isAccessibilitySize {
                Picker("Duration", selection: $controller.selectedDuration) {
                    ForEach(controller.availableDurations) { duration in
                        Text(duration.displayName).tag(duration)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityLabel("Selected duration")
            } else {
                Picker("Duration", selection: $controller.selectedDuration) {
                    ForEach(controller.availableDurations) { duration in
                        Text(duration.displayName).tag(duration)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Selected duration")
            }
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                requestButton
                demoteButton
                refreshButton
            }
            VStack(spacing: 10) {
                requestButton
                demoteButton
                refreshButton
            }
        }
    }

    private var requestButton: some View {
        Button {
            controller.beginRequest()
        } label: {
            Label("Request Temporary Admin", systemImage: "person.badge.key")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.dashboardPrimary)
        .disabled(controller.isRequestEnabled == false)
        .accessibilityLabel("Request temporary admin")
    }

    private var demoteButton: some View {
        Button(role: .destructive) {
            Task { await controller.demoteNow() }
        } label: {
            Label("End Elevation Now", systemImage: "person.badge.minus")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.dashboardSecondary)
        .disabled(controller.isDemoteEnabled == false)
        .accessibilityLabel("End temporary admin now")
    }

    private var refreshButton: some View {
        Button {
            Task { await controller.refresh() }
        } label: {
            Label("Refresh Status", systemImage: "arrow.clockwise")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.dashboardSecondary)
        .disabled(controller.isBusy)
        .accessibilityLabel("Refresh temporary admin status")
    }

    // MARK: Helpers

    private var toneColor: Color {
        switch presentation.tone {
        case .neutral: return .secondary
        case .active: return DashboardColors.bluePrimary
        case .success: return DashboardColors.greenPrimary
        case .warning: return .orange
        case .danger: return .red
        }
    }

    private func formatted(_ date: Date?) -> String {
        guard let date else { return "—" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Confirmation sheet

private struct TemporaryAdminConfirmationSheet: View {
    @ObservedObject var controller: TemporaryAdminElevationController
    @Environment(\.dismiss) private var dismiss

    private let requiredPhrase = "confirm"

    private var canConfirm: Bool {
        controller.confirmationText.trimmingCharacters(in: .whitespacesAndNewlines) == requiredPhrase
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Confirm temporary admin request") {
                    Text("This will request temporary local administrator rights for the currently signed-in Mac user.\n\nThe Mac must check in with Jamf Pro before the policy can run. This action does not elevate a typed username and does not change Jamf Pro privileges.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Section("Details") {
                    CategoryFieldRow(label: "Selected Mac", value: controller.selectedMacName ?? "—")
                    CategoryFieldRow(label: "Serial Number", value: controller.selectedMacSerial ?? "—")
                    CategoryFieldRow(label: "Duration", value: controller.selectedDuration.displayName)
                    CategoryFieldRow(label: "Reason", value: controller.reason)
                    CategoryFieldRow(label: "Ticket / Reference", value: controller.ticketReference)
                }

                Section("Required Jamf privileges") {
                    ForEach(controller.requiredPrivileges, id: \.self) { privilege in
                        Text(privilege).font(.footnote)
                    }
                }

                Section {
                    HStack(spacing: 6) {
                        Text("Type")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text("\"\(requiredPhrase)\"")
                            .font(.footnote.monospaced().weight(.semibold))
                        Text("to enable.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    TextField(requiredPhrase, text: $controller.confirmationText)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())

                    Button("Request Temporary Admin") {
                        dismiss()
                        Task { await controller.confirmRequest() }
                    }
                    .disabled(canConfirm == false)

                    Button("Cancel", role: .cancel) {
                        controller.isConfirmationPresented = false
                        dismiss()
                    }
                }
            }
            .dashboardGroupedFormStyle()
            .navigationTitle("Confirm Request")
            #if os(macOS)
            .frame(minWidth: 520, idealWidth: 600, minHeight: 420, idealHeight: 520)
            #endif
        }
        .interactiveDismissDisabled(false)
    }
}

// MARK: - Privileges sheet

private struct TemporaryAdminPrivilegesSheet: View {
    let privileges: [String]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Normal-use Jamf privileges") {
                    ForEach(privileges, id: \.self) { privilege in
                        Text(privilege).font(.footnote)
                    }
                }
                Section("This feature does not grant") {
                    ForEach(["Jamf Pro privileges", "Secure Token", "Bootstrap Token", "FileVault recovery access", "local account password access"], id: \.self) { item in
                        Text(item).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .dashboardGroupedFormStyle()
            .navigationTitle("Required Privileges")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            #if os(macOS)
            .frame(minWidth: 480, idealWidth: 560, minHeight: 380, idealHeight: 460)
            #endif
        }
    }
}
