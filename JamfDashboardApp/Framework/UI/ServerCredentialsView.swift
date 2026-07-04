import SwiftUI

/// A form-based view for entering, verifying, and saving Jamf Pro server credentials.
/// Supports two authentication methods: API Client (client ID + secret) and
/// username/password. The user must successfully verify the connection before
/// credentials can be saved to the Keychain. Diagnostic events are reported
/// for verification successes, failures, saves, and clears.
struct ServerCredentialsView: View {
    /// Dismiss action to close or pop this view.
    @Environment(\.dismiss) private var dismiss

    /// Drives the auth-method picker style: a segmented control truncates the
    /// long "Username & Password" label at accessibility text sizes, so we fall
    /// back to a menu picker (which shows full labels) at those sizes.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The shared credentials store used to load, save, and clear Jamf credentials.
    @ObservedObject var credentialsStore: JamfCredentialsStore
    /// Optional diagnostics reporter for logging credential-related events.
    let diagnosticsReporter: (any DiagnosticsReporting)?

    /// The Jamf Pro server URL entered by the user.
    @State private var serverURL = ""
    /// The currently selected authentication method (API client or username/password).
    @State private var authenticationMethod = JamfCredentials.AuthenticationMethod.apiClient
    /// The API client ID (used when authenticationMethod is `.apiClient`).
    @State private var clientID = ""
    /// The API client secret (used when authenticationMethod is `.apiClient`).
    @State private var clientSecret = ""
    /// The Jamf account username (used when authenticationMethod is `.usernamePassword`).
    @State private var accountUsername = ""
    /// The Jamf account password (used when authenticationMethod is `.usernamePassword`).
    @State private var accountPassword = ""
    /// Whether a verification request is currently in flight.
    @State private var isVerifyingConnection = false
    /// Whether the most recent verification attempt succeeded, enabling the Save button.
    @State private var isConnectionVerified = false

    /// An error message displayed when verification or save fails.
    @State private var errorMessage: String?
    /// A success/status message displayed after successful operations.
    @State private var statusMessage: String?

    /// A composite string built from the current form inputs. When this value changes,
    /// the verification state is automatically reset so the user must re-verify
    /// after editing any credential field.
    private var verificationInputSignature: String {
        switch authenticationMethod {
        case .apiClient:
            return [
                authenticationMethod.rawValue,
                serverURL.trimmingCharacters(in: .whitespacesAndNewlines),
                clientID.trimmingCharacters(in: .whitespacesAndNewlines),
                clientSecret
            ].joined(separator: "|")
        case .usernamePassword:
            return [
                authenticationMethod.rawValue,
                serverURL.trimmingCharacters(in: .whitespacesAndNewlines),
                accountUsername.trimmingCharacters(in: .whitespacesAndNewlines),
                accountPassword
            ].joined(separator: "|")
        }
    }

    /// Whether the form has enough data filled in to attempt a verification request.
    private var canVerifyConnection: Bool {
        credentialsForFormState().isComplete
    }

