import Foundation

/// The lifecycle states of an optional runtime privilege comparison.
///
/// Static matrix browsing never depends on these — they only describe the
/// optional "compare against my live Jamf token" enhancement.
enum PermissionsMatrixRuntimeState: Equatable {
    case notAuthenticated
    case readyToCheck
    case checkingAuth
    case checkingPrivilegeCatalog
    case missingReadApiRoles
    case comparisonComplete
    case comparisonUnavailable
    case comparisonFailed
}

/// The result of comparing a selected action's required privileges against the
/// current Jamf Pro token's privileges.
///
/// Language is deliberately cautious: a name absent from the live data is "not
/// confirmed", never definitively "missing", because token/API-role snapshots
/// can lag privilege changes.
struct PermissionsMatrixComparisonResult: Equatable {
    var state: PermissionsMatrixRuntimeState
    /// Required privileges confirmed present in the current token.
    var confirmedPresent: [String]
    /// Required privileges not present in the current token data.
    var notConfirmed: [String]
    /// Optional/alternative privileges (any_of / overlay) absent from the token.
    /// Informational only — their absence is not a problem on its own.
    var alternativesNotPresent: [String]
    var tokenPrivilegeCount: Int
    /// Whether the `/api/v1/api-role-privileges` catalog could be read
    /// (requires the "Read API Roles" privilege).
    var apiRoleCatalogAvailable: Bool
    var userFacingError: PermissionsMatrixUserFacingError?

    static func notAuthenticated() -> PermissionsMatrixComparisonResult {
        PermissionsMatrixComparisonResult(
            state: .notAuthenticated,
            confirmedPresent: [],
            notConfirmed: [],
            alternativesNotPresent: [],
            tokenPrivilegeCount: 0,
            apiRoleCatalogAvailable: false,
            userFacingError: nil
        )
    }
}

/// Compares the static matrix against the current Jamf Pro token/API role.
///
/// All Jamf access goes through the shared `JamfAPIGateway` from `ModuleContext`
/// — there is no module-local client, token store, or URLSession path. The
/// current token's privilege names come from the gateway's existing
/// `fetchTokenAuthorizations()` (which reads `GET /api/v1/auth`).
struct PermissionsMatrixRuntimeVerifier: Sendable {
    private let apiGateway: JamfAPIGateway
    private let diagnosticsReporter: any DiagnosticsReporting

    /// Endpoint paths (no leading slash; the gateway joins them to the base URL).
    private static let authPath = "api/v1/auth"
    private static let apiRolePrivilegesPath = "api/v1/api-role-privileges"

    init(apiGateway: JamfAPIGateway, diagnosticsReporter: any DiagnosticsReporting) {
        self.apiGateway = apiGateway
        self.diagnosticsReporter = diagnosticsReporter
    }

