import Foundation

/// Maps technical Jamf errors to user-facing Remote Support failures with exact required
/// privileges and honest retry semantics, following the HTTP error contract (401/403/404/409/
/// 429/5xx). Pure and independently testable — it classifies errors via the shared
/// `JamfFrameworkError` matchers and never performs networking.
nonisolated struct SupportRemoteSupportDiagnosticMapper {

    /// Endpoint privilege gating `api/v2/mdm/commands` (both GET status and POST command).
    static let endpointPrivilege = "View MDM command information in Jamf Pro API"
    /// Command privilege gating the Remote Desktop enable/disable commands.
    static let commandPrivilege = "Send Computer Remote Desktop Command"

    /// HTTP status implied by a recognizable Jamf error, or `nil` for transport/other errors.
    func httpStatus(for error: Error) -> Int? {
        for code in [401, 403, 404, 409, 429, 500, 502, 503, 504] where error.matchesJamf(status: code) {
            return code
        }
        return nil
    }

    /// Builds the user-facing failure for a Jamf error.
    ///
    /// - Parameter requiresCommandPrivilege: `true` for enable/disable commands (POST), which need
    ///   both the endpoint and the command privilege; `false` for status lookups (GET), which need
    ///   only the endpoint privilege. A 403 lists exactly the privileges that apply.
    func failure(from error: Error, requiresCommandPrivilege: Bool) -> SupportRemoteSupportFailure {
        switch httpStatus(for: error) {
        case 403:
            let privileges = requiresCommandPrivilege
                ? "\(Self.endpointPrivilege)\n\(Self.commandPrivilege)"
                : Self.endpointPrivilege
            return SupportRemoteSupportFailure(
                summary: "Jamf denied the request — your API role is missing a required privilege.",
                isSafeToRetry: true,
                recommendation: "Ask a Jamf administrator to grant the listed privileges to your API role, then retry.",
                requiredPrivilege: privileges
            )
        case 401:
            return SupportRemoteSupportFailure(
                summary: "Your Jamf session is invalid or expired.",
                isSafeToRetry: true,
                recommendation: "Re-authenticate in Forsetti settings, then try again."
            )
        case 404:
            return SupportRemoteSupportFailure(
                summary: "Jamf could not find the device, management ID, or command endpoint.",
                isSafeToRetry: false,
                recommendation: "Refresh the device record and confirm it is still managed by Jamf."
            )
        case 409:
            return SupportRemoteSupportFailure(
                summary: "Jamf reported a conflicting or incompatible state for this command.",
                isSafeToRetry: true,
                recommendation: "Refresh the device and try again once any prior command settles."
            )
        case 429:
            return SupportRemoteSupportFailure(
                summary: "Jamf is rate-limiting requests right now.",
                isSafeToRetry: true,
                recommendation: "Wait a few seconds, then try again."
            )
        case let .some(code) where code >= 500:
            return SupportRemoteSupportFailure(
                summary: "Jamf returned a server error (\(code)).",
                isSafeToRetry: true,
                recommendation: "This is usually temporary — try again shortly."
            )
        default:
            return SupportRemoteSupportFailure(
                summary: error.localizedDescription,
                isSafeToRetry: true,
                recommendation: "Confirm the Jamf API privileges for Remote Desktop commands, then try again."
            )
        }
    }
}

//endofline