    var body: some View {
        // Deterministic, hand-authored layout instead of a macOS `Form`.
        // macOS `Form` rows render the field's label in a fixed-width leading
        // column; a long label/value (the Jamf URL) was clipped against the
        // window edge — the "text running into the side" the user reported,
        // and the sheet's width was unpredictable. Here every field is a label
        // *above* a full-width `.roundedBorder` field, inside a centered,
        // width-capped card, so the layout is identical and never clips on
        // either platform regardless of how the OS sizes the sheet.
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                credentialSection("Jamf Server") {
                    labeledField("Server URL") {
                        // Short label sits above; the long example URL lives in
                        // `prompt:` inside the field where there is room.
                        TextField("", text: $serverURL, prompt: Text("https://company.jamfcloud.com"))
                            .textFieldStyle(.roundedBorder)
                            .dashboardURLKeyboard()
                            .dashboardNoAutoCorrectionTextInput()
                    }
                }

                credentialSection("Authentication Method") {
                    Group {
                        if dynamicTypeSize.isAccessibilitySize {
                            authenticationMethodPicker.pickerStyle(.menu)
                        } else {
                            authenticationMethodPicker.pickerStyle(.segmented)
                        }
                    }
                    .labelsHidden()

                    Text("Choose one method. Only the selected method is used and stored.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Credential fields for the selected method
                if authenticationMethod == .apiClient {
                    credentialSection("Jamf API Client") {
                        labeledField("Client ID") {
                            TextField("", text: $clientID, prompt: Text("Client ID"))
                                .textFieldStyle(.roundedBorder)
                                .dashboardNoAutoCorrectionTextInput()
                        }
                        labeledField("Client Secret") {
                            SecureField("", text: $clientSecret, prompt: Text("Client Secret"))
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                } else {
                    credentialSection("Jamf Account") {
                        labeledField("Username") {
                            TextField("", text: $accountUsername, prompt: Text("Username"))
                                .textFieldStyle(.roundedBorder)
                                .dashboardNoAutoCorrectionTextInput()
                        }
                        labeledField("Password") {
                            SecureField("", text: $accountPassword, prompt: Text("Password"))
                                .textFieldStyle(.roundedBorder)
                        }

                        // M4: Deprecation notice per Jamf Pro 11.17.0 changes
                        Text("Note: Username/password authentication is deprecated in Jamf Pro 11.17.0+. Consider switching to API Client credentials for long-term compatibility.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // Actions
                VStack(spacing: 10) {
                    Button {
                        Task {
                            await verifyConnection()
                        }
                    } label: {
                        Group {
                            if isVerifyingConnection {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text("Verifying Connection...")
                                }
                            } else {
                                Text("Verify Connection")
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.dashboardSecondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .disabled(canVerifyConnection == false || isVerifyingConnection)

                    Button {
                        saveCredentials()
                    } label: {
                        Text("Save Credentials")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.dashboardPrimary)
                    // Save is only enabled after a successful verification
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .disabled(isConnectionVerified == false || isVerifyingConnection)

                    Button(role: .destructive) {
                        clearCredentials()
                    } label: {
                        Text("Clear Stored Credentials")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.dashboardDanger)
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .padding(.top, 4)

                // Status / error feedback — full-width wrapping text
                if let statusMessage {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(DashboardTheme.successText)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .dashboardCardSurface()
            // Cap the content column so it never stretches edge-to-edge on a
            // wide macOS sheet, then center it within the sheet width.
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        // Restores the interactive swipe-to-dismiss-keyboard behavior a grouped
        // Form gave for free; without it the action buttons can sit behind the
        // keyboard with no easy way to reveal them. No-op on macOS.
        .scrollDismissesKeyboard(.interactively)
        .dashboardAppBackground()
        .navigationTitle("Server Credentials")
        .dashboardInlineNavigationTitle()
        .onChange(of: verificationInputSignature) { _, _ in
            // Any change to credential fields invalidates the previous verification
            resetVerificationStateForInputChange()
        }
        // No custom back button — this view is pushed via NavigationLink from
        // SettingsView, so the enclosing NavigationStack supplies the system
        // back chevron. Adding one here creates the duplicate back buttons the
        // user reported.
        .task {
            // Pre-populate the form with existing saved credentials, if any
            loadExistingCredentialsIfPresent()
        }
    }

    /// The auth-method picker without a style applied, so the caller can pick
    /// `.segmented` (default) or `.menu` (accessibility text sizes).
    private var authenticationMethodPicker: some View {
        Picker("", selection: $authenticationMethod) {
            ForEach(JamfCredentials.AuthenticationMethod.allCases, id: \.self) { method in
                Text(method.displayName).tag(method)
            }
        }
    }

    /// A titled group of related credential controls. The title is a plain
    /// full-width `Text` (not a macOS `Form` section header), so it renders
    /// identically on iOS and macOS and never collides with a label column.
    @ViewBuilder
    private func credentialSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            content()
        }
    }

    /// A single input rendered as a label *above* a full-width field — the
    /// deterministic alternative to a macOS `Form` row's leading-label column,
    /// which clips long labels/values against the window edge.
    @ViewBuilder
    private func labeledField<Content: View>(
        _ title: String,
        @ViewBuilder field: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            field()
        }
    }

    // "A robot may not injure a human being or, through inaction, allow a human being to come to harm.
    //  A robot must obey the orders given it by human beings except where such orders would conflict with the First Law.
    //  A robot must protect its own existence as long as such protection does not conflict with the First or Second Law."

    /// Loads previously saved credentials from the store and populates all form fields.
    /// Resets the verification flag so the user must re-verify before saving changes.
    private func loadExistingCredentialsIfPresent() {
        guard let credentials = try? credentialsStore.loadCredentials() else {
            return
        }

        serverURL = credentials.serverURL
        authenticationMethod = credentials.authenticationMethod
        clientID = credentials.clientID
        clientSecret = credentials.clientSecret
        accountUsername = credentials.accountUsername
        accountPassword = credentials.accountPassword
        isConnectionVerified = false
    }

    /// Builds a `JamfCredentials` value from the current form state, zeroing out
    /// fields that do not belong to the selected authentication method.
    /// - Returns: A `JamfCredentials` reflecting the current form inputs.
    private func credentialsForFormState() -> JamfCredentials {
        switch authenticationMethod {
        case .apiClient:
            return JamfCredentials(
                serverURL: serverURL,
                authenticationMethod: .apiClient,
                clientID: clientID,
                clientSecret: clientSecret,
                accountUsername: "",
                accountPassword: ""
            )
        case .usernamePassword:
            return JamfCredentials(
                serverURL: serverURL,
                authenticationMethod: .usernamePassword,
                clientID: "",
                clientSecret: "",
                accountUsername: accountUsername,
                accountPassword: accountPassword
            )
        }
    }

    /// Attempts to obtain an access token from the Jamf Pro server using the current
    /// form credentials. On success, enables the Save button and reports a diagnostic event.
    /// On failure, displays the error and reports a diagnostic error.
    @MainActor
    private func verifyConnection() async {
        guard canVerifyConnection else {
            statusMessage = nil
            errorMessage = "Complete the server URL and selected login fields to verify."
            isConnectionVerified = false
            return
        }

        isVerifyingConnection = true
        isConnectionVerified = false
        statusMessage = nil
        errorMessage = nil

        let credentials = credentialsForFormState()
        let authenticationService = JamfAuthenticationService(diagnosticsReporter: diagnosticsReporter)

        do {
            // Attempt to fetch an access token -- this validates the server URL and credentials
            _ = try await authenticationService.accessToken(for: credentials)
            isConnectionVerified = true
            statusMessage = "Connection verified. You can now save credentials."
            errorMessage = nil

            await diagnosticsReporter?.report(
                source: "framework.credentials",
                category: "verification",
                severity: .info,
                message: "Jamf credential verification succeeded.",
                metadata: [
                    "auth_method": credentials.authenticationMethod.rawValue
                ]
            )
        } catch {
            isConnectionVerified = false
            statusMessage = nil
            let description = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            errorMessage = description

            await diagnosticsReporter?.reportError(
                source: "framework.credentials",
                category: "verification",
                message: "Jamf credential verification failed.",
                errorDescription: description,
                metadata: [
                    "auth_method": credentials.authenticationMethod.rawValue
                ]
            )
        }

        isVerifyingConnection = false
    }

    /// Saves the current form credentials to the Keychain via the credentials store.
    /// Requires that `isConnectionVerified` is true. Reports the outcome as a diagnostic event.
    private func saveCredentials() {
        guard isConnectionVerified else {
            statusMessage = nil
            errorMessage = "Verify the connection before saving credentials."
            return
        }

        do {
            let credentials = credentialsForFormState()

            try credentialsStore.saveCredentials(credentials)
            statusMessage = "Credentials saved securely in Keychain."
            errorMessage = nil

            Task {
                await diagnosticsReporter?.report(
                    source: "framework.credentials",
                    category: "credentials",
                    severity: .info,
                    message: "Jamf credentials saved to Keychain.",
                    metadata: [:]
                )
            }
        } catch {
            statusMessage = nil
            let description = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            errorMessage = description

            Task {
                await diagnosticsReporter?.reportError(
                    source: "framework.credentials",
                    category: "credentials",
                    message: "Failed to save Jamf credentials.",
                    errorDescription: description
                )
            }
        }
    }

    /// Removes all stored credentials from the Keychain and resets the form to its default state.
    /// Reports the outcome as a diagnostic event with warning severity.
    private func clearCredentials() {
        do {
            try credentialsStore.clearCredentials()
            statusMessage = "Stored credentials removed."
            errorMessage = nil
            // Reset all form fields to blank defaults
            serverURL = ""
            authenticationMethod = .apiClient
            clientID = ""
            clientSecret = ""
            accountUsername = ""
            accountPassword = ""
            isConnectionVerified = false

            Task {
                await diagnosticsReporter?.report(
                    source: "framework.credentials",
                    category: "credentials",
                    severity: .warning,
                    message: "Stored Jamf credentials were cleared.",
                    metadata: [:]
                )
            }
        } catch {
            statusMessage = nil
            let description = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            errorMessage = description

            Task {
                await diagnosticsReporter?.reportError(
                    source: "framework.credentials",
                    category: "credentials",
                    message: "Failed to clear stored credentials.",
                    errorDescription: description
                )
            }
        }
    }

    /// Resets the verified state when any credential input changes, forcing the user
    /// to re-verify before they can save. This prevents saving stale credentials
    /// that no longer match the last successful verification.
    private func resetVerificationStateForInputChange() {
        guard isConnectionVerified else {
            return
        }

        isConnectionVerified = false
        statusMessage = nil
    }
}

//endofline
