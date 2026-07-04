import Foundation

extension TemporaryAdminUserFacingError {

    /// The normal-use Jamf privileges the feature requires. Surfaced on
    /// permission failures so the technician knows exactly what to grant.
    static let requiredNormalUsePrivileges = [
        "Read Computers",
        "Read Computer Extension Attributes",
        "Read Static Computer Groups, or current tenant-supported request-scope equivalent",
        "Update Static Computer Groups, or current tenant-supported request-scope equivalent"
    ]

    /// Maps a thrown error from a request/demote/poll operation into a
    /// normalized, technician-readable error.
    ///
    /// - Parameters:
    ///   - error: The thrown error.
    ///   - jamfScopeChanged: Whether the Jamf request-scope membership was
    ///     changed before the failure (false for an add that threw).
    ///   - correlationId: The diagnostics correlation reference, if any.
    static func map(
        _ error: Error,
        jamfScopeChanged: Bool? = false,
        correlationId: String? = nil
    ) -> TemporaryAdminUserFacingError {
        // The app never mutates Mac account state directly; it only changes
        // Jamf request-scope membership. So local Mac state is never "changed"
        // by a failed app operation.
        let localMacStateChanged = false

        if error.isJamfInvalidPrivilege {
            return TemporaryAdminUserFacingError(
                title: "Temporary Admin Elevation could not be requested.",
                summary: "Jamf Pro rejected the request because the current API client does not appear to have permission to update the configured request scope.",
                technicalCause: "Jamf Pro returned a 403 / invalid-privilege response.",
                requiredJamfPrivileges: requiredNormalUsePrivileges,
                localMacStateChanged: localMacStateChanged,
                jamfScopeChanged: jamfScopeChanged,
                safeToRetry: true,
                recommendedAction: "Update the Jamf API Role assigned to this API Client, refresh the Forsetti Jamf Pro token, and try again. No Mac permissions were changed.",
                diagnosticsCategory: TemporaryAdminDiagnostics.Category.permission,
                diagnosticsCorrelationId: correlationId
            )
        }

        if let featureError = error as? TemporaryAdminElevationError {
            switch featureError {
            case .notConfigured:
                return TemporaryAdminUserFacingError(
                    title: "Temporary Admin Elevation is not configured.",
                    summary: "A Jamf administrator must create the required request groups, policies, scripts, and Computer Extension Attributes before this action can be used.",
                    technicalCause: "No usable feature configuration was found.",
                    localMacStateChanged: localMacStateChanged,
                    jamfScopeChanged: false,
                    safeToRetry: false,
                    recommendedAction: "Complete the Jamf tenant setup and configure the request-scope IDs. No Mac permissions were changed.",
                    diagnosticsCategory: TemporaryAdminDiagnostics.Category.validation,
                    diagnosticsCorrelationId: correlationId
                )
            case .notEligible(let reason):
                return TemporaryAdminUserFacingError(
                    title: "Temporary Admin Elevation is unavailable for this device.",
                    summary: reason,
                    technicalCause: "The selected device is not an eligible managed Mac.",
                    localMacStateChanged: localMacStateChanged,
                    jamfScopeChanged: false,
                    safeToRetry: false,
                    recommendedAction: "Select a managed Mac with a valid Jamf computer inventory ID.",
                    diagnosticsCategory: TemporaryAdminDiagnostics.Category.validation,
                    diagnosticsCorrelationId: correlationId
                )
            case .validationFailed(let messages):
                return TemporaryAdminUserFacingError(
                    title: "Temporary Admin Elevation could not be requested.",
                    summary: messages.joined(separator: "\n"),
                    technicalCause: "Input validation failed.",
                    localMacStateChanged: localMacStateChanged,
                    jamfScopeChanged: false,
                    safeToRetry: true,
                    recommendedAction: "Correct the highlighted fields and try again.",
                    diagnosticsCategory: TemporaryAdminDiagnostics.Category.validation,
                    diagnosticsCorrelationId: correlationId
                )
            case .missingRequestScope:
                return TemporaryAdminUserFacingError(
                    title: "Temporary Admin Elevation is not fully configured.",
                    summary: "No Jamf request scope is configured for the selected action.",
                    technicalCause: "A required request scope has no configured Jamf object ID.",
                    localMacStateChanged: localMacStateChanged,
                    jamfScopeChanged: false,
                    safeToRetry: false,
                    recommendedAction: "Record the dedicated request-group IDs in the Support Technician configuration. No Mac permissions were changed.",
                    diagnosticsCategory: TemporaryAdminDiagnostics.Category.validation,
                    diagnosticsCorrelationId: correlationId
                )
            case .duplicateActiveRequest:
                return TemporaryAdminUserFacingError(
                    title: "A request is already in progress.",
                    summary: "A temporary admin request is already active for this Mac in this session. Wait for it to complete or refresh the status.",
                    technicalCause: "A duplicate active request was blocked.",
                    localMacStateChanged: localMacStateChanged,
                    jamfScopeChanged: false,
                    safeToRetry: false,
                    recommendedAction: "Wait for the current request to finish, or use Refresh Status.",
                    diagnosticsCategory: TemporaryAdminDiagnostics.Category.request,
                    diagnosticsCorrelationId: correlationId
                )
            }
        }

        if let frameworkError = error as? JamfFrameworkError, case .notFound = frameworkError {
            return TemporaryAdminUserFacingError(
                title: "A configured request scope was not found.",
                summary: "Jamf Pro could not find the configured request group. The configuration may reference a deleted or incorrect group ID.",
                technicalCause: "Jamf Pro returned a 404 for the request scope.",
                localMacStateChanged: localMacStateChanged,
                jamfScopeChanged: jamfScopeChanged,
                safeToRetry: false,
                recommendedAction: "Verify the dedicated request-group IDs in the Support Technician configuration.",
                diagnosticsCategory: TemporaryAdminDiagnostics.Category.scope,
                diagnosticsCorrelationId: correlationId
            )
        }

        return TemporaryAdminUserFacingError(
            title: "Temporary Admin Elevation could not be completed.",
            summary: "The request to Jamf Pro did not succeed.",
            technicalCause: error.localizedDescription,
            localMacStateChanged: localMacStateChanged,
            jamfScopeChanged: jamfScopeChanged,
            safeToRetry: true,
            recommendedAction: "Check connectivity to Jamf Pro and try again. No Mac permissions were changed.",
            diagnosticsCategory: TemporaryAdminDiagnostics.Category.scope,
            diagnosticsCorrelationId: correlationId
        )
    }
}
