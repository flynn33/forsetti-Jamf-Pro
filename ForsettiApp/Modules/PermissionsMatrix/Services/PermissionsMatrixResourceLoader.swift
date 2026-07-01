import Foundation

/// Errors thrown while locating or decoding the bundled matrix resource.
enum PermissionsMatrixLoadError: LocalizedError {
    case resourceNotFound(name: String)
    case decodeFailed(underlying: String)

    var errorDescription: String? {
        switch self {
        case .resourceNotFound(let name):
            return "Permissions Matrix resource \(name).json was not found in the app bundle."
        case .decodeFailed(let underlying):
            return "Permissions Matrix resource could not be decoded: \(underlying)"
        }
    }
}

/// Loads and decodes the bundled Permissions Matrix v4 resource.
///
/// The loader is intentionally UI-free so a future framework release can reuse it
/// unchanged. The `bundle` is injectable so unit tests can point at the host-app
/// bundle (`Bundle(for:)`). Decode/load failures are reported through the shared
/// diagnostics reporter and surfaced to the caller as typed errors.
struct PermissionsMatrixResourceLoader {
    /// The base filename (without extension) of the bundled resource.
    static let resourceName = "jamf_dashboard_permissions_matrix.v4.module_resource"

    /// The subdirectory the resource lives in within the source tree. Tried as a
    /// fallback in case the synchronized group preserves the folder structure.
    private static let resourceSubdirectory = "Modules/PermissionsMatrix/Resources"

    /// Command IDs that must be present for the matrix to be considered valid.
    /// Mirrors the package validator's `required_commands` set.
    static let requiredCommandIDs: Set<String> = [
        "support.action.update_inventory",
        "support.action.blank_push",
        "support.action.enable_wifi",
        "support.action.disable_wifi",
        "support.action.enable_bluetooth",
        "support.action.disable_bluetooth",
        "support.action.reset_local_user_password",
        "support.search_all_devices",
        "computer_search.search_computers",
        "mobile_search.search_mobile_devices"
    ]

    private let bundle: Bundle
    private let diagnosticsReporter: any DiagnosticsReporting

    init(bundle: Bundle = .main, diagnosticsReporter: any DiagnosticsReporting) {
        self.bundle = bundle
        self.diagnosticsReporter = diagnosticsReporter
    }

    /// Locates, decodes, and validates the bundled matrix.
    ///
    /// - Returns: The decoded document.
    /// - Throws: `PermissionsMatrixLoadError` if the resource is missing or undecodable.
    func loadMatrix() async throws -> PermissionsMatrixDocument {
        guard let url = locateResourceURL() else {
            await diagnosticsReporter.reportError(
                source: PermissionsMatrixDiagnostics.source,
                category: PermissionsMatrixDiagnostics.Category.resourceLoad,
                message: "Permissions Matrix resource not found in app bundle.",
                errorDescription: "Missing \(Self.resourceName).json",
                metadata: ["resource_name": Self.resourceName]
            )
            throw PermissionsMatrixLoadError.resourceNotFound(name: Self.resourceName)
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            await diagnosticsReporter.reportError(
                source: PermissionsMatrixDiagnostics.source,
                category: PermissionsMatrixDiagnostics.Category.resourceLoad,
                message: "Failed to read Permissions Matrix resource data.",
                errorDescription: error.localizedDescription,
                metadata: ["path": url.path]
            )
            throw PermissionsMatrixLoadError.resourceNotFound(name: Self.resourceName)
        }

        let document: PermissionsMatrixDocument
        do {
            document = try JSONDecoder().decode(PermissionsMatrixDocument.self, from: data)
        } catch {
            await diagnosticsReporter.reportError(
                source: PermissionsMatrixDiagnostics.source,
                category: PermissionsMatrixDiagnostics.Category.decode,
                message: "Failed to decode Permissions Matrix resource.",
                errorDescription: String(describing: error),
                metadata: [
                    "byte_count": String(data.count),
                    "path": url.path
                ]
            )
            throw PermissionsMatrixLoadError.decodeFailed(underlying: String(describing: error))
        }

        await reportValidation(for: document)
        return document
    }

    // MARK: - Private

    private func locateResourceURL() -> URL? {
        // Flat lookup first — synchronized groups usually flatten resources into
        // the bundle's Resources root.
        if let url = bundle.url(forResource: Self.resourceName, withExtension: "json") {
            return url
        }
        // Fallback: the folder structure was preserved.
        if let url = bundle.url(forResource: Self.resourceName, withExtension: "json", subdirectory: Self.resourceSubdirectory) {
            return url
        }
        // Last resort: the main bundle, in case an injected bundle lacks the file.
        if bundle != .main {
            if let url = Bundle.main.url(forResource: Self.resourceName, withExtension: "json") {
                return url
            }
        }
        return nil
    }

    /// Compares decoded counts and required commands against the resource's own
    /// verification summary. Mismatches are reported as warnings but never block
    /// browsing — the matrix is still usable.
    private func reportValidation(for document: PermissionsMatrixDocument) async {
        var warnings: [String] = []

        let missingCommands = Self.requiredCommandIDs.subtracting(Set(document.actions.map(\.commandID)))
        if missingCommands.isEmpty == false {
            warnings.append("Missing required commands: \(missingCommands.sorted().joined(separator: ", "))")
        }

        if let summary = document.verificationSummary {
            if let expected = summary.actions, expected != document.actions.count {
                warnings.append("Action count \(document.actions.count) != expected \(expected)")
            }
            if let expected = summary.privileges, expected != document.privileges.count {
                warnings.append("Privilege count \(document.privileges.count) != expected \(expected)")
            }
            if let expected = summary.modernEndpointCatalogEntries, expected != document.endpointCatalog.modernJamfProAPI.count {
                warnings.append("Modern endpoint count \(document.endpointCatalog.modernJamfProAPI.count) != expected \(expected)")
            }
            if let expected = summary.classicEndpointCatalogEntries, expected != document.endpointCatalog.classicAPI.count {
                warnings.append("Classic endpoint count \(document.endpointCatalog.classicAPI.count) != expected \(expected)")
            }
        }

        if warnings.isEmpty {
            await diagnosticsReporter.report(
                source: PermissionsMatrixDiagnostics.source,
                category: PermissionsMatrixDiagnostics.Category.resourceLoad,
                severity: .info,
                message: "Permissions Matrix loaded and validated.",
                metadata: [
                    "actions": String(document.actions.count),
                    "privileges": String(document.privileges.count),
                    "modern_endpoints": String(document.endpointCatalog.modernJamfProAPI.count),
                    "classic_endpoints": String(document.endpointCatalog.classicAPI.count),
                    "mdm_overlays": String(document.endpointCatalog.mdmCommandTypeOverlays.count)
                ]
            )
        } else {
            await diagnosticsReporter.report(
                source: PermissionsMatrixDiagnostics.source,
                category: PermissionsMatrixDiagnostics.Category.resourceLoad,
                severity: .warning,
                message: "Permissions Matrix loaded with validation warnings.",
                metadata: [
                    "warnings": warnings.joined(separator: "; "),
                    "actions": String(document.actions.count)
                ]
            )
        }
    }
}

//endofline
