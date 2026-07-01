import SwiftUI

/// A modal popup that displays a secret credential retrieved from Jamf Pro —
/// a local admin / LAPS password, jssmanage password, recovery-lock password,
/// device-lock PIN, or FileVault recovery key — with a one-tap copy-to-
/// clipboard control.
///
/// Presented via `.sheet(item:)` bound to
/// `SupportTechnicianViewModel.presentedCredential`. The secret reaches this
/// view only; it is never written into the sidebar's result-summary frame or
/// the diagnostics log. The value is shown until the technician dismisses the
/// popup (the credential is cleared on dismiss so it shows once per request).
struct SupportCredentialPopupView: View {
    @Environment(\.dismiss) private var dismiss

    /// The credential to display. Carries the action title and the secret value.
    let credential: SupportCredentialDisplay

    /// Fires when the popup is dismissed so the view model can clear the
    /// presented credential (one-time display).
    let onDismiss: () -> Void

    /// Flips to `true` for a short window after a successful copy so the
    /// button can show a "Copied!" confirmation with a checkmark.
    @State private var didCopy = false

    /// Drives the auto-reset of the "Copied!" confirmation back to "Copy".
    @State private var copyResetTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Form {
                Section("Credential") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(credential.title)
                            .font(.body.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)

                        // The secret value, monospaced and selectable so the
                        // technician can hand-copy if needed. Wraps on long
                        // values rather than truncating.
                        Text(credential.value)
                            .font(.title3.monospaced().weight(.semibold))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            // Distinct surface + border so the value box stays
                            // visible against the grouped-form section
                            // background (which matches `groupedSurface`).
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(DashboardTheme.surface)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(DashboardTheme.border, lineWidth: 1)
                                    )
                            )
                            .accessibilityLabel("Credential value")

                        Button {
                            copyValue()
                        } label: {
                            Label(
                                didCopy ? "Copied!" : "Copy to Clipboard",
                                systemImage: didCopy ? "checkmark.circle.fill" : "doc.on.doc"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.dashboardPrimary)
                        // Matches `SupportTechnicianLayout.controlButtonHeight`
                        // (file-private to the main view) for a comfortable tap target.
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .animation(.easeInOut(duration: 0.15), value: didCopy)
                    }
                    .padding(8)
                }

                Section {
                    Text("This value is shown once. Copy it now if you need it — reopen the command to retrieve it again.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .dashboardGroupedFormStyle()
            .navigationTitle("Password Retrieved")
            .dashboardInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismissPopup()
                    }
                }
            }
            #if os(macOS)
            .frame(
                minWidth: 480,
                idealWidth: 560,
                minHeight: 320,
                idealHeight: 380
            )
            #endif
        }
        .onDisappear {
            copyResetTask?.cancel()
            onDismiss()
        }
    }

    /// Copies the secret to the system clipboard and shows the "Copied!"
    /// confirmation for two seconds before reverting the button label.
    private func copyValue() {
        DashboardClipboard.copy(credential.value)
        didCopy = true
        copyResetTask?.cancel()
        copyResetTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if Task.isCancelled { return }
            didCopy = false
        }
    }

    private func dismissPopup() {
        copyResetTask?.cancel()
        dismiss()
    }
}

//endofline
