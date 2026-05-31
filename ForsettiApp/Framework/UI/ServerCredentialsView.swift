import SwiftUI

/// A form-based view for entering, verifying, and saving Jamf Pro server credentials.
/// Supports two authentication methods: API Client (client ID + secret) and
/// username/password. The user must successfully verify the connection before
/// credentials can be saved to the Keychain. Diagnostic events are reported
/// for verification successes, failures, saves, and clears.
struct ServerCredentialsView: View {
    /// Dismiss action to close or pop this view.
    @Environment(\.dismiss) private var dismiss

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
        Form {
            Section("Jamf Server") {
                TextField("https://company.jamfcloud.com", text: $serverURL)
                    .forsettiURLKeyboard()
                    .forsettiNoAutoCorrectionTextInput()
            }

            Section("Authentication Method") {
                Picker("Method", selection: $authenticationMethod) {
                    ForEach(JamfCredentials.AuthenticationMethod.allCases, id: \.self) { method in
                        Text(method.displayName).tag(method)
                    }
                }
                .pickerStyle(.segmented)

                Text("Choose one method. Only the selected method is used and stored.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            // Show the appropriate credential fields based on the selected auth method
            if authenticationMethod == .apiClient {
                Section("Jamf API Client") {
                    TextField("Client ID", text: $clientID)
                        .forsettiNoAutoCorrectionTextInput()
                    SecureField("Client Secret", text: $clientSecret)
                }
            } else {
                Section("Jamf Account") {
                    TextField("Username", text: $accountUsername)
                        .forsettiNoAutoCorrectionTextInput()
                    SecureField("Password", text: $accountPassword)

                    // M4: Deprecation notice per Jamf Pro 11.17.0 changes
                    Text("Note: Username/password authentication is deprecated in Jamf Pro 11.17.0+. Consider switching to API Client credentials for long-term compatibility.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section {
                Button {
                    Task {
                        await verifyConnection()
                    }
                } label: {
                    if isVerifyingConnection {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Verifying Connection...")
                        }
                    } else {
                        Text("Verify Connection")
                    }
                }
                .buttonStyle(.forsettiSecondary)
                .disabled(canVerifyConnection == false || isVerifyingConnection)

                Button("Save Credentials") {
                    saveCredentials()
                }
                .buttonStyle(.forsettiPrimary)
                // Save is only enabled after a successful verification
                .disabled(isConnectionVerified == false || isVerifyingConnection)

                Button("Clear Stored Credentials", role: .destructive) {
                    clearCredentials()
                }
                .buttonStyle(.forsettiDanger)
            }

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .foregroundStyle(ForsettiColors.greenPrimary)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
        }
        .forsettiInsetGroupedListStyle()
        .navigationTitle("Server Credentials")
        .forsettiInlineNavigationTitle()
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
