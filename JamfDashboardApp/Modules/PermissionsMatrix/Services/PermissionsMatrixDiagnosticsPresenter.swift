import Foundation

// Diagnostics identifiers and user-facing error formatting for the Permissions
// Matrix module. The module is advisory/diagnostic only, so most failures report
// `localDataChanged: false` and `jamfDataChanged: false`.

/// Stable diagnostics `source` and `category` strings used across the module.
///
/// The `source` follows the framework convention every other module uses —
/// `module.<kebab-name>` (e.g. `module.reports`, `module.support-technician`) —
/// so Permissions Helper events are attributed and grouped in the framework
/// Diagnostics center exactly like the rest of the app. Categories are short
/// logical groups within that source (the source already carries the namespace).
enum PermissionsMatrixDiagnostics {
    /// The diagnostics source for every event emitted by this module.
    static let source = "module.permissions-matrix"

    enum Category {
        static let resourceLoad = "resource-load"
        static let decode = "decode"
        static let runtimeAuth = "runtime-auth"
        static let runtimePrivilegeCatalog = "runtime-privilege-catalog"
        static let runtimeCompare = "runtime-compare"
        static let uiAction = "ui-action"
        static let visualMatrix = "visual-matrix"
    }
}

/// A structured, actionable error suitable for presenting in the module UI.
///
/// Mirrors the fields required by the package's ERROR_AND_DIAGNOSTICS_SPEC so the
/// operator always sees a plain-language summary, the technical cause, and a
/// recommended next action — never a bare "Failed." message.
struct PermissionsMatrixUserFacingError: Identifiable, Equatable {
    let id = UUID()
    var title: String
    var summary: String
    var technicalCause: String?
    var affectedSystem: String
    var endpoint: String?
    var requiredPrivileges: [String]
    var localDataChanged: Bool
    var jamfDataChanged: Bool
    var safeToRetry: Bool
    var recommendedAction: String
    var diagnosticsSource: String
    var diagnosticsCategory: String
}

/// Builds user-facing errors and formats them for diagnostics metadata.
enum PermissionsMatrixDiagnosticsPresenter {
    /// Error shown when the bundled matrix resource cannot be found in the app bundle.
    static func resourceNotFound(resourceName: String) -> PermissionsMatrixUserFacingError {
        PermissionsMatrixUserFacingError(
            title: "Permissions data unavailable",
            summary: "The bundled Permissions Matrix data file could not be found in the app bundle, so this module cannot display privilege information.",
            technicalCause: "Missing resource: \(resourceName).json",
            affectedSystem: "Jamf Dashboard (local app bundle)",
            endpoint: nil,
            requiredPrivileges: [],
            localDataChanged: false,
            jamfDataChanged: false,
            safeToRetry: false,
            recommendedAction: "Reinstall or rebuild Jamf Dashboard so the Permissions Matrix resource is bundled, then reopen this module.",
            diagnosticsSource: PermissionsMatrixDiagnostics.source,
            diagnosticsCategory: PermissionsMatrixDiagnostics.Category.resourceLoad
        )
    }

    /// Error shown when the matrix file exists but cannot be decoded.
    static func decodeFailure(resourceName: String, underlying: String) -> PermissionsMatrixUserFacingError {
        PermissionsMatrixUserFacingError(
            title: "Permissions data could not be read",
            summary: "The Permissions Matrix data file was found but could not be decoded. The bundled data may be corrupted or out of date for this build.",
            technicalCause: underlying,
            affectedSystem: "Jamf Dashboard (local app bundle)",
            endpoint: nil,
            requiredPrivileges: [],
            localDataChanged: false,
            jamfDataChanged: false,
            safeToRetry: false,
            recommendedAction: "Rebuild Jamf Dashboard with a valid Permissions Matrix resource. If this persists, file a bug with the diagnostics export attached.",
            diagnosticsSource: PermissionsMatrixDiagnostics.source,
            diagnosticsCategory: PermissionsMatrixDiagnostics.Category.decode
        )
    }

    /// Error shown when a runtime privilege comparison call fails against Jamf Pro.
    ///
    /// Wording follows the spec: Jamf Pro is the source of truth; the dashboard
    /// neither granted nor denied anything.
    static func runtimeFailure(
        category: String,
        endpoint: String,
        httpStatus: Int?,
        likelyPrivileges: [String],
        safeToRetry: Bool,
        underlying: String
    ) -> PermissionsMatrixUserFacingError {
        let statusText = httpStatus.map { " (HTTP \($0))" } ?? ""
        let summary: String
        if httpStatus == 403 {
            summary = "Jamf Pro rejected this request or did not expose the requested privilege data. The current API client may be missing one or more Jamf Pro privileges listed below."
        } else {
            summary = "The live privilege comparison could not be completed\(statusText). Static matrix browsing is unaffected."
        }
        return PermissionsMatrixUserFacingError(
            title: "Live privilege comparison unavailable",
            summary: summary,
            technicalCause: underlying,
            affectedSystem: "Jamf Pro API",
            endpoint: endpoint,
            requiredPrivileges: likelyPrivileges,
            localDataChanged: false,
            jamfDataChanged: false,
            safeToRetry: safeToRetry,
            recommendedAction: httpStatus == 403
                ? "In Jamf Pro, grant the API role/client the privileges listed above (including \"Read API Roles\" for catalog comparison), then try again."
                : "Verify Jamf Pro connectivity and credentials, then retry. Static browsing continues to work offline.",
            diagnosticsSource: PermissionsMatrixDiagnostics.source,
            diagnosticsCategory: category
        )
    }
}

//endofline
