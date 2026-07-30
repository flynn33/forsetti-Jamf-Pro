import Foundation

/// Errors produced by the App Store demo router (local only; never network).
enum AppStoreDemoRouterError: LocalizedError, Equatable, Sendable {
    case unexpectedEmptyPath

    var errorDescription: String? {
        switch self {
        case .unexpectedEmptyPath:
            return "App Store demo received an empty API path."
        }
    }
}

/// Routes Jamf API-shaped requests to in-memory fixtures for App Store Review.
///
/// **Hard guarantees**
/// - Never opens a network connection
/// - Never reads or writes Keychain credentials
/// - Mutations (POST/PUT/DELETE) return simulated success only; no external side effects
///
/// Support Technician coverage includes inventory search (RSQL filters), full
/// multi-section detail payloads, MDM command history, Classic policies, and
/// simulated management actions.
nonisolated enum AppStoreDemoResponseRouter: Sendable {

    /// Builds a local response for a gateway request while demo mode is active.
    nonisolated static func response(
        path: String,
        method: HTTPMethod,
        queryItems: [URLQueryItem] = [],
        body: Data? = nil
    ) throws -> Data {
        _ = body
        let normalized = normalize(path)
        guard normalized.isEmpty == false else {
            throw AppStoreDemoRouterError.unexpectedEmptyPath
        }

        // Mutating verbs never touch a server — simulated local acknowledgements only.
        switch method {
        case .post, .put, .delete:
            return simulatedMutationSuccess(path: normalized, method: method)
        case .get:
            break
        }

        if normalized == "api/v1/auth" || normalized.hasPrefix("api/v1/auth/") {
            return AppStoreDemoSeedCatalog.authPrivilegesJSON()
        }

        // Prefer the inventory-detail marker before the shorter inventory path.
        if normalized.contains("computers-inventory-detail") {
            return computerDetailResponse(path: normalized)
        }

        if normalized.contains("computers-inventory") {
            return computerInventoryResponse(path: normalized, queryItems: queryItems)
        }

        if normalized.contains("mobile-devices") {
            return mobileDeviceInventoryResponse(path: normalized, queryItems: queryItems)
        }

        if normalized.contains("computer-extension-attributes")
            || normalized.contains("mobile-device-extension-attributes")
            || normalized.contains("computerextensionattributes")
            || normalized.contains("mobiledeviceextensionattributes") {
            return emptyPagedResults()
        }

        if normalized.contains("computer-prestages") {
            return computerPrestageResponse(path: normalized)
        }

        if normalized.contains("mobile-device-prestages") {
            return mobilePrestageResponse(path: normalized)
        }

        if normalized.contains("api/v2/mdm/commands") || normalized.hasSuffix("mdm/commands") {
            let managementID = managementIDFromFilter(queryItems)
            return AppStoreDemoSeedCatalog.mdmCommandHistoryJSON(managementID: managementID)
        }

        if normalized == "JSSResource/policies" || normalized.hasPrefix("JSSResource/policies/") {
            return AppStoreDemoSeedCatalog.classicPoliciesJSON()
        }

        if normalized.contains("JSSResource/computerhistory") {
            let id = resourceID(after: "id", in: normalized) ?? "1001"
            return AppStoreDemoSeedCatalog.classicComputerHistoryJSON(inventoryID: id)
        }

        if normalized.contains("JSSResource/mobiledevicehistory") {
            return AppStoreDemoSeedCatalog.mdmCommandHistoryJSON(managementID: nil)
        }

        if normalized.contains("local-admin-password") {
            if normalized.hasSuffix("/password") || normalized.contains("/password") {
                return AppStoreDemoSeedCatalog.lapsPasswordJSON()
            }
            if normalized.hasSuffix("/accounts") || normalized.contains("/accounts") {
                return AppStoreDemoSeedCatalog.lapsAccountsJSON()
            }
            return AppStoreDemoSeedCatalog.lapsAccountsJSON()
        }

        if normalized.hasSuffix("/buildings") || normalized.contains("/buildings/") {
            return AppStoreDemoSeedCatalog.buildingsJSON()
        }

        if normalized.hasSuffix("/departments") || normalized.contains("/departments/") {
            return AppStoreDemoSeedCatalog.departmentsJSON()
        }

        if normalized.contains("api-roles") || normalized.contains("api-integrations") {
            return emptyPagedResults()
        }

        // Classic script / package list endpoints used by Application Manager cleanup.
        if normalized.contains("JSSResource/scripts") || normalized.contains("JSSResource/packages") {
            return jsonObject(["scripts": [], "packages": []])
        }

        // Unknown GET endpoints still stay offline with an empty, well-formed page.
        return emptyPagedResults()
    }

    // MARK: - Inventory

    nonisolated private static func computerDetailResponse(path: String) -> Data {
        if let id = resourceID(after: "computers-inventory-detail", in: path),
           let record = AppStoreDemoSeedCatalog.computer(id: id) {
            return jsonObject(record)
        }
        return jsonObject(AppStoreDemoSeedCatalog.computers[0])
    }

    nonisolated private static func computerInventoryResponse(
        path: String,
        queryItems: [URLQueryItem]
    ) -> Data {
        if let id = trailingInventoryID(in: path, marker: "computers-inventory"),
           let record = AppStoreDemoSeedCatalog.computer(id: id) {
            return jsonObject(record)
        }

        let filter = queryItems.first(where: { $0.name == "filter" })?.value
        let page = Int(queryItems.first(where: { $0.name == "page" })?.value ?? "0") ?? 0
        let results = AppStoreDemoSeedCatalog.filteredComputers(filter: filter)
        // Demo inventory is a single small page — only page 0 has records.
        let pageResults = page == 0 ? results : []
        return pagedResults(pageResults, totalCount: results.count)
    }

    nonisolated private static func mobileDeviceInventoryResponse(
        path: String,
        queryItems: [URLQueryItem]
    ) -> Data {
        // Single-device detail: …/mobile-devices/{id}/detail or …/mobile-devices/{id}
        if let id = mobileDeviceResourceID(in: path),
           let record = AppStoreDemoSeedCatalog.mobileDevice(id: id) {
            return jsonObject(record)
        }

        let filter = queryItems.first(where: { $0.name == "filter" })?.value
        let page = Int(queryItems.first(where: { $0.name == "page" })?.value ?? "0") ?? 0
        let results = AppStoreDemoSeedCatalog.filteredMobileDevices(filter: filter)
        let pageResults = page == 0 ? results : []
        return pagedResults(pageResults, totalCount: results.count)
    }

    // MARK: - Prestages

    nonisolated private static func computerPrestageResponse(path: String) -> Data {
        if path.contains("/scope") {
            let id = resourceID(after: "computer-prestages", in: path) ?? "demo-c-prestage-1"
            return AppStoreDemoSeedCatalog.computerPrestageScopeJSON(prestageID: id)
        }
        if let id = resourceID(after: "computer-prestages", in: path),
           id.isEmpty == false,
           id != "scope" {
            return AppStoreDemoSeedCatalog.computerPrestageDetailJSON(id: id)
        }
        return AppStoreDemoSeedCatalog.computerPrestagesListJSON()
    }

    nonisolated private static func mobilePrestageResponse(path: String) -> Data {
        if path.contains("/scope") {
            let id = resourceID(after: "mobile-device-prestages", in: path) ?? "demo-m-prestage-1"
            return AppStoreDemoSeedCatalog.mobilePrestageScopeJSON(prestageID: id)
        }
        if let id = resourceID(after: "mobile-device-prestages", in: path),
           id.isEmpty == false,
           id != "scope" {
            return AppStoreDemoSeedCatalog.mobilePrestageDetailJSON(id: id)
        }
        return AppStoreDemoSeedCatalog.mobilePrestagesListJSON()
    }

    // MARK: - Mutations

    /// Simulated success body for management actions. No external system is contacted.
    nonisolated private static func simulatedMutationSuccess(path: String, method: HTTPMethod) -> Data {
        let payload: [String: Any] = [
            "id": "demo-simulated-\(method.rawValue.lowercased())",
            "uuid": "demo-simulated-\(UUID().uuidString)",
            "href": "demo://local/\(path)",
            "demoMode": true,
            "externalDataChanged": false,
            "message": "App Store demo simulated \(method.rawValue). No live Jamf Pro action ran."
        ]
        return jsonObject(payload)
    }

    // MARK: - Helpers

    nonisolated private static func normalize(_ path: String) -> String {
        var value = path.trimmingCharacters(in: .whitespacesAndNewlines)
        while value.hasPrefix("/") {
            value.removeFirst()
        }
        if let queryIndex = value.firstIndex(of: "?") {
            value = String(value[..<queryIndex])
        }
        return value
    }

    /// Extracts `id` from paths like `api/v1/computers-inventory/1001` or
    /// `api/v2/mobile-device-prestages/demo-m-prestage-1/scope`.
    nonisolated private static func resourceID(after marker: String, in path: String) -> String? {
        guard let range = path.range(of: marker) else { return nil }
        let after = path[range.upperBound...]
        let parts = after.split(separator: "/").map(String.init).filter { $0.isEmpty == false }
        guard let first = parts.first else { return nil }
        // Skip non-id fragments such as "detail" when the path is
        // computers-inventory-detail (handled separately) or bare list roots.
        if first == "detail" || first.hasPrefix("-") {
            return parts.dropFirst().first
        }
        return first
    }

    /// Inventory ID only when the path is `…/computers-inventory/{numericId}`
    /// (not the list endpoint and not inventory-detail).
    nonisolated private static func trailingInventoryID(in path: String, marker: String) -> String? {
        guard let range = path.range(of: marker) else { return nil }
        let after = path[range.upperBound...]
        let parts = after.split(separator: "/").map(String.init).filter { $0.isEmpty == false }
        guard let first = parts.first, first.isEmpty == false else { return nil }
        // List endpoints end at the marker with no trailing segment.
        if first == "detail" { return nil }
        return first
    }

    /// Mobile single-device IDs from:
    /// - `api/v2/mobile-devices/{id}/detail`
    /// - `api/v2/mobile-devices/{id}`
    /// - `api/v2/mobile-devices/detail/{id}`
    nonisolated private static func mobileDeviceResourceID(in path: String) -> String? {
        guard let range = path.range(of: "mobile-devices") else { return nil }
        let after = path[range.upperBound...]
        let parts = after.split(separator: "/").map(String.init).filter { $0.isEmpty == false }
        guard let first = parts.first else { return nil }
        if first == "detail" {
            return parts.dropFirst().first
        }
        // Bare list path: mobile-devices/detail (no id)
        if first == "detail" { return nil }
        // id/detail or id
        if parts.count >= 1, first != "detail" {
            // Ignore non-numeric path noise; demo IDs are numeric strings.
            return first
        }
        return nil
    }

    nonisolated private static func managementIDFromFilter(_ queryItems: [URLQueryItem]) -> String? {
        guard let filter = queryItems.first(where: { $0.name == "filter" })?.value else {
            return nil
        }
        // clientManagementId=='uuid'
        let terms = AppStoreDemoSeedCatalog.termsFromRSQLFilter(filter)
        return terms.first
    }

    nonisolated private static func emptyPagedResults() -> Data {
        pagedResults([], totalCount: 0)
    }

    nonisolated private static func pagedResults(_ results: [[String: Any]], totalCount: Int) -> Data {
        jsonObject([
            "totalCount": totalCount,
            "results": results
        ])
    }

    nonisolated private static func jsonObject(_ object: Any) -> Data {
        // Fixtures are hand-built dictionaries of JSON-safe types.
        (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
    }
}