    /// Compares a selected action against the live token. Never throws — failures
    /// are folded into the returned result so the UI degrades gracefully.
    func compare(action: PermissionsMatrixAction, hasCredentials: Bool) async -> PermissionsMatrixComparisonResult {
        guard hasCredentials else {
            return .notAuthenticated()
        }

        // 1) Current token privileges via the shared gateway (GET /api/v1/auth).
        let tokenPrivileges: [String]
        do {
            tokenPrivileges = try await apiGateway.fetchTokenAuthorizations()
        } catch {
            let info = Self.classify(error)
            let uiError = PermissionsMatrixDiagnosticsPresenter.runtimeFailure(
                category: PermissionsMatrixDiagnostics.Category.runtimeAuth,
                endpoint: "GET /\(Self.authPath)",
                httpStatus: info.httpStatus,
                likelyPrivileges: requiredNames(for: action),
                safeToRetry: info.safeToRetry,
                underlying: info.description
            )
            await reportRuntimeFailure(
                action: action,
                category: PermissionsMatrixDiagnostics.Category.runtimeAuth,
                endpoint: "/\(Self.authPath)",
                info: info,
                authenticatedState: true,
                apiRoleCatalogAvailable: false
            )
            return PermissionsMatrixComparisonResult(
                state: .comparisonFailed,
                confirmedPresent: [],
                notConfirmed: [],
                alternativesNotPresent: [],
                tokenPrivilegeCount: 0,
                apiRoleCatalogAvailable: false,
                userFacingError: uiError
            )
        }

        // 2) Best-effort: probe the API role privilege catalog. A 403 here means
        //    "Read API Roles" is likely missing — we note it but still complete
        //    the token-based comparison.
        var apiRoleCatalogAvailable = true
        var readApiRolesMissing = false
        do {
            _ = try await apiGateway.request(path: Self.apiRolePrivilegesPath, method: .get)
        } catch {
            apiRoleCatalogAvailable = false
            let info = Self.classify(error)
            readApiRolesMissing = info.isForbidden
            await diagnosticsReporter.report(
                source: PermissionsMatrixDiagnostics.source,
                category: PermissionsMatrixDiagnostics.Category.runtimePrivilegeCatalog,
                severity: .warning,
                message: readApiRolesMissing
                    ? "API role privilege catalog unavailable — \"Read API Roles\" may be missing."
                    : "API role privilege catalog could not be read.",
                metadata: [
                    "endpoint": "/\(Self.apiRolePrivilegesPath)",
                    "http_status": info.httpStatus.map(String.init) ?? "n/a",
                    "error_description": info.description
                ]
            )
        }

        // 3) Name-level comparison against the token's privilege set.
        let tokenSet = Set(tokenPrivileges)
        let required = requiredNames(for: action)
        let alternatives = alternativeNames(for: action)

        let confirmedPresent = (required + alternatives).filter { tokenSet.contains($0) }
        let notConfirmed = required.filter { tokenSet.contains($0) == false }
        let alternativesNotPresent = alternatives.filter { tokenSet.contains($0) == false }

        await diagnosticsReporter.report(
            source: PermissionsMatrixDiagnostics.source,
            category: PermissionsMatrixDiagnostics.Category.runtimeCompare,
            severity: notConfirmed.isEmpty ? .info : .warning,
            message: "Runtime privilege comparison complete for \(action.resolvedDisplayName).",
            metadata: [
                "action_id": action.commandID,
                "required_privileges": required.joined(separator: ", "),
                "confirmed_present_count": String(confirmedPresent.count),
                "not_confirmed_count": String(notConfirmed.count),
                "token_privilege_count": String(tokenPrivileges.count),
                "authenticated_state": "true",
                "api_role_catalog_available": String(apiRoleCatalogAvailable),
                "safe_to_retry": "true"
            ]
        )

        return PermissionsMatrixComparisonResult(
            state: readApiRolesMissing ? .missingReadApiRoles : .comparisonComplete,
            confirmedPresent: confirmedPresent,
            notConfirmed: notConfirmed,
            alternativesNotPresent: alternativesNotPresent,
            tokenPrivilegeCount: tokenPrivileges.count,
            apiRoleCatalogAvailable: apiRoleCatalogAvailable,
            userFacingError: nil
        )
    }

    // MARK: - Requirement flattening (delegates to the model)

    /// Hard-required privilege names for the action (see
    /// `PermissionsMatrixAction.hardRequiredPrivilegeNames`).
    func requiredNames(for action: PermissionsMatrixAction) -> [String] {
        action.hardRequiredPrivilegeNames
    }

    /// Optional/alternative privilege names (`any_of` / `optional_runtime_overlay`).
    private func alternativeNames(for action: PermissionsMatrixAction) -> [String] {
        action.alternativePrivilegeNames
    }

    // MARK: - Error helpers

    private func reportRuntimeFailure(
        action: PermissionsMatrixAction,
        category: String,
        endpoint: String,
        info: (httpStatus: Int?, isForbidden: Bool, safeToRetry: Bool, description: String),
        authenticatedState: Bool,
        apiRoleCatalogAvailable: Bool
    ) async {
        await diagnosticsReporter.reportError(
            source: PermissionsMatrixDiagnostics.source,
            category: category,
            message: "Runtime privilege verification failed for \(action.resolvedDisplayName).",
            errorDescription: info.description,
            metadata: [
                "action_id": action.commandID,
                "endpoint": endpoint,
                "http_status": info.httpStatus.map(String.init) ?? "n/a",
                "required_privileges": requiredNames(for: action).joined(separator: ", "),
                "safe_to_retry": String(info.safeToRetry),
                "authenticated_state": String(authenticatedState),
                "api_role_catalog_available": String(apiRoleCatalogAvailable)
            ]
        )
    }

    private static func classify(_ error: Error) -> (httpStatus: Int?, isForbidden: Bool, safeToRetry: Bool, description: String) {
        guard let frameworkError = error as? JamfFrameworkError else {
            return (nil, false, true, error.localizedDescription)
        }
        switch frameworkError {
        case .forbidden(let message):
            return (403, true, false, message)
        case .networkFailure(let statusCode, let message):
            return (statusCode, false, true, message)
        case .serverError(let statusCode, let message):
            return (statusCode, false, true, message)
        case .notFound(let message):
            return (404, false, false, message)
        case .rateLimited:
            return (429, false, true, "Jamf Pro rate limited the request.")
        case .authenticationFailed:
            return (401, false, true, "Authentication failed.")
        case .credentialsRejected:
            return (401, false, false, "Jamf Pro rejected the stored credentials.")
        case .missingCredentials:
            return (nil, false, false, "No Jamf Pro credentials are configured.")
        case .invalidServerURL:
            return (nil, false, false, "The configured Jamf Pro server URL is invalid.")
        default:
            return (nil, false, true, frameworkError.errorDescription ?? "Unknown error.")
        }
    }
}

//endofline
