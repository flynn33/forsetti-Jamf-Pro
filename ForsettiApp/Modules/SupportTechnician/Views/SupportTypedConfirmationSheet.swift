import SwiftUI

/// A modal confirmation sheet for destructive MDM commands that requires the
/// technician to type a confirmation phrase (e.g. "confirm") before the
/// Confirm button enables.
///
/// Generalised from the prior `SupportTypedRemovalConfirmationSheet` so the
/// same component governs every destructive action — Erase, Restart,
/// Shutdown, Lock, Log Out, Clear Passcode, Rotate LAPS, Remote Management.
/// The required word is supplied by `SupportManagementAction.requiredTypedPhrase`
/// (defaults to `"confirm"` across the board).
///
/// Match is case-sensitive on the trimmed input — typing "Confirm" or
/// "  confirm  " do **not** unlock the button; only an exact match to
/// `requiredPhrase` does.
struct SupportTypedConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// The destructive action awaiting typed confirmation.
    let action: SupportManagementAction

    /// The phrase the technician must type into the input field. Driven by
    /// `action.requiredTypedPhrase` in normal flows; passed explicitly so
    /// the sheet can be reused for non-action confirmations later if needed.
    let requiredPhrase: String

    /// Bound text input.
    @Binding var confirmationText: String

    /// Optional account name surfaced in the confirmation copy. Used by
    /// the per-row password reset flow in the User Accounts frame so
    /// the sheet says "You are about to rotate the password for
    /// jim.daley" instead of just "You are about to run Rotate LAPS
    /// Password." `nil` for normal destructive-action confirmations.
    let accountName: String?

    /// Fires when the technician cancels (button or close).
    let onCancel: () -> Void

    /// Fires when the technician confirms by typing the required phrase
    /// exactly and tapping Confirm.
    let onConfirm: () -> Void

    /// Backwards-compatible initializer — keeps every existing
    /// destructive-action call site unchanged. The `accountName`
    /// parameter is opt-in for callers that want per-account context
    /// (the per-row password reset path in the User Accounts frame).
    init(
        action: SupportManagementAction,
        requiredPhrase: String,
        confirmationText: Binding<String>,
        accountName: String? = nil,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping () -> Void
    ) {
        self.action = action
        self.requiredPhrase = requiredPhrase
        self._confirmationText = confirmationText
        self.accountName = accountName
        self.onCancel = onCancel
        self.onConfirm = onConfirm
    }

    /// `true` only when the trimmed typed text equals the required phrase.
    private var canConfirm: Bool {
        confirmationText.trimmingCharacters(in: .whitespacesAndNewlines) == requiredPhrase
    }

    /// The summary line shown at the top of the confirmation form. Per-
    /// account flows (password reset) replace the generic "You are about
    /// to run <action>" with "You are about to rotate the password for
    /// <account>." so the technician sees which user they're targeting.
    private var primaryPrompt: String {
        if let accountName, accountName.isEmpty == false {
            return "You are about to rotate the password for \"\(accountName)\"."
        }
        return "You are about to run \(action.title)."
    }

    /// The supporting body copy under the primary prompt. Per-account
    /// flows get a short explainer about the rotate behaviour; normal
    /// destructive-action flows use the action's `confirmationMessage`.
    private var secondaryPrompt: String {
        if let accountName, accountName.isEmpty == false {
            return "Jamf Pro will generate a new password for the \"\(accountName)\" account via the Local Admin Password (LAPS) feature, then push it to the device at next check-in. The new password is shown once after the rotate request returns. Only works for accounts registered with Jamf's LAPS feature; non-LAPS accounts return an error."
        }
        return action.confirmationMessage
    }

    /// The Confirm button label. Per-account flows say "Reset Password
    /// for <account>" instead of "Confirm <action.title>" so the
    /// destructive button names the target user the technician is
    /// rotating, not the generic action it's reusing internally.
    private var confirmButtonLabel: String {
        if let accountName, accountName.isEmpty == false {
            return "Reset Password for \(accountName)"
        }
        return "Confirm \(action.title)"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Confirmation required") {
                    // Wrap the prompt + body + hint + textfield in a
                    // single VStack with explicit spacing so the rows
                    // don't crunch against each other and against the
                    // section edges. Symmetric padding on all four
                    // sides — equal horizontal and vertical breathing
                    // room beyond the Form's default cell padding so
                    // the text isn't pushed against the left/right
                    // edges while having open space above/below.
                    VStack(alignment: .leading, spacing: 12) {
                        Text(primaryPrompt)
                            .font(.body.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)

                        Text(secondaryPrompt)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 6) {
                            Text("Type")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            Text("\"\(requiredPhrase)\"")
                                .font(.footnote.monospaced().weight(.semibold))
                            Text("to enable Confirm.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 4)

                        TextField(requiredPhrase, text: $confirmationText)
                            .textFieldStyle(.roundedBorder)
                            .autocorrectionDisabled()
                            .font(.body.monospaced())
                    }
                    .padding(8)
                }

                Section {
                    Button(confirmButtonLabel, role: .destructive) {
                        guard canConfirm else { return }
                        onConfirm()
                        dismiss()
                    }
                    .disabled(canConfirm == false)
                    .padding(.vertical, 2)

                    Button("Back", role: .cancel) {
                        onCancel()
                        dismiss()
                    }
                    .padding(.vertical, 2)
                }
            }
            .forsettiInsetGroupedListStyle()
            .navigationTitle("Type to confirm")
            .forsettiInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        onCancel()
                        dismiss()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                }
            }
            // macOS sheets default to a very small frame; without an
            // explicit minimum size the prompts wrap mid-sentence and
            // the text field is jammed against the section edges. The
            // sizes below match the smaller-modal convention used
            // elsewhere in the project (see
            // `SupportFrames.swift:481` for the same pattern on the
            // Application Manager sheet).
            #if os(macOS)
            .frame(
                minWidth: 520,
                idealWidth: 600,
                minHeight: 380,
                idealHeight: 460
            )
            #endif
        }
        .interactiveDismissDisabled(canConfirm == false)
    }
}

//endofline
