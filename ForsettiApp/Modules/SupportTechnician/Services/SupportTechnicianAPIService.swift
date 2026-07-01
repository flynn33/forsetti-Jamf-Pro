import Foundation

// "End of Line"

/// Encapsulates all Jamf Pro API interactions for the Support Technician module.
///
/// This actor provides thread-safe methods for searching assets, fetching device
/// details, performing MDM management actions, retrieving sensitive credentials,
/// and managing application deployments. It handles the wide variety of Jamf Pro
/// API versions and response shapes through multi-path fallback strategies and
/// flexible JSON parsing.
actor SupportTechnicianAPIService {
    /// Enumerates the Jamf Pro computer inventory API version tiers.
    ///
    /// Each version maps to different search, detail, and inventory endpoint paths.
    /// The service tries versions in order (v3, v2, v1) and falls back on failure.
    private enum ComputerInventoryEndpointVersion: String, CaseIterable {
        case v3 = "v3"
        case v2 = "v2"
        case v1 = "v1"

        /// The API path for paginated computer inventory searches.
        var searchPath: String {
            "api/\(rawValue)/computers-inventory"
        }

        /// The API path prefix for fetching a single computer's full detail.
        var detailPathPrefix: String {
            "api/\(rawValue)/computers-inventory-detail"
        }

        /// The API path prefix for inventory-level endpoints (filevault, recovery lock, etc.).
        var inventoryPathPrefix: String {
            "api/\(rawValue)/computers-inventory"
        }
    }

    /// Controls how inventory section parameters are encoded in mobile device requests.
    ///
    /// Some Jamf Pro versions use modern section names (e.g. "USER_AND_LOCATION"),
    /// others use legacy names (e.g. "LOCATION"), and some reject section parameters entirely.
    private enum SectionEncodingMode: CaseIterable {
        case modern
        case legacy
        case none
    }

    /// The shared Jamf Pro API gateway used for all authenticated requests.
    private let apiGateway: JamfAPIGateway

    /// Diagnostics reporter for logging service-level events (catalog failures, fallbacks).
    private let diagnosticsReporter: any DiagnosticsReporting

    /// Persistent local cache. Backs `fetchDeviceDetail(...)` and
    /// `fetchAllPolicies()` so repeated visits to the same device don't
    /// re-hit Jamf Pro. Driven by the Refresh / Clear Cache toolbar
    /// buttons in the detail pane.
    let cache: SupportTechnicianCache

    /// ISO 8601 date formatter without fractional seconds.
    private let iso8601Formatter = ISO8601DateFormatter()

    /// ISO 8601 date formatter with fractional seconds support.
    private let iso8601FractionalFormatter = ISO8601DateFormatter()

    /// Session cache mapping uppercase mobile serial → PreStage profile name,
    /// built once by walking the prestage scope API. The mobile detail payload
    /// carries no inline PreStage, so this backs the General-frame PreStage row
    /// for iOS/iPadOS. Rebuilt when a detail fetch passes `bypassCache: true`.
    private var cachedMobilePrestageScopeMap: [String: String]?

    /// Displayed PreStage for a mobile device when both real API sources (bulk
    /// inventory `enrollmentMethodPrestage` and the prestage scope walk) resolve
    /// nil. AuthEnroll is a tenant prestage that isn't exposed through either
    /// API, so a device that resolves to nothing is treated as AuthEnroll.
    private static let mobilePrestageNilFallback = "AuthEnroll"

    /// Creates a new API service wired to the given gateway and diagnostics reporter.
    ///
    /// Configures ISO 8601 date formatters for parsing inventory timestamps.
    ///
    /// - Parameters:
    ///   - apiGateway: The shared Jamf Pro API gateway.
    ///   - diagnosticsReporter: Receives diagnostic events for observability. Defaults to
    ///     the gateway's reporter would be ideal, but the gateway doesn't expose it; instead
    ///     callers inject the same shared reporter used across the app.
    init(apiGateway: JamfAPIGateway, diagnosticsReporter: any DiagnosticsReporting) {
        self.apiGateway = apiGateway
        self.diagnosticsReporter = diagnosticsReporter
        self.cache = SupportTechnicianCache()

        iso8601Formatter.formatOptions = [.withInternetDateTime]
        iso8601FractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        // Kick off the Application Manager ephemeral-cleanup pass. Fire-and-forget —
        // this runs once per service construction (effectively once per Support
        // Technician session) and purges Jamf Pro script / policy records older
        // than 24 hours.
        Task { [weak self] in
            await self?.purgeStaleApplicationActionArtifacts()
        }
    }

    // MARK: - Public Search

    /// Searches for managed assets (computers and/or mobile devices) matching the given query.
    ///
    /// When the scope is `.all`, computer and mobile device searches run concurrently.
    /// Results are deduplicated and sorted by asset type then display name.
    ///
    /// - Parameters:
    ///   - query: The username or serial number to search for.
    ///   - scope: Which device types to include in the search.
    /// - Returns: A deduplicated, sorted array of search results.
    /// - Throws: `SupportTechnicianError.invalidSearchQuery` if the query is empty.
    func searchAssets(
        query: String,
        scope: SupportSearchScope
    ) async throws -> [SupportSearchResult] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedQuery.isEmpty == false else {
            throw SupportTechnicianError.invalidSearchQuery
        }

        let results: [SupportSearchResult]
        switch scope {
        case .all:
            // Run computer and mobile searches concurrently for speed
            async let computerResults = searchComputers(query: trimmedQuery)
            async let mobileResults = searchMobileDevices(query: trimmedQuery)
            let computers = try await computerResults
            let mobileDevices = try await mobileResults
            results = computers + mobileDevices
        case .computers:
            results = try await searchComputers(query: trimmedQuery)
        case .mobileDevices:
            results = try await searchMobileDevices(query: trimmedQuery)
        }

        return dedupe(results).sorted(by: sortByAssetAndName)
    }

    // MARK: - Device Detail

    /// Fetches the full device detail for a search result, including structured sections,
    /// health diagnostics, application inventory, and the raw JSON payload.
    ///
    /// - Parameter result: The search result to fetch details for.
    /// - Returns: A fully populated `SupportDeviceDetail` instance.
    func fetchDeviceDetail(
        for result: SupportSearchResult,
        bypassCache: Bool = false
    ) async throws -> SupportDeviceDetail {
        // Cache-first path. The persistent cache stores the raw payload
        // JSON so repeated visits to the same device don't re-hit Jamf
        // Pro. The Refresh toolbar button calls this method with
        // bypassCache: true to force a network fetch.
        let payload: [String: Any]
        let rawJSON: String
        if bypassCache == false,
           let cachedJSON = await cache.cachedPayload(forDeviceID: result.id),
           let cachedData = cachedJSON.data(using: .utf8),
           let cachedPayload = (try? JSONSerialization.jsonObject(with: cachedData)) as? [String: Any],
           cachedDetailPayloadNeedsRefresh(cachedPayload, for: result) == false
        {
            payload = cachedPayload
            rawJSON = cachedJSON
        } else {
            payload = try await fetchRawDetailPayload(for: result)
            rawJSON = prettyJSONString(from: payload)
            await cache.storePayload(rawJSON, forDeviceID: result.id)
        }

        // Diagnostic dump so the operator can verify exactly what Jamf
        // returned. Writes to the sandboxed Documents directory; if the
        // write fails (sandbox denial / disk full) we silently continue
        // — the dump is best-effort only.
        Self.dumpPayloadForDiagnostics(rawJSON: rawJSON, deviceID: result.id)
        let (sections, categorized) = buildSectionsAndCategorize(from: payload)
        let extensionAttributes = extractExtensionAttributes(from: payload)
        let hardwareSpecs = extractHardwareSpecs(from: payload, assetType: result.assetType)
        let osInfo = extractOSInfo(from: payload)
        let securityProfile = extractSecurityProfile(from: payload)
        let networkInfo = extractNetworkInfo(from: payload)
        let deviceGroups = extractDeviceGroups(from: payload)
        let configurationProfiles = extractConfigurationProfiles(from: payload)
        let localUsers = extractLocalUsers(from: payload)
        let applications = extractApplicationNames(from: payload)
        let flattenedValues = flattenForDiagnostics(from: payload)
        let diagnostics = buildDiagnostics(for: result, flattenedValues: flattenedValues, applications: applications)

        // Mobile devices carry no inline PreStage in their PER-ID detail
        // payload. The bulk search dict does (parsed into
        // `result.prestageEnrollment`), so prefer that — it mirrors how the Mac
        // path reads PreStage straight from inventory data. The scope-API walk
        // stays as a fallback for devices the bulk search didn't resolve;
        // `bypassCache` (the detail Refresh button) rebuilds the scope map.
        var resolvedMobilePrestage: String?
        if result.assetType == .mobileDevice {
            if let fromSearch = result.prestageEnrollment {
                resolvedMobilePrestage = fromSearch
            } else if let fromScope = await resolveMobilePrestageName(
                forSerial: result.serialNumber,
                forceReload: bypassCache
            ) {
                resolvedMobilePrestage = fromScope
            } else {
                // AuthEnroll doesn't surface through the inventory or scope
                // APIs — it reports nil everywhere — so a mobile device that
                // resolves to nothing through both real sources is, per tenant
                // policy, an AuthEnroll enrollment.
                resolvedMobilePrestage = Self.mobilePrestageNilFallback
            }
            await diagnosticsReporter.report(
                source: "module.support-technician",
                category: "prestage",
                severity: .info,
                message: "Mobile PreStage source for the General frame.",
                metadata: [
                    "serial": result.serialNumber,
                    "from_search": result.prestageEnrollment ?? "nil",
                    "final": resolvedMobilePrestage ?? "nil"
                ]
            )
        }
        let summary = enrichedSummary(
            for: result,
            from: payload,
            mobilePrestageOverride: resolvedMobilePrestage
        )

        return SupportDeviceDetail(
            summary: summary,
            diagnostics: diagnostics,
            sections: sections,
            applications: applications,
            rawJSON: rawJSON,
            categorized: categorized,
            extensionAttributes: extensionAttributes,
            hardwareSpecs: hardwareSpecs,
            osInfo: osInfo,
            securityProfile: securityProfile,
            networkInfo: networkInfo,
            deviceGroups: deviceGroups,
            configurationProfiles: configurationProfiles,
            localUsers: localUsers
        )
    }

    /// Old cached computer payloads from before the detail-section fix may
    /// lack `LOCAL_USER_ACCOUNTS`. Treat those as stale so the User Accounts
    /// frame gets a fresh all-sections fetch without requiring the operator
    /// to manually clear cache.
    private func cachedDetailPayloadNeedsRefresh(
        _ payload: [String: Any],
        for result: SupportSearchResult
    ) -> Bool {
        guard result.assetType == .computer else {
            return false
        }

        return resolveValue(atPath: "localUserAccounts", in: payload) == nil
            && resolveValue(atPath: "local_user_accounts", in: payload) == nil
    }

    /// Adds detail-only enrollment fields to the original search result so
    /// the General frame can display PreStage / Automated Enrollment without
    /// changing the search endpoint contract.
    private func enrichedSummary(
        for result: SupportSearchResult,
        from payload: [String: Any],
        mobilePrestageOverride: String? = nil
    ) -> SupportSearchResult {
        // Inline payload data wins; `mobilePrestageOverride` is the last resort
        // for mobile devices, whose payload carries no inline PreStage and must
        // be resolved out-of-band via the prestage scope API.
        let prestageEnrollment = SupportTechnicianPrestageParser.displayValue(from: payload) ?? extractString(
            using: [
                "general.enrollmentMethodPrestage.profileName",
                "general.enrollmentMethodPrestage.mobileDevicePrestageId",
                "general.prestageEnrollmentProfile.displayName",
                "general.prestageEnrollmentProfile.name",
                "general.prestageEnrollmentProfileName",
                "general.prestageEnrollmentProfileId",
                "general.prestageEnrollment.name",
                "general.prestageEnrollment.displayName",
                "prestageEnrollmentProfileName",
                "prestageEnrollmentProfileId",
                "prestageId",
                "prestageEnrollment.name",
                "prestageEnrollment.displayName",
                "prestageEnrollmentName",
                "prestageEnrollmentProfile"
            ],
            from: payload
        ) ?? mobilePrestageOverride
        let automatedEnrollment = extractBool(
            using: [
                "general.enrolledViaAutomatedDeviceEnrollment",
                "general.automatedDeviceEnrollment",
                "enrolledViaAutomatedDeviceEnrollment",
                "automatedDeviceEnrollment"
            ],
            from: payload
        )

        return SupportSearchResult(
            assetType: result.assetType,
            inventoryID: result.inventoryID,
            managementID: result.managementID,
            clientManagementID: result.clientManagementID,
            displayName: result.displayName,
            serialNumber: result.serialNumber,
            username: result.username,
            email: result.email,
            model: result.model,
            osVersion: result.osVersion,
            lastInventoryUpdate: result.lastInventoryUpdate,
            prestageEnrollment: prestageEnrollment,
            automatedDeviceEnrollment: automatedEnrollment
        )
    }

    // MARK: - Mobile PreStage Resolution

    /// Resolves the PreStage profile name for a mobile device by its serial.
    ///
    /// The mobile detail payload has no inline PreStage, so the assignment is
    /// found by walking the prestage scope API into a serial → name map. The
    /// map is built once per session and reused; `forceReload` (the detail
    /// Refresh) rebuilds it.
    private func resolveMobilePrestageName(forSerial serial: String, forceReload: Bool) async -> String? {
        guard let normalized = SupportTechnicianPrestageParser.normalizeSerial(serial) else {
            await diagnosticsReporter.report(
                source: "module.support-technician",
                category: "prestage",
                severity: .info,
                message: "Skipped mobile PreStage resolution: device has no usable serial number.",
                metadata: ["raw_serial": serial]
            )
            return nil
        }
        let map = await mobilePrestageScopeMap(forceReload: forceReload)
        let resolved = map[normalized]
        await diagnosticsReporter.report(
            source: "module.support-technician",
            category: "prestage",
            severity: .info,
            message: "Resolved mobile PreStage for the General frame.",
            metadata: [
                "serial": normalized,
                "scope_serial_count": String(map.count),
                "matched": resolved == nil ? "false" : "true"
            ]
        )
        return resolved
    }

    /// Returns the cached serial → PreStage name map, building it on first use.
    private func mobilePrestageScopeMap(forceReload: Bool) async -> [String: String] {
        if forceReload == false, let cached = cachedMobilePrestageScopeMap {
            return cached
        }
        let map = await buildMobilePrestageScopeMap()
        cachedMobilePrestageScopeMap = map
        return map
    }

    /// Walks every mobile-device-prestage and its scope, producing a map of
    /// uppercase serial → PreStage profile name. Best-effort: API failures
    /// yield a partial (or empty) map and the PreStage row simply stays hidden.
    private func buildMobilePrestageScopeMap() async -> [String: String] {
        let prestageNames = await fetchAllMobilePrestageNames()
        guard prestageNames.isEmpty == false else {
            return [:]
        }

        var serialToName: [String: String] = [:]
        var serialsByPrestage: [String: [String]] = [:]
        for (prestageID, prestageName) in prestageNames {
            let serials = await fetchMobilePrestageScopeSerials(forPrestageID: prestageID)
            serialsByPrestage["\(prestageName) [\(prestageID)]"] = serials.sorted()
            for serial in serials where serialToName[serial] == nil {
                serialToName[serial] = prestageName
            }
        }

        // Ground-truth dump: the full serial → PreStage map keyed by
        // "name [id]". When a device the operator expects (e.g. one they see
        // under a profile in PreStage Director) doesn't resolve here, this file
        // settles whether it's a scope-parse miss on a specific profile's shape
        // or a serial that genuinely isn't in any v2 `/scope` response.
        if let dumpData = try? JSONSerialization.data(
            withJSONObject: [
                "prestage_count": prestageNames.count,
                "total_unique_serials": serialToName.count,
                "serials_by_prestage": serialsByPrestage
            ],
            options: [.prettyPrinted, .sortedKeys]
        ), let dumpString = String(data: dumpData, encoding: .utf8) {
            Self.dumpPayloadForDiagnostics(
                rawJSON: dumpString,
                deviceID: "session",
                kind: "mobile-prestage-scope-map"
            )
        }
        await diagnosticsReporter.report(
            source: "module.support-technician",
            category: "prestage",
            severity: .info,
            message: "Built mobile PreStage scope map.",
            metadata: [
                "prestage_count": String(prestageNames.count),
                "total_unique_serials": String(serialToName.count),
                "per_prestage_counts": serialsByPrestage
                    .map { "\($0.key)=\($0.value.count)" }
                    .sorted()
                    .joined(separator: ";")
            ]
        )
        return serialToName
    }

    /// Pages `GET api/v2/mobile-device-prestages` into `[id: displayName]`.
    private func fetchAllMobilePrestageNames() async -> [String: String] {
        let pageSize = 100
        var page = 0
        var names: [String: String] = [:]

        while true {
            let data: Data
            do {
                data = try await apiGateway.request(
                    path: "api/v2/mobile-device-prestages",
                    method: .get,
                    queryItems: [
                        URLQueryItem(name: "page", value: String(page)),
                        URLQueryItem(name: "page-size", value: String(pageSize))
                    ]
                )
            } catch {
                await diagnosticsReporter.reportError(
                    source: "module.support-technician",
                    category: "prestage",
                    message: "Failed reading mobile PreStage list for the General frame.",
                    errorDescription: error.localizedDescription,
                    metadata: ["page": String(page)]
                )
                break
            }

            guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                break
            }

            let pageNames = SupportTechnicianPrestageParser.mobilePrestageNames(fromListPage: json)
            let previousCount = names.count
            names.merge(pageNames) { existing, _ in existing }
            let totalCount = json["totalCount"] as? Int

            if pageNames.isEmpty || pageNames.count < pageSize || names.count == previousCount {
                break
            }
            if let totalCount, names.count >= totalCount {
                break
            }
            page += 1
        }
        return names
    }

    /// Pages `GET api/v2/mobile-device-prestages/{id}/scope` into a set of
    /// normalized serials scoped to that prestage.
    private func fetchMobilePrestageScopeSerials(forPrestageID prestageID: String) async -> Set<String> {
        let pageSize = 100
        var page = 0
        var serials = Set<String>()

        while true {
            let data: Data
            do {
                data = try await apiGateway.request(
                    path: "api/v2/mobile-device-prestages/\(prestageID)/scope",
                    method: .get,
                    queryItems: [
                        URLQueryItem(name: "page", value: String(page)),
                        URLQueryItem(name: "page-size", value: String(pageSize))
                    ]
                )
            } catch {
                await diagnosticsReporter.reportError(
                    source: "module.support-technician",
                    category: "prestage",
                    message: "Failed reading mobile PreStage scope for the General frame.",
                    errorDescription: error.localizedDescription,
                    metadata: ["prestage_id": prestageID, "page": String(page)]
                )
                break
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) else {
                break
            }

            let pageSerials = SupportTechnicianPrestageParser.mobilePrestageScopeSerials(fromScopeJSON: json)
            let previousCount = serials.count
            serials.formUnion(pageSerials)

            if pageSerials.isEmpty || pageSerials.count < pageSize || serials.count == previousCount {
                break
            }
            page += 1
        }
        return serials
    }

    /// Extracts local user accounts from a Mac inventory payload.
    /// Top-level `localUserAccounts[]` per the v2 computer detail shape.
    private func extractLocalUsers(from payload: [String: Any]) -> [SupportLocalUser] {
        guard let array = resolveValue(atPath: "localUserAccounts", in: payload) as? [Any]
            ?? resolveValue(atPath: "local_user_accounts", in: payload) as? [Any]
        else {
            return []
        }
        return array.compactMap { element -> SupportLocalUser? in
            guard let dict = element as? [String: Any] else { return nil }
            guard let username = extractStringValue(from: dict["username"])
                ?? extractStringValue(from: dict["userName"])
            else { return nil }
            return SupportLocalUser(
                uid: extractStringValue(from: dict["uid"])
                    ?? extractStringValue(from: dict["userGuid"]),
                username: username,
                fullName: extractStringValue(from: dict["fullName"]),
                isAdmin: dict["admin"] as? Bool ?? (dict["admin"] as? NSNumber)?.boolValue,
                fileVault2Enabled: dict["fileVault2Enabled"] as? Bool
                    ?? (dict["fileVault2Enabled"] as? NSNumber)?.boolValue,
                userAccountType: extractStringValue(from: dict["userAccountType"]),
                homeDirectory: extractStringValue(from: dict["homeDirectory"]),
                homeDirectorySizeMb: (dict["homeDirectorySizeMb"] as? NSNumber)?.intValue,
                azureActiveDirectoryId: extractStringValue(from: dict["azureActiveDirectoryId"])
            )
        }
    }

    // MARK: - Management Actions

    /// Performs an MDM management action on the selected device.
    ///
    /// Routes each action to the appropriate Jamf Pro API endpoint, handling
    /// computer vs. mobile device differences and credential retrieval flows.
    ///
    /// - Parameters:
    ///   - action: The management action to perform.
    ///   - detail: The device detail providing identifiers and context.
    /// - Returns: An action result, potentially including a sensitive value for credential actions.
    func perform(_ action: SupportManagementAction, for detail: SupportDeviceDetail) async throws -> SupportActionResult {
        switch action {
        case .refreshInventory:
            // The Update Inventory command is the single most-used
            // technician action and must work on every managed device,
            // not just modern (macOS 13+ / iOS 17+) DDM-capable ones.
            //
            // Strategy:
            //   1. Try DDM sync (`POST /api/v1/ddm/{managementId}/sync`)
            //      first — that's the modern path Apple is steering
            //      integrators toward and it's instant when the device
            //      is on-net.
            //   2. If DDM sync fails for ANY reason (no managementId,
            //      404 on a non-DDM device, 4xx/5xx anywhere), fall
            //      back to the Classic API UpdateInventory command
            //      which has worked unchanged since Jamf Pro 9.x:
            //        Computer: POST /JSSResource/computercommands/command/UpdateInventory/id/{computerId}
            //        Mobile:   POST /JSSResource/mobiledevicecommands/command/UpdateInventory/id/{mobileDeviceId}
            //      Both take the INVENTORY id, not the managementId,
            //      so they work even on devices missing a v2 management
            //      identifier. The user explicitly said this used to
            //      work before the redesign — the Classic API path was
            //      always there.
            do {
                let managementID = try resolveManagementID(from: detail)
                try await sendDDMSync(managementID: managementID)
                return SupportActionResult(
                    title: action.title,
                    detail: "DDM sync queued for \(detail.summary.displayName). The device's next DeclarativeManagement check-in refreshes Jamf's inventory.",
                    sensitiveValue: nil
                )
            } catch {
                // Fall through to Classic API.
                await diagnosticsReporter.report(
                    source: "module.support-technician",
                    category: "management",
                    severity: .info,
                    message: "DDM sync failed for inventory refresh — falling back to Classic UpdateInventory.",
                    metadata: [
                        "asset_type": detail.summary.assetType.rawValue,
                        "inventory_id": detail.summary.inventoryID,
                        "ddm_error": (error as? LocalizedError)?.errorDescription ?? "\(error)"
                    ]
                )
            }

            let classicPath: String
            switch detail.summary.assetType {
            case .computer:
                classicPath = "JSSResource/computercommands/command/UpdateInventory/id/\(detail.summary.inventoryID)"
            case .mobileDevice:
                classicPath = "JSSResource/mobiledevicecommands/command/UpdateInventory/id/\(detail.summary.inventoryID)"
            }
            _ = try await apiGateway.request(path: classicPath, method: .post, body: nil)
            return SupportActionResult(
                title: action.title,
                detail: "Update Inventory command queued for \(detail.summary.displayName) via Classic API. The device runs inventory collection at its next MDM check-in.",
                sensitiveValue: nil
            )

        case .blankPush:
            // Modern Jamf Pro API dedicated endpoint:
            //   POST /api/v2/mdm/blank-push
            //   { "clientManagementIds": ["<uuid>"] }
            //
            // A blank push sends an empty APNs notification that
            // prompts the device to contact its MDM server and process
            // any queued commands immediately — useful when the tech
            // just queued an UpdateInventory / RemoteDesktop / Restart
            // and doesn't want to wait for the device's next scheduled
            // check-in.
            //
            // Privilege: `Send MDM Check In Command` (tenant has it,
            // confirmed via introspection).
            //
            // Works for both computers and mobile devices since the
            // endpoint accepts any Jamf Pro managementId regardless of
            // asset type.
            let managementID = try resolveManagementID(from: detail)
            try await sendBlankPush(managementID: managementID)
            return SupportActionResult(
                title: action.title,
                detail: "Blank push sent to \(detail.summary.displayName). The device should check in with MDM shortly and process any queued commands.",
                sensitiveValue: nil
            )

        case .discoverApplications:
            switch detail.summary.assetType {
            case .computer:
                let data = try await fetchComputerDetailPayload(inventoryID: detail.summary.inventoryID)
                let payload = try rootDictionary(from: data)
                let appCount = extractApplicationNames(from: payload).count
                return SupportActionResult(
                    title: action.title,
                    detail: "Loaded \(appCount) application\(appCount == 1 ? "" : "s") from the last reported inventory.",
                    sensitiveValue: nil
                )
            case .mobileDevice:
                let managementID = try resolveManagementID(from: detail)
                _ = try await queueMDMCommand(commandType: "INSTALLED_APPLICATION_LIST", managementID: managementID)
                return SupportActionResult(
                    title: action.title,
                    detail: "Application discovery command queued in Jamf Pro.",
                    sensitiveValue: nil
                )
            }

        case .restartDevice:
            let managementID = try resolveManagementID(from: detail)
            _ = try await queueMDMCommand(commandType: "RESTART_DEVICE", managementID: managementID)
            return SupportActionResult(
                title: action.title,
                detail: "Restart command queued in Jamf Pro.",
                sensitiveValue: nil
            )

        case .shutDownDevice:
            // Modern Jamf Pro API:
            //   POST /api/v2/mdm/commands
            //   { clientData: [{managementId: <uuid>}],
            //     commandData: {commandType: "SHUT_DOWN_DEVICE"} }
            //
            // Privilege: `Send Computer Shut Down Command` (macOS),
            // `Send Mobile Device Shut Down Command` (mobile). The
            // tenant's API client holds the macOS variant per runtime
            // introspection; mobile is likely covered by the same role
            // bundle. A missing privilege surfaces as 403 with a
            // pointer to the exact privilege name from the verbose log.
            let managementID = try resolveManagementID(from: detail)
            _ = try await queueMDMCommand(commandType: "SHUT_DOWN_DEVICE", managementID: managementID)
            return SupportActionResult(
                title: action.title,
                detail: "Shut Down command queued in Jamf Pro. The device powers off at next MDM check-in.",
                sensitiveValue: nil
            )

        case .sendDeviceLock:
            // Modern Jamf Pro API DEVICE_LOCK command.
            //
            // On macOS the command needs a 6-digit PIN in commandData
            // (required — the Mac's firmware lock prompts for exactly
            // this PIN to unlock). On iOS the PIN is not applicable;
            // the device's existing passcode stays in force.
            //
            //   POST /api/v2/mdm/commands
            //   macOS:
            //     { clientData: [{managementId}],
            //       commandData: {commandType: "DEVICE_LOCK", pin: "123456"} }
            //   iOS:
            //     { clientData: [{managementId}],
            //       commandData: {commandType: "DEVICE_LOCK"} }
            //
            // Privilege: `Send Computer Remote Lock Command` (macOS),
            // `Send Mobile Device Remote Lock Command` (mobile). Both
            // confirmed present in the tenant's API client role.
            //
            // The Mac PIN is cryptographically random (SecRandomCopyBytes)
            // and returned via `sensitiveValue` so the tech sees it
            // exactly once. `View Device Lock PIN` later retrieves the
            // same PIN from Jamf's MDM command history, but returning
            // it here saves a round trip.
            let managementID = try resolveManagementID(from: detail)
            var extras: [String: Any] = [:]
            var pinForUI: String?
            if detail.summary.assetType == .computer {
                let pin = generateLockPIN()
                extras["pin"] = pin
                pinForUI = pin
            }
            _ = try await queueMDMCommand(
                commandType: "DEVICE_LOCK",
                managementID: managementID,
                extraCommandData: extras
            )
            let baseDetail = "Device Lock command queued for \(detail.summary.displayName)."
            if let pinForUI {
                return SupportActionResult(
                    title: action.title,
                    detail: baseDetail + " The end user will be prompted for this PIN at the firmware lock screen. Save it — it is not shown again on this screen (though `View Device Lock PIN` can retrieve it from Jamf).",
                    sensitiveValue: pinForUI
                )
            }
            return SupportActionResult(
                title: action.title,
                detail: baseDetail + " The device locks with its existing passcode at next check-in.",
                sensitiveValue: nil
            )

        case .logOutUser:
            // Modern Jamf Pro API:
            //   POST /api/v2/mdm/commands
            //   { clientData: [{managementId}],
            //     commandData: {commandType: "LOG_OUT_USER"} }
            //
            // macOS only — LOG_OUT_USER is defined for computer targets.
            // Mobile devices have no equivalent standalone command.
            //
            // Privilege: `Send Computer Log Out User Command` (or whatever
            // the exact name is in the tenant's role bundle). A missing
            // privilege surfaces as a clear 403 via the verbose log.
            guard detail.summary.assetType == .computer else {
                throw SupportTechnicianError.unsupportedAction
            }
            let managementID = try resolveManagementID(from: detail)
            _ = try await queueMDMCommand(commandType: "LOG_OUT_USER", managementID: managementID)
            return SupportActionResult(
                title: action.title,
                detail: "Log Out User command queued on \(detail.summary.displayName). The currently signed-in user is logged out at next MDM check-in.",
                sensitiveValue: nil
            )

        case .clearPasscode:
            guard detail.summary.assetType == .mobileDevice else {
                throw SupportTechnicianError.unsupportedAction
            }
            let managementID = try resolveManagementID(from: detail)
            _ = try await queueMDMCommand(commandType: "CLEAR_PASSCODE", managementID: managementID)
            return SupportActionResult(
                title: action.title,
                detail: "Clear Passcode command queued in Jamf Pro. The end user will be locked out until a new passcode is set.",
                sensitiveValue: nil
            )

        case .eraseDevice:
            switch detail.summary.assetType {
            case .computer:
                _ = try await requestWithPathFallback(
                    paths: [
                        "api/v1/computers-management/\(detail.summary.inventoryID)/erase"
                    ],
                    method: .post,
                    bodyCandidates: [nil, Data("{}".utf8)]
                )

                return SupportActionResult(
                    title: action.title,
                    detail: "Erase command submitted for the selected computer.",
                    sensitiveValue: nil
                )
            case .mobileDevice:
                let managementID = try resolveManagementID(from: detail)
                _ = try await queueMDMCommand(commandType: "ERASE_DEVICE", managementID: managementID)
                return SupportActionResult(
                    title: action.title,
                    detail: "Erase command queued for the selected mobile device.",
                    sensitiveValue: nil
                )
            }

        case .viewFileVaultPersonalRecoveryKey:
            guard detail.summary.assetType == .computer else {
                throw SupportTechnicianError.unsupportedAction
            }

            // Try each API version's filevault endpoint
            let data = try await requestWithPathFallback(
                paths: ComputerInventoryEndpointVersion.allCases.map {
                    "\($0.inventoryPathPrefix)/\(detail.summary.inventoryID)/filevault"
                },
                method: .get
            )

            let key = try extractSecretValue(
                from: data,
                preferredKeyFragments: [
                    "personalRecoveryKey",
                    "recoveryKey",
                    "individualRecoveryKey"
                ]
            )

            return SupportActionResult(
                title: action.title,
                detail: "Retrieved FileVault personal recovery key.",
                sensitiveValue: key
            )

        case .viewRecoveryLockPassword:
            guard detail.summary.assetType == .computer else {
                throw SupportTechnicianError.unsupportedAction
            }

            // 404 from this endpoint means no recovery lock has been set on
            // the device — not an error condition. Surface as an informative
            // result rather than a failure alert.
            do {
                let data = try await requestWithPathFallback(
                    paths: ComputerInventoryEndpointVersion.allCases.map {
                        "\($0.inventoryPathPrefix)/\(detail.summary.inventoryID)/view-recovery-lock-password"
                    },
                    method: .get
                )

                let password = try extractSecretValue(
                    from: data,
                    preferredKeyFragments: [
                        "recoveryLockPassword",
                        "password"
                    ]
                )

                return SupportActionResult(
                    title: action.title,
                    detail: "Retrieved recovery lock password.",
                    sensitiveValue: password
                )
            } catch let JamfFrameworkError.notFound(message)
                    where message.localizedCaseInsensitiveContains("recovery lock") {
                return SupportActionResult(
                    title: action.title,
                    detail: "No recovery lock password is set on this computer. Configure Recovery Lock via policy or an MDM command first.",
                    sensitiveValue: nil
                )
            }

        case .viewDeviceLockPIN:
            guard detail.summary.assetType == .computer else {
                throw SupportTechnicianError.unsupportedAction
            }

            // This endpoint returns the PIN of a previously-issued Device Lock
            // MDM command. If no Device Lock has ever been sent for this
            // device, Jamf returns 404 with body "No Device Lock command
            // found for device: <id>". That is NOT a failure — it's "feature
            // unused." Intercept the 404 and return an informative result
            // instead of throwing.
            do {
                let data = try await requestWithPathFallback(
                    paths: ComputerInventoryEndpointVersion.allCases.map {
                        "\($0.inventoryPathPrefix)/\(detail.summary.inventoryID)/view-device-lock-pin"
                    },
                    method: .get
                )

                let pin = try extractSecretValue(
                    from: data,
                    preferredKeyFragments: [
                        "pin",
                        "deviceLockPin"
                    ]
                )

                return SupportActionResult(
                    title: action.title,
                    detail: "Retrieved device lock PIN.",
                    sensitiveValue: pin
                )
            } catch let JamfFrameworkError.notFound(message)
                    where message.localizedCaseInsensitiveContains("device lock") {
                return SupportActionResult(
                    title: action.title,
                    detail: "No device lock PIN is available — no Device Lock MDM command has been issued for this computer. Send a Device Lock command from Jamf Pro first, then revisit this action to retrieve the PIN.",
                    sensitiveValue: nil
                )
            }

        case .viewLAPSAccountPassword:
            guard detail.summary.assetType == .computer else {
                throw SupportTechnicianError.unsupportedAction
            }

            // Resolve the LAPS account, then fetch its password
            let clientManagementID = try resolveClientManagementID(from: detail)
            let account = try await resolvePreferredLAPSAccount(for: clientManagementID)
            let password = try await fetchLAPSPassword(
                clientManagementID: clientManagementID,
                accountName: account.username,
                passwordGUID: account.passwordGUID
            )

            return SupportActionResult(
                title: action.title,
                detail: "Retrieved LAPS password for \(account.username).",
                sensitiveValue: password
            )

        case .rotateLAPSPassword:
            guard detail.summary.assetType == .computer else {
                throw SupportTechnicianError.unsupportedAction
            }

            let clientManagementID = try resolveClientManagementID(from: detail)
            _ = try await requestWithPathFallback(
                paths: [
                    "api/v2/local-admin-password/\(clientManagementID)/set-password"
                ],
                method: .put,
                bodyCandidates: [nil, Data("{}".utf8)]
            )

            return SupportActionResult(
                title: action.title,
                detail: "Requested LAPS password rotation for this computer.",
                sensitiveValue: nil
            )

        case .enableBluetooth:
            // Classic API only — v2 has no equivalent.
            //   POST /JSSResource/computercommands/command/SettingsEnableBluetooth/id/{id}
            //   POST /JSSResource/mobiledevicecommands/command (XML body with command=Settings, EnableBluetooth)
            return try await queueBluetoothCommand(detail: detail, enable: true)

        case .disableBluetooth:
            return try await queueBluetoothCommand(detail: detail, enable: false)

        case .enableLostMode:
            // Mobile only, requires supervised device. v2 commandType
            //   ENABLE_LOST_MODE — Jamf accepts the minimal payload without
            //   message/phoneNumber/footnote; supplying them would require
            //   additional sheet UI which isn't in scope here.
            guard detail.summary.assetType == .mobileDevice else {
                throw SupportTechnicianError.unsupportedAction
            }
            let managementID = try resolveManagementID(from: detail)
            _ = try await queueMDMCommand(commandType: "ENABLE_LOST_MODE", managementID: managementID)
            return SupportActionResult(
                title: action.title,
                detail: "Lost Mode enable command queued. The device locks at next MDM check-in.",
                sensitiveValue: nil
            )

        case .disableLostMode:
            guard detail.summary.assetType == .mobileDevice else {
                throw SupportTechnicianError.unsupportedAction
            }
            let managementID = try resolveManagementID(from: detail)
            _ = try await queueMDMCommand(commandType: "DISABLE_LOST_MODE", managementID: managementID)
            return SupportActionResult(
                title: action.title,
                detail: "Lost Mode disable command queued in Jamf Pro.",
                sensitiveValue: nil
            )

        case .playLostModeSound:
            guard detail.summary.assetType == .mobileDevice else {
                throw SupportTechnicianError.unsupportedAction
            }
            let managementID = try resolveManagementID(from: detail)
            _ = try await queueMDMCommand(commandType: "PLAY_LOST_MODE_SOUND", managementID: managementID)
            return SupportActionResult(
                title: action.title,
                detail: "Lost Mode sound command queued. Device must already be in Lost Mode for this to take effect.",
                sensitiveValue: nil
            )

        case .requestDeviceLocation:
            guard detail.summary.assetType == .mobileDevice else {
                throw SupportTechnicianError.unsupportedAction
            }
            let managementID = try resolveManagementID(from: detail)
            _ = try await queueMDMCommand(commandType: "DEVICE_LOCATION", managementID: managementID)
            return SupportActionResult(
                title: action.title,
                detail: "Location query queued. Result appears in the device's Jamf Pro inventory on next check-in.",
                sensitiveValue: nil
            )

        case .clearRestrictionsPassword:
            guard detail.summary.assetType == .mobileDevice else {
                throw SupportTechnicianError.unsupportedAction
            }
            let managementID = try resolveManagementID(from: detail)
            _ = try await queueMDMCommand(commandType: "CLEAR_RESTRICTIONS_PASSWORD", managementID: managementID)
            return SupportActionResult(
                title: action.title,
                detail: "Restrictions password clear command queued in Jamf Pro.",
                sensitiveValue: nil
            )

        case .refreshCellularPlans:
            guard detail.summary.assetType == .mobileDevice else {
                throw SupportTechnicianError.unsupportedAction
            }
            let managementID = try resolveManagementID(from: detail)
            _ = try await queueMDMCommand(commandType: "REFRESH_CELLULAR_PLANS", managementID: managementID)
            return SupportActionResult(
                title: action.title,
                detail: "Cellular plan refresh queued in Jamf Pro.",
                sensitiveValue: nil
            )

        case .scheduleOSUpdate:
            // Routes through `/api/v1/managed-software-updates/plans`
            // for both platforms. This tenant has the "Managed
            // Software Update Plans" toggle enabled in Jamf Pro
            // Settings, which Jamf uses to gate the legacy
            // ScheduleOSUpdate command path. When the toggle is on,
            // every Classic ScheduleOSUpdate request — both the URL
            // form (`/command/ScheduleOSUpdate/InstallAction/...`)
            // and the XML-body form (`<command>ScheduleOSUpdate
            // </command>` posted to `/command`) — returns 503 with
            // the message "This endpoint cannot be used if the
            // Managed Software Update Plans toggle is on." The Wi-Fi
            // and Bluetooth `Settings` commands posted to the same
            // `/command` URL continue to work because the toggle
            // only blocks ScheduleOSUpdate specifically — not the
            // whole endpoint.
            //
            // The modern path requires the privilege "Create Managed
            // Software Updates", which was added to the QA-Tool API
            // role after the 503 trail surfaced it.
            //
            // History (so future maintainers don't repeat the loop):
            //   1. v3.22.7 used v2 MDM commands with
            //      `commandType: SCHEDULE_OS_UPDATE` — 400
            //      INVALID_FIELD (not in v2 command list).
            //   2. Classic URL-form ScheduleOSUpdate (Accept JSON) —
            //      401 (Plans toggle blocks it; surfaced as 401 on
            //      the JSON-Accept path).
            //   3. `api/v1/mobile-device-software-updates/send-
            //      updates` — 404 (path not on this Jamf Pro).
            //   4. Unified `api/v1/managed-software-updates/plans` —
            //      403 INVALID_PRIVILEGE (role lacked "Create
            //      Managed Software Updates").
            //   5. Classic URL-form ScheduleOSUpdate (Accept XML) —
            //      503 with the Plans-toggle disablement message.
            //   6. Classic XML-body ScheduleOSUpdate (POST to
            //      `/command`) — 503, same message. Jamf detects the
            //      `<command>ScheduleOSUpdate</command>` element and
            //      blocks it regardless of URL form.
            //   7. This (current) implementation — back to
            //      `managed-software-updates/plans` now that the role
            //      has "Create Managed Software Updates".
            //
            // Body shape per Jamf Pro 11.x docs:
            //   {
            //     "devices": [{"objectType": "MOBILE_DEVICE"|"COMPUTER",
            //                  "deviceId": "<inventoryId>"}],
            //     "config":  {"updateAction": "DOWNLOAD_INSTALL_ALLOW_DEFERRAL",
            //                 "versionType": "LATEST_ANY"}
            //   }
            //
            // `updateAction: DOWNLOAD_INSTALL_ALLOW_DEFERRAL` matches
            // the v3.22.7 button label "Schedule the next OS update
            // install" — device downloads, prompts the user, and
            // allows deferral. `versionType: LATEST_ANY` lets Jamf
            // pick the latest GM for the device.
            let objectType: String
            switch detail.summary.assetType {
            case .mobileDevice:
                objectType = "MOBILE_DEVICE"
            case .computer:
                objectType = "COMPUTER"
            }

            let planBody: [String: Any] = [
                "devices": [
                    [
                        "objectType": objectType,
                        "deviceId": detail.summary.inventoryID
                    ]
                ],
                "config": [
                    "updateAction": "DOWNLOAD_INSTALL_ALLOW_DEFERRAL",
                    "versionType": "LATEST_ANY"
                ]
            ]
            let planBodyData = try JSONSerialization.data(withJSONObject: planBody, options: [])

            await diagnosticsReporter.report(
                source: "module.support-technician",
                category: "management",
                severity: .info,
                message: "Scheduling OS update via managed-software-updates plan.",
                metadata: [
                    "asset_type": detail.summary.assetType.rawValue,
                    "inventory_id": detail.summary.inventoryID,
                    "endpoint": "api/v1/managed-software-updates/plans",
                    "object_type": objectType,
                    "update_action": "DOWNLOAD_INSTALL_ALLOW_DEFERRAL",
                    "version_type": "LATEST_ANY",
                    "privilege": "Create Managed Software Updates"
                ]
            )

            _ = try await apiGateway.request(
                path: "api/v1/managed-software-updates/plans",
                method: .post,
                body: planBodyData
            )

            return SupportActionResult(
                title: action.title,
                detail: "OS update plan queued via managed-software-updates. The device downloads and prompts the user to install at next check-in.",
                sensitiveValue: nil
            )

        case .settingsSync:
            // Generic SETTINGS no-op sync — useful when other Settings-
            // family commands (Bluetooth, Wi-Fi, etc.) don't apply but
            // the tech wants to force a Settings payload exchange.
            let managementID = try resolveManagementID(from: detail)
            _ = try await queueMDMCommand(commandType: "SETTINGS", managementID: managementID)
            return SupportActionResult(
                title: action.title,
                detail: "Settings sync queued in Jamf Pro.",
                sensitiveValue: nil
            )

        case .enableWifi:
            return try await queueWifiCommand(detail: detail, enable: true)
        case .disableWifi:
            return try await queueWifiCommand(detail: detail, enable: false)

        case .viewJamfManagementAccountPassword:
            // Jamf's historical "jssmanage" account is now managed via
            // the same LAPS endpoint as other local admin accounts; the
            // account name is the only thing that differs. Reuse the
            // existing `fetchLAPSPassword` helper with "jssmanage" as the
            // explicit account name.
            guard detail.summary.assetType == .computer else {
                throw SupportTechnicianError.unsupportedAction
            }
            let clientManagementID = try resolveClientManagementID(from: detail)
            let password = try await fetchLAPSPassword(
                clientManagementID: clientManagementID,
                accountName: "jssmanage",
                passwordGUID: nil
            )
            return SupportActionResult(
                title: action.title,
                detail: "Retrieved current password for the legacy jssmanage local admin account on \(detail.summary.displayName). The password is shown once; save it now if you need it.",
                sensitiveValue: password
            )

        case .enableFileVault, .redeployManagementFramework:
            // Macs only. POST /api/v1/jamf-management-framework/redeploy/{computerId}
            // re-runs the Jamf binary management framework, which
            // re-applies every assigned configuration profile and
            // policy — including the FileVault disk-encryption
            // configuration profile. There is no single-shot MDM
            // command for "Enable FileVault" — Apple requires it be
            // delivered via a profile, and the redeploy endpoint is
            // the documented way to force re-application of that
            // profile from the API.
            guard detail.summary.assetType == .computer else {
                throw SupportTechnicianError.unsupportedAction
            }
            let computerID = detail.summary.inventoryID
            _ = try await apiGateway.request(
                path: "api/v1/jamf-management-framework/redeploy/\(computerID)",
                method: .post,
                body: nil
            )
            let detailText: String
            if action == .enableFileVault {
                detailText = "Management framework redeploy queued. The Jamf binary re-runs at next check-in and re-applies the device's FileVault configuration profile; enrolment progresses according to that profile's settings."
            } else {
                detailText = "Management framework redeploy queued. The Jamf binary re-runs at the next check-in and re-applies every assigned configuration profile + policy."
            }
            return SupportActionResult(
                title: action.title,
                detail: detailText,
                sensitiveValue: nil
            )
        }
    }

    /// Sends a Classic-API Wi-Fi toggle command — same Classic-only
    /// pattern as `queueBluetoothCommand`.
    private func queueWifiCommand(
        detail: SupportDeviceDetail,
        enable: Bool
    ) async throws -> SupportActionResult {
        let verb = enable ? "Enable" : "Disable"
        switch detail.summary.assetType {
        case .computer:
            let suffix = enable ? "SettingsEnableWifi" : "SettingsDisableWifi"
            let path = "JSSResource/computercommands/command/\(suffix)/id/\(detail.summary.inventoryID)"
            _ = try await apiGateway.request(path: path, method: .post, body: nil)
            return SupportActionResult(
                title: enable ? "Turn On Wi-Fi" : "Turn Off Wi-Fi",
                detail: "\(verb) Wi-Fi command queued for this Mac via Classic API.",
                sensitiveValue: nil
            )

        case .mobileDevice:
            let xml = """
            <mobile_device_command>
              <general>
                <command>Settings</command>
              </general>
              <settings>
                <wifi>\(enable ? "true" : "false")</wifi>
              </settings>
              <mobile_devices>
                <mobile_device><id>\(detail.summary.inventoryID)</id></mobile_device>
              </mobile_devices>
            </mobile_device_command>
            """
            _ = try await apiGateway.request(
                path: "JSSResource/mobiledevicecommands/command",
                method: .post,
                body: xml.data(using: .utf8)
            )
            return SupportActionResult(
                title: enable ? "Turn On Wi-Fi" : "Turn Off Wi-Fi",
                detail: "\(verb) Wi-Fi command queued for this iOS/iPadOS device. Requires supervision.",
                sensitiveValue: nil
            )
        }
    }

    /// Sends a Classic-API Bluetooth toggle command.
    ///
    /// - macOS: `POST /JSSResource/computercommands/command/Settings{Enable|Disable}Bluetooth/id/{id}`
    /// - iOS:   `POST /JSSResource/mobiledevicecommands/command/Settings/id/{id}` with XML body
    ///   containing `<bluetooth>true|false</bluetooth>` in `<settings>`.
    ///
    /// Returns a `SupportActionResult` describing the outcome. Throws on
    /// authentication/network failure so the lifecycle indicator turns red
    /// and the verbose error popup explains the reason.
    private func queueBluetoothCommand(
        detail: SupportDeviceDetail,
        enable: Bool
    ) async throws -> SupportActionResult {
        let verb = enable ? "Enable" : "Disable"

        switch detail.summary.assetType {
        case .computer:
            let suffix = enable ? "SettingsEnableBluetooth" : "SettingsDisableBluetooth"
            let path = "JSSResource/computercommands/command/\(suffix)/id/\(detail.summary.inventoryID)"
            _ = try await apiGateway.request(path: path, method: .post, body: nil)
            return SupportActionResult(
                title: enable ? "Turn On Bluetooth" : "Turn Off Bluetooth",
                detail: "\(verb) Bluetooth command queued for this Mac via Classic API. macOS 10.13.4+ required.",
                sensitiveValue: nil
            )

        case .mobileDevice:
            // Classic mobile command — Settings payload with bluetooth toggle.
            // Supervised devices only; unsupervised will return 200 but ignore.
            let xml = """
            <mobile_device_command>
              <general>
                <command>Settings</command>
              </general>
              <settings>
                <bluetooth>\(enable ? "true" : "false")</bluetooth>
              </settings>
              <mobile_devices>
                <mobile_device><id>\(detail.summary.inventoryID)</id></mobile_device>
              </mobile_devices>
            </mobile_device_command>
            """
            _ = try await apiGateway.request(
                path: "JSSResource/mobiledevicecommands/command",
                method: .post,
                body: xml.data(using: .utf8)
            )
            return SupportActionResult(
                title: enable ? "Turn On Bluetooth" : "Turn Off Bluetooth",
                detail: "\(verb) Bluetooth command queued for this iOS/iPadOS device. Requires supervision; unsupervised devices ignore the command silently.",
                sensitiveValue: nil
            )
        }
    }

    // MARK: - Computer Search

    /// Searches for computers matching the query by trying wildcard then exact RSQL
    /// filters across all API endpoint versions.
    ///
    /// Falls back through endpoint versions and filter strategies until a successful
    /// response is received or all options are exhausted.
    private func searchComputers(query: String) async throws -> [SupportSearchResult] {
        let escapedQuery = escapeRSQLString(query)
        let wildcardFilter = buildComputerFilter(withEscapedQuery: escapedQuery, useWildcard: true)
        let exactFilter = buildComputerFilter(withEscapedQuery: escapedQuery, useWildcard: false)

        var lastError: (any Error)?

        for endpointVersion in ComputerInventoryEndpointVersion.allCases {
            for (index, filter) in [wildcardFilter, exactFilter].enumerated() {
                do {
                    // Page loop: accumulate results across all pages until a
                    // page returns fewer records than the page size (Jamf's
                    // end-of-results signal). Previously the first page was
                    // the only page fetched — tenants with >200 matching
                    // computers saw silently truncated results.
                    var allResults: [SupportSearchResult] = []
                    var page = 0
                    while true {
                        let data = try await requestComputerInventory(
                            endpointVersion: endpointVersion,
                            filter: filter,
                            includeSections: true,
                            page: page
                        )
                        let pageResults = try parseComputerSearchResults(from: data)
                        allResults.append(contentsOf: pageResults)

                        if pageResults.count < Self.supportComputerPageSize || pageResults.isEmpty {
                            return allResults
                        }

                        page += 1
                        // Safety cap: 50 pages × 200 = 10k records.
                        if page >= 50 { return allResults }
                    }
                } catch {
                    lastError = error

                    // If wildcard failed with 400, try exact filter next
                    if index == 0,
                       isNetworkFailure(error, statusCode: 400)
                    {
                        continue
                    }

                    // If this endpoint version is not supported, try the next one
                    if shouldTryNextComputerEndpoint(after: error) {
                        break
                    }
                }
            }
        }

        throw lastError ?? JamfFrameworkError.authenticationFailed
    }

    /// Executes a paginated computer inventory search request.
    ///
    /// Requests standard inventory sections (General, Hardware, OS, etc.) to populate
    /// search result fields. Falls back to a section-less request if the server
    /// rejects the section parameters with a 400 error.
    /// Page size used for computer searches in the Support Technician module.
    private static let supportComputerPageSize = 200

    private func requestComputerInventory(
        endpointVersion: ComputerInventoryEndpointVersion,
        filter: String,
        includeSections: Bool,
        page: Int = 0
    ) async throws -> Data {
        let sections = [
            "GENERAL",
            "HARDWARE",
            "OPERATING_SYSTEM",
            "USER_AND_LOCATION",
            "SECURITY",
            "DISK_ENCRYPTION"
        ]

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "page-size", value: String(Self.supportComputerPageSize)),
            URLQueryItem(name: "sort", value: "general.name:asc"),
            URLQueryItem(name: "filter", value: filter)
        ]

        if includeSections {
            queryItems.append(contentsOf: sections.map { URLQueryItem(name: "section", value: $0) })
        }

        do {
            return try await apiGateway.request(
                path: endpointVersion.searchPath,
                method: .get,
                queryItems: queryItems
            )
        } catch {
            // Retry without sections if the server rejected the section parameters
            if includeSections,
               isNetworkFailure(error, statusCode: 400)
            {
                return try await requestComputerInventory(
                    endpointVersion: endpointVersion,
                    filter: filter,
                    includeSections: false,
                    page: page
                )
            }

            throw error
        }
    }

    /// Parses computer search results from raw inventory API response data.
    ///
    /// Handles multiple JSON key paths for each field to support different
    /// Jamf Pro response formats across API versions.
    private func parseComputerSearchResults(from data: Data) throws -> [SupportSearchResult] {
        let object = try jsonObject(from: data)
        let dictionaries = dictionaryArray(from: object)

        return dictionaries.compactMap { dictionary in
            let inventoryID = extractString(
                using: ["id", "general.id", "computerId"],
                from: dictionary
            )

            let serialNumber = extractString(
                using: ["hardware.serialNumber", "serialNumber", "general.serialNumber"],
                from: dictionary
            )

            // Both inventory ID and serial number are required for a valid result
            guard let inventoryID, let serialNumber else {
                return nil
            }

            let displayName =
                extractString(using: ["general.name", "computerName", "name"], from: dictionary) ??
                serialNumber

            let managementID = extractString(
                using: ["general.managementId", "managementId", "clientManagementId"],
                from: dictionary
            )

            return SupportSearchResult(
                assetType: .computer,
                inventoryID: inventoryID,
                managementID: managementID,
                clientManagementID: managementID,
                displayName: displayName,
                serialNumber: serialNumber,
                username: extractString(using: ["userAndLocation.username", "username"], from: dictionary),
                email: extractString(using: ["userAndLocation.email", "email"], from: dictionary),
                model: extractString(using: ["hardware.model", "model", "hardware.modelIdentifier"], from: dictionary),
                osVersion: extractString(using: ["operatingSystem.version", "osVersion"], from: dictionary),
                lastInventoryUpdate: extractString(
                    using: ["general.reportDate", "general.lastContactTime", "reportDate", "lastContactTime"],
                    from: dictionary
                ),
                prestageEnrollment: nil,
                automatedDeviceEnrollment: nil
            )
        }
    }

    // MARK: - Mobile Device Search

    /// Searches for mobile devices matching the query using wildcard then exact RSQL filters.
    private func searchMobileDevices(query: String) async throws -> [SupportSearchResult] {
        // Delegate to the shared RSQL helper so the grammar lives in
        // one tested place (see `JamfRSQLFilter`). Force-unwrap the
        // helper's Optional: callers here always pass a non-empty
        // trimmed query (validated by `searchAssets`), so the helper
        // never returns nil at this site.
        guard
            let wildcardFilter = JamfRSQLFilter.serialOrUsername(query: query, useWildcard: true),
            let exactFilter = JamfRSQLFilter.serialOrUsername(query: query, useWildcard: false)
        else {
            return []
        }

        var lastError: (any Error)?

        for (index, filter) in [wildcardFilter, exactFilter].enumerated() {
            do {
                // Page loop. Same rationale as the computer search above:
                // stop when a page returns fewer items than the page size.
                var allResults: [SupportSearchResult] = []
                var page = 0
                while true {
                    let data = try await requestMobileInventory(filter: filter, page: page)
                    let pageResults = try parseMobileSearchResults(from: data)
                    allResults.append(contentsOf: pageResults)

                    // Ground-truth diagnostics: dump the exact bulk body and log
                    // which devices yielded a PreStage from the search dict. This
                    // makes it unambiguous whether the bulk `general` section
                    // carries `enrollmentMethodPrestage` for a given device.
                    if page == 0 {
                        Self.dumpPayloadForDiagnostics(
                            rawJSON: String(data: data, encoding: .utf8) ?? "",
                            deviceID: pageResults.first?.inventoryID ?? "query",
                            kind: "mobile-search-payload"
                        )
                        let withPrestage = pageResults.filter { $0.prestageEnrollment != nil }
                        let sample = pageResults.prefix(8)
                            .map { "\($0.serialNumber)=\($0.prestageEnrollment ?? "nil")" }
                            .joined(separator: ";")
                        await diagnosticsReporter.report(
                            source: "module.support-technician",
                            category: "prestage",
                            severity: .info,
                            message: "Parsed mobile search results for PreStage display.",
                            metadata: [
                                "result_count": String(pageResults.count),
                                "with_prestage_count": String(withPrestage.count),
                                "sample": sample
                            ]
                        )
                    }

                    if pageResults.count < Self.supportMobilePageSize || pageResults.isEmpty {
                        return allResults
                    }

                    page += 1
                    if page >= 50 { return allResults }
                }
            } catch {
                lastError = error

                if index == 0,
                   isNetworkFailure(error, statusCode: 400)
                {
                    continue
                }
            }
        }

        throw lastError ?? JamfFrameworkError.authenticationFailed
    }

    /// Page size used for mobile device searches in the Support Technician module.
    private static let supportMobilePageSize = 200

    /// Executes a mobile device inventory search, trying modern section names first,
    /// then legacy names, then no sections at all.
    private func requestMobileInventory(filter: String, page: Int = 0) async throws -> Data {
        var lastError: (any Error)?

        for mode in SectionEncodingMode.allCases {
            var queryItems: [URLQueryItem] = [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "page-size", value: String(Self.supportMobilePageSize)),
                URLQueryItem(name: "sort", value: "displayName:asc"),
                URLQueryItem(name: "filter", value: filter)
            ]

            switch mode {
            case .modern:
                queryItems.append(contentsOf: [
                    URLQueryItem(name: "section", value: "GENERAL"),
                    URLQueryItem(name: "section", value: "USER_AND_LOCATION"),
                    URLQueryItem(name: "section", value: "HARDWARE"),
                    URLQueryItem(name: "section", value: "APPLICATIONS")
                ])
            case .legacy:
                queryItems.append(contentsOf: [
                    URLQueryItem(name: "section", value: "GENERAL"),
                    URLQueryItem(name: "section", value: "LOCATION"),
                    URLQueryItem(name: "section", value: "HARDWARE"),
                    URLQueryItem(name: "section", value: "APPLICATIONS")
                ])
            case .none:
                break
            }

            do {
                return try await apiGateway.request(
                    path: "api/v2/mobile-devices/detail",
                    method: .get,
                    queryItems: queryItems
                )
            } catch {
                lastError = error

                // If this mode fails for non-section reasons, stop trying
                if mode == .none || isSectionParameterError(error) == false {
                    throw error
                }
            }
        }

        throw lastError ?? JamfFrameworkError.authenticationFailed
    }

    /// Parses mobile device search results from raw API response data.
    private func parseMobileSearchResults(from data: Data) throws -> [SupportSearchResult] {
        let object = try jsonObject(from: data)
        let dictionaries = dictionaryArray(from: object)

        return dictionaries.compactMap { dictionary in
            let inventoryID = extractString(
                using: ["id", "mobileDeviceId", "deviceId", "general.id"],
                from: dictionary
            )

            let serialNumber = extractString(
                using: ["serialNumber", "hardware.serialNumber", "general.serialNumber"],
                from: dictionary
            )

            guard let inventoryID, let serialNumber else {
                return nil
            }

            let displayName =
                extractString(
                    using: ["general.displayName", "general.name", "deviceName", "displayName", "name"],
                    from: dictionary
                ) ??
                serialNumber

            let managementID = extractString(
                using: ["general.managementId", "managementId", "clientManagementId"],
                from: dictionary
            )

            return SupportSearchResult(
                assetType: .mobileDevice,
                inventoryID: inventoryID,
                managementID: managementID,
                clientManagementID: managementID,
                displayName: displayName,
                serialNumber: serialNumber,
                username: extractString(using: ["userAndLocation.username", "username", "location.username"], from: dictionary),
                email: extractString(using: ["userAndLocation.emailAddress", "emailAddress", "location.email"], from: dictionary),
                model: extractString(using: ["hardware.model", "model", "modelIdentifier"], from: dictionary),
                osVersion: extractString(using: ["general.osVersion", "osVersion"], from: dictionary),
                lastInventoryUpdate: extractString(
                    using: [
                        "general.lastInventoryUpdateDate",
                        "general.lastInventoryUpdate",
                        "lastInventoryUpdateDate",
                        "lastInventoryUpdate"
                    ],
                    from: dictionary
                ),
                // The per-id mobile detail endpoint carries NO PreStage, but the
                // bulk `mobile-devices/detail` search dict does, under
                // `general.enrollmentMethodPrestage` — the same source the Mobile
                // Device Search module reads. Extract it here so the General frame
                // can display it the way the Mac path reads it from inventory.
                prestageEnrollment: SupportTechnicianPrestageParser.displayValue(from: dictionary),
                automatedDeviceEnrollment: nil
            )
        }
    }

    // MARK: - Detail Fetching

    /// Fetches the raw JSON payload for a device detail, trying multiple API paths
    /// based on device type and API version.
    private func fetchRawDetailPayload(for result: SupportSearchResult) async throws -> [String: Any] {
        switch result.assetType {
        case .computer:
            let data = try await fetchComputerDetailPayload(inventoryID: result.inventoryID)
            return try rootDictionary(from: data)

        case .mobileDevice:
            // The v2 mobile-devices detail endpoint returns ONLY the `general`
            // section unless explicit `section=` query items are supplied. The
            // redesigned Technician Module reads Hardware, Security, Network,
            // Applications, Profiles, Certificates, and Extension Attributes
            // — all of which live in their own sections — so they must be
            // requested here. Without these query items every non-General frame
            // showed "no data reported", which was the bug behind the user's
            // "all data is missing" report.
            let sectionQueryItems = Self.mobileDeviceDetailSections.map {
                URLQueryItem(name: "section", value: $0)
            }
            let data = try await requestWithPathFallback(
                paths: [
                    "api/v2/mobile-devices/\(result.inventoryID)/detail",
                    "api/v2/mobile-devices/\(result.inventoryID)",
                    "api/v2/mobile-devices/detail/\(result.inventoryID)"
                ],
                method: .get,
                queryItems: sectionQueryItems
            )

            return try rootDictionary(from: data)
        }
    }

    /// Inventory sections requested when fetching a mobile device detail.
    /// Mirrors the section enum used by `MobileDeviceInventorySection` in the
    /// Mobile Device Search module. Missing any of these means the
    /// corresponding category frame renders an empty-state placeholder.
    private static let mobileDeviceDetailSections = [
        "GENERAL",
        "HARDWARE",
        "USER_AND_LOCATION",
        "PURCHASING",
        "SECURITY",
        "APPLICATIONS",
        "EBOOKS",
        "NETWORK",
        "SERVICE_SUBSCRIPTIONS",
        "CERTIFICATES",
        "CONFIGURATION_PROFILES",
        "USER_PROFILES",
        "PROVISIONING_PROFILES",
        "SHARED_USERS",
        "EXTENSION_ATTRIBUTES",
        "MOBILE_DEVICE_GROUPS"
    ]

    /// The inventory sections requested when falling back to the non-detail
    /// `computers-inventory/{id}` endpoint, which returns only `GENERAL` by default.
    private static let computerInventoryDetailSections = [
        "GENERAL",
        "HARDWARE",
        "OPERATING_SYSTEM",
        "USER_AND_LOCATION",
        "APPLICATIONS",
        "SECURITY",
        "DISK_ENCRYPTION",
        "CONFIGURATION_PROFILES",
        "LOCAL_USER_ACCOUNTS",
        "CERTIFICATES",
        "GROUP_MEMBERSHIPS",
        "EXTENSION_ATTRIBUTES",
        // Added in 3.22.7 — these sections weren't being requested so
        // storage / purchasing / software updates / content caching were
        // returning as `null` even on Macs that report them.
        "STORAGE",
        "PURCHASING",
        "SOFTWARE_UPDATES",
        "CONTENT_CACHING",
        "PRINTERS",
        "SERVICES",
        "LICENSED_SOFTWARE",
        "PACKAGE_RECEIPTS",
        "FONTS",
        "IBEACONS",
        "ATTACHMENTS",
        "PLUGINS"
    ]

    /// Fetches a computer's full detail payload, preferring the all-sections
    /// `computers-inventory-detail/{id}` endpoint and falling back to
    /// `computers-inventory/{id}` with explicit section query items when the
    /// detail endpoint is forbidden or unavailable.
    private func fetchComputerDetailPayload(inventoryID: String) async throws -> Data {
        let sectionQueryItems = Self.computerInventoryDetailSections.map {
            URLQueryItem(name: "section", value: $0)
        }

        var lastError: (any Error)?

        for endpointVersion in ComputerInventoryEndpointVersion.allCases {
            let attempts: [(path: String, queryItems: [URLQueryItem])] = [
                ("\(endpointVersion.inventoryPathPrefix)/\(inventoryID)", sectionQueryItems),
                ("\(endpointVersion.detailPathPrefix)/\(inventoryID)", [])
            ]

            for attempt in attempts {
                do {
                    return try await apiGateway.request(
                        path: attempt.path,
                        method: .get,
                        queryItems: attempt.queryItems
                    )
                } catch {
                    lastError = error

                    if shouldTryNextPath(after: error) {
                        continue
                    }

                    throw error
                }
            }
        }

        throw lastError ?? JamfFrameworkError.authenticationFailed
    }

    // MARK: - Application Manager (v3.18+) — Installed applications fetch

    /// Fetches the applications currently installed on a specific Mac, as
    /// reported by Jamf Pro's `APPLICATIONS` inventory section.
    ///
    /// This is the data source for the Application Manager view. The record
    /// is derived exclusively from `GET /api/v1/computers-inventory/{id}?section=APPLICATIONS`;
    /// no catalog data, no install-state inference, no deploy-package lookup.
    ///
    /// Endpoint-version fallback (v3 → v2 → v1) mirrors `fetchComputerDetailPayload`
    /// so tenants that restrict newer endpoints still get a usable response.
    ///
    /// Emits a diagnostics event on success (category `application-manager`,
    /// severity `.info`, metadata: `inventory_id`, `count`) and an error event
    /// on failure (severity `.error`, metadata: `inventory_id`, plus the
    /// parsed error description).
    ///
    /// - Parameter inventoryID: Jamf Pro inventory record ID of the target
    ///   computer.
    /// - Returns: Sorted, deduplicated array of `DeviceApplication` records.
    ///   Empty array is a valid return value (the Mac truly has no
    ///   applications reported, or the payload resolves to an empty list) —
    ///   the caller must not treat empty as an error.
    /// - Throws: `JamfFrameworkError.networkFailure`, `.decodingFailure`, or
    ///   `SupportTechnicianError.unsupportedResponseShape` if every endpoint
    ///   version fails.
    func fetchInstalledApplications(
        inventoryID: String
    ) async throws -> [DeviceApplication] {
        let applicationsSection = [URLQueryItem(name: "section", value: "APPLICATIONS")]

        var lastError: (any Error)?

        for endpointVersion in ComputerInventoryEndpointVersion.allCases {
            // Primary: paginated inventory endpoint with section filter.
            // Fallback within the same version: the detail endpoint (no section filter).
            let attempts: [(path: String, queryItems: [URLQueryItem])] = [
                ("\(endpointVersion.inventoryPathPrefix)/\(inventoryID)", applicationsSection),
                ("\(endpointVersion.detailPathPrefix)/\(inventoryID)", [])
            ]

            for attempt in attempts {
                do {
                    let data = try await apiGateway.request(
                        path: attempt.path,
                        method: .get,
                        queryItems: attempt.queryItems
                    )

                    let root = try rootDictionary(from: data)
                    let applications = parseDeviceApplications(from: root)

                    await diagnosticsReporter.report(
                        source: "module.support-technician",
                        category: "application-manager",
                        severity: .info,
                        message: "Loaded installed applications from Jamf Pro.",
                        metadata: [
                            "inventory_id": inventoryID,
                            "count": String(applications.count),
                            "endpoint": attempt.path
                        ]
                    )

                    return applications
                } catch {
                    lastError = error

                    if shouldTryNextPath(after: error) {
                        continue
                    }

                    throw error
                }
            }
        }

        let resolvedError = lastError ?? JamfFrameworkError.authenticationFailed
        await diagnosticsReporter.reportError(
            source: "module.support-technician",
            category: "application-manager",
            message: "Failed to load installed applications from Jamf Pro.",
            errorDescription: resolvedError.localizedDescription,
            metadata: [
                "inventory_id": inventoryID
            ]
        )

        throw resolvedError
    }

    /// Parses the `APPLICATIONS` inventory section out of the root computer
    /// dictionary, probing every known container path Jamf Pro has used in
    /// practice and extracting display name, version, path, and bundle ID
    /// per entry.
    ///
    /// The resulting records are deduplicated by `DeviceApplication.id` —
    /// which prefers `bundleIdentifier`, then `path`, then `displayName` —
    /// and sorted case-insensitively by `displayName` for stable UI rendering.
    ///
    /// Entries that lack even a display name are skipped; a record with no
    /// identifying handle would be unactionable in the UI.
    private func parseDeviceApplications(
        from dictionary: [String: Any]
    ) -> [DeviceApplication] {
        // Every path where Jamf Pro has, at some version, placed the
        // application array. Ordered most-specific-first so the modern
        // inventory shape wins.
        let applicationPathCandidates = [
            "applications",
            "applicationList",
            "general.applications",
            "softwareUpdates",
            "licensedSoftware",
            "software"
        ]

        var parsedByKey: [String: DeviceApplication] = [:]

        for path in applicationPathCandidates {
            guard let value = resolveValue(atPath: path, in: dictionary) else {
                continue
            }

            for record in dictionaryArray(from: value) {
                guard let parsed = parseDeviceApplication(from: record) else {
                    continue
                }

                // First occurrence wins. Later matches at less-specific paths
                // don't overwrite; this keeps the modern-inventory record
                // authoritative when multiple paths resolve on older tenants.
                if parsedByKey[parsed.id] == nil {
                    parsedByKey[parsed.id] = parsed
                }
            }

            // Fallback: payload was a flat array of names rather than dicts
            // (seen on some older classic-adjacent responses).
            if let values = value as? [Any] {
                for element in values {
                    guard let scalar = extractStringValue(from: element),
                          scalar.isEmpty == false
                    else {
                        continue
                    }

                    let synthetic = DeviceApplication(
                        id: scalar,
                        displayName: scalar,
                        version: nil,
                        path: nil,
                        bundleIdentifier: nil
                    )

                    if parsedByKey[synthetic.id] == nil {
                        parsedByKey[synthetic.id] = synthetic
                    }
                }
            }
        }

        return parsedByKey.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    /// Parses a single application-record dictionary into a `DeviceApplication`,
    /// tolerating Jamf Pro's field-name drift across versions. Returns `nil`
    /// when the record yields no display name — a record with no name is
    /// unactionable because the install/uninstall trigger is
    /// `install-<exact display name>` / `uninstall-<exact display name>`.
    private func parseDeviceApplication(
        from record: [String: Any]
    ) -> DeviceApplication? {
        let displayNamePaths = ["name", "displayName", "title"]
        let versionPaths = ["version", "appVersion", "shortVersion", "bundleVersion"]
        let pathPaths = ["path", "location", "installPath"]
        let bundleIDPaths = ["bundleId", "bundleIdentifier", "identifier"]

        guard let displayName = extractString(using: displayNamePaths, from: record),
              displayName.isEmpty == false
        else {
            return nil
        }

        let version = extractString(using: versionPaths, from: record)
        let path = extractString(using: pathPaths, from: record)
        let bundleIdentifier = extractString(using: bundleIDPaths, from: record)

        let id = bundleIdentifier ?? path ?? displayName

        return DeviceApplication(
            id: id,
            displayName: displayName,
            version: version,
            path: path,
            bundleIdentifier: bundleIdentifier
        )
    }

    // MARK: - Application Manager (v3.18+) — Script creation

    /// Uploads a one-shot zsh wrapper script to Jamf Pro via
    /// `POST /api/v1/scripts`.
    ///
    /// The script name embeds the action, application display name, target
    /// serial number, and an ISO-8601 timestamp — so repeated invocations
    /// never collide and the Jamf Pro scripts list stays audit-friendly.
    ///
    /// The script contents are defensive: they validate parameter 4 is
    /// present, confirm `/usr/local/bin/jamf` is executable, fire
    /// `jamf policy -trigger install-<appName>` (or `uninstall-<appName>`),
    /// and grep the verbose output for the Jamf "No policies were found"
    /// sentinel — exiting 20 on a missing trigger so the Jamf Pro policy
    /// log captures a clear failure rather than a silent success.
    ///
    /// - Parameters:
    ///   - action: `.install(appName:)` or `.uninstall(appName:)`.
    ///   - inventoryID: Jamf Pro inventory record ID of the target computer
    ///     (logged to diagnostics; not embedded in the script itself).
    ///   - serialNumber: Hardware serial of the target computer (embedded
    ///     in the script comment header so a Jamf Pro admin reading the
    ///     script log can match it against the intended target).
    ///   - deviceDisplayName: Display name of the target computer (embedded
    ///     in the script's `info` field for admin readability).
    ///   - timestamp: ISO-8601 timestamp to embed in script name + notes.
    ///     Callers pass a single timestamp shared between the script and
    ///     its paired one-shot policy so both records match.
    /// - Returns: The Jamf Pro script ID (String — regardless of whether
    ///   the API returned it as Int or String).
    /// - Throws: `SupportTechnicianError.unsupportedResponseShape` if the
    ///   response body doesn't carry an `id`; the underlying request error
    ///   otherwise.
    func createApplicationActionScript(
        action: ApplicationAction,
        inventoryID: String,
        serialNumber: String,
        deviceDisplayName: String,
        timestamp: String
    ) async throws -> String {
        let endpoint = "api/v1/scripts"
        let appName = action.appName
        let actionVerb = action.verb
        let name = "Dashboard \(actionVerb): \(appName) (\(timestamp)) [serial \(serialNumber)]"
        let scriptContents = generateApplicationActionScript(action: action, serialNumber: serialNumber)

        let payload: [String: Any] = [
            "name": name,
            "info": "Auto-added by Forsetti to \(actionVerb.lowercased()) \(appName) on \(deviceDisplayName) (serial \(serialNumber)). Safe to delete after the paired one-shot policy has executed.",
            "notes": "Custom-trigger wrapper. Parameter 4 = exact app display name. Fires \(action.customTrigger) on the target Mac. Generated \(timestamp).",
            "priority": "AFTER",
            "osRequirements": "",
            "parameter4": appName,
            "scriptContents": scriptContents
        ]

        let body = try JSONSerialization.data(withJSONObject: payload, options: [])
        let bodyPreview = String(data: body, encoding: .utf8).map { String($0.prefix(600)) } ?? "<non-utf8>"

        await diagnosticsReporter.report(
            source: "module.support-technician",
            category: "application-manager",
            severity: .info,
            message: "Creating one-shot \(actionVerb.lowercased()) wrapper script in Jamf Pro.",
            metadata: [
                "endpoint": endpoint,
                "method": "POST",
                "script_name": name,
                "action": actionVerb.lowercased(),
                "app_name": appName,
                "inventory_id": inventoryID,
                "serial_number": serialNumber,
                "custom_trigger": action.customTrigger,
                "body_preview": bodyPreview
            ]
        )

        let responseData: Data
        do {
            responseData = try await apiGateway.request(
                path: endpoint,
                method: .post,
                body: body
            )
        } catch {
            await diagnosticsReporter.reportError(
                source: "module.support-technician",
                category: "application-manager",
                message: "Failed to create \(actionVerb.lowercased()) wrapper script.",
                errorDescription: describe(error),
                metadata: [
                    "endpoint": endpoint,
                    "script_name": name,
                    "action": actionVerb.lowercased(),
                    "app_name": appName,
                    "inventory_id": inventoryID,
                    "serial_number": serialNumber
                ]
            )
            throw error
        }

        let scriptID = try extractScriptID(from: responseData)

        await diagnosticsReporter.report(
            source: "module.support-technician",
            category: "application-manager",
            severity: .info,
            message: "Created one-shot \(actionVerb.lowercased()) wrapper script.",
            metadata: [
                "endpoint": endpoint,
                "script_id": scriptID,
                "script_name": name,
                "action": actionVerb.lowercased(),
                "app_name": appName,
                "inventory_id": inventoryID,
                "serial_number": serialNumber
            ]
        )

        return scriptID
    }

    /// Extracts the script ID from a `POST /api/v1/scripts` response body.
    /// The modern API returns `{"id": <Int-or-String>}`, but the shape is
    /// version-sensitive — checks both. Throws if the ID is missing or empty.
    private func extractScriptID(from data: Data) throws -> String {
        guard let object = try? jsonObject(from: data),
              let dict = object as? [String: Any]
        else {
            throw SupportTechnicianError.unsupportedResponseShape
        }

        if let intID = dict["id"] as? Int {
            let stringified = String(intID)
            guard stringified.isEmpty == false else {
                throw SupportTechnicianError.unsupportedResponseShape
            }
            return stringified
        }

        if let stringID = dict["id"] as? String {
            let trimmed = stringID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else {
                throw SupportTechnicianError.unsupportedResponseShape
            }
            return trimmed
        }

        throw SupportTechnicianError.unsupportedResponseShape
    }

    /// Builds the zsh wrapper script body for an install or uninstall action.
    ///
    /// The body is deliberately defensive: it validates parameter 4, checks
    /// that `/usr/local/bin/jamf` exists and is executable, runs
    /// `jamf policy -trigger <customTrigger> -verbose`, and greps the verbose
    /// output for the Jamf "No policies were found" sentinel — exiting 20
    /// so the Jamf Pro policy log marks a failure rather than a silent
    /// success when the admin hasn't configured a matching trigger.
    ///
    /// Exit codes:
    /// - 10: parameter 4 (app name) missing
    /// - 11: /usr/local/bin/jamf missing or not executable
    /// - 20: no policies matched the custom trigger on Jamf Pro
    /// - other non-zero: whatever `jamf policy` itself returned
    private func generateApplicationActionScript(
        action: ApplicationAction,
        serialNumber: String
    ) -> String {
        let verb = action.verb.lowercased()
        // The custom-trigger prefix embeds the action (install- / uninstall-).
        // parameter 4 supplies the exact app display name at run time.
        let triggerPrefix = (action.customTrigger.hasPrefix("install-") ? "install-" : "uninstall-")

        return """
        #!/bin/zsh
        # Forsetti one-shot \(verb) wrapper.
        # parameter 4 = exact application display name (required)
        # Intended target serial: \(serialNumber)
        set -euo pipefail

        APP_NAME="${4:-}"
        if [[ -z "${APP_NAME}" ]]; then
          echo "ERROR: parameter 4 (app name) is required" >&2
          exit 10
        fi

        JAMF_BIN="/usr/local/bin/jamf"
        if [[ ! -x "${JAMF_BIN}" ]]; then
          echo "ERROR: ${JAMF_BIN} not found or not executable" >&2
          exit 11
        fi

        ACTUAL_SERIAL="$(ioreg -l | awk '/IOPlatformSerialNumber/ { gsub(/"/, "", $4); print $4 }')"
        TRIGGER="\(triggerPrefix)${APP_NAME}"
        START_EPOCH="$(date +%s)"

        echo "Dashboard \(verb): intended_serial=\(serialNumber) actual_serial=${ACTUAL_SERIAL} app='${APP_NAME}' trigger='${TRIGGER}' start=${START_EPOCH}"

        # Capture stdout+stderr so we can grep for the "No policies" sentinel.
        # jamf policy returns 0 even when no matching policy exists, so grep is
        # the authoritative signal.
        OUTPUT="$("${JAMF_BIN}" policy -trigger "${TRIGGER}" -verbose 2>&1)" || RC=$?
        RC="${RC:-0}"

        echo "${OUTPUT}"

        if echo "${OUTPUT}" | grep -qE "No policies were found"; then
          echo "ERROR: no Jamf Pro policy is scoped to this device with custom trigger '${TRIGGER}'" >&2
          exit 20
        fi

        exit "${RC}"
        """
    }

    // MARK: - Application Manager (v3.18+) — Ephemeral cleanup queue

    /// Persisted record of a one-shot Application Manager dispatch. Stored
    /// so `purgeStaleApplicationActionArtifacts` can delete the Jamf Pro
    /// script and policy it generated after 24 hours, preventing
    /// accumulation of `Dashboard …` records on the Jamf Pro scripts and
    /// policies pages.
    struct ApplicationActionCleanupRecord: Codable, Sendable {
        let scriptID: String
        let policyID: String
        let createdAtEpoch: TimeInterval
    }

    /// Path to the on-disk JSON file that persists the cleanup queue across
    /// app launches. Located under Application Support per-app-container
    /// conventions.
    private static var applicationActionCleanupQueueURL: URL {
        let baseDirectory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        let jamfDirectory = baseDirectory.appendingPathComponent("Forsetti", isDirectory: true)
        return jamfDirectory.appendingPathComponent("application-action-cleanup-queue.json", isDirectory: false)
    }

    /// Age at which a cleanup record becomes eligible for purge. Shorter
    /// than the default Jamf Pro policy log retention so the admin has a
    /// window to read the policy log before the dashboard deletes it.
    private static let applicationActionCleanupAge: TimeInterval = 24 * 60 * 60

    /// Reads the cleanup queue from disk. Returns `[]` if the file doesn't
    /// exist yet, is empty, or is malformed — a malformed file gets
    /// rewritten on the next append, so this doesn't throw.
    private func loadApplicationActionCleanupQueue() -> [ApplicationActionCleanupRecord] {
        let url = Self.applicationActionCleanupQueueURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        do {
            let data = try Data(contentsOf: url)
            guard data.isEmpty == false else {
                return []
            }
            return try JSONDecoder().decode([ApplicationActionCleanupRecord].self, from: data)
        } catch {
            // Log and return empty; the malformed file is overwritten on next append.
            Task {
                await diagnosticsReporter.reportError(
                    source: "module.support-technician",
                    category: "application-manager",
                    message: "Application Manager cleanup queue file is malformed; treating as empty.",
                    errorDescription: describe(error),
                    metadata: [
                        "path": url.path
                    ]
                )
            }
            return []
        }
    }

    /// Writes the cleanup queue back to disk. Ensures the parent directory
    /// exists; creates it if necessary. Best-effort — failures log to
    /// diagnostics but don't throw (the cleanup queue is operational hygiene,
    /// not core functionality).
    private func saveApplicationActionCleanupQueue(_ queue: [ApplicationActionCleanupRecord]) {
        let url = Self.applicationActionCleanupQueueURL
        do {
            let parent = url.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: parent.path) == false {
                try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(queue)
            try data.write(to: url, options: [.atomic])
        } catch {
            Task {
                await diagnosticsReporter.reportError(
                    source: "module.support-technician",
                    category: "application-manager",
                    message: "Failed to persist Application Manager cleanup queue.",
                    errorDescription: describe(error),
                    metadata: [
                        "path": url.path
                    ]
                )
            }
        }
    }

    /// Appends a cleanup record after a successful `triggerAppPolicy`. Called
    /// only from the orchestrator on the success path — the blank-push
    /// failure path leaves the script and policy in place but still appends
    /// (the user's intent is still to clean up eventually; the delay merely
    /// shifts to the device's next regular check-in).
    private func enqueueApplicationActionCleanup(scriptID: String, policyID: String) {
        var queue = loadApplicationActionCleanupQueue()
        queue.append(
            ApplicationActionCleanupRecord(
                scriptID: scriptID,
                policyID: policyID,
                createdAtEpoch: Date().timeIntervalSince1970
            )
        )
        saveApplicationActionCleanupQueue(queue)
    }

    /// Purges queue entries older than `applicationActionCleanupAge` and
    /// best-effort-deletes the corresponding Jamf Pro script and policy
    /// records. Called once per service instance at construction time.
    ///
    /// Records that remain within the age window are kept. Deletion failures
    /// are logged but don't block — if Jamf Pro rejects a delete (e.g. the
    /// script was already removed manually), the entry drops from the queue
    /// anyway so repeated attempts don't fire indefinitely.
    func purgeStaleApplicationActionArtifacts() async {
        let queue = loadApplicationActionCleanupQueue()
        guard queue.isEmpty == false else {
            return
        }

        let now = Date().timeIntervalSince1970
        var remaining: [ApplicationActionCleanupRecord] = []
        var purgedCount = 0

        for record in queue {
            if now - record.createdAtEpoch < Self.applicationActionCleanupAge {
                remaining.append(record)
                continue
            }

            // Best-effort delete. Any failure is logged but doesn't prevent
            // the record from being dropped from the queue — a permanent
            // failure would otherwise loop forever.
            await bestEffortDeleteScript(scriptID: record.scriptID, reason: "ephemeral cleanup (>24h)")
            await bestEffortDeletePolicy(policyID: record.policyID, reason: "ephemeral cleanup (>24h)")
            purgedCount += 1
        }

        saveApplicationActionCleanupQueue(remaining)

        await diagnosticsReporter.report(
            source: "module.support-technician",
            category: "application-manager",
            severity: .info,
            message: "Ephemeral cleanup pass complete.",
            metadata: [
                "purged_count": String(purgedCount),
                "retained_count": String(remaining.count)
            ]
        )
    }

    /// Best-effort `DELETE /JSSResource/policies/id/{id}` used by the
    /// ephemeral cleanup. Mirrors `bestEffortDeleteScript` — a failure logs
    /// but doesn't throw, so cleanup can always make forward progress.
    private func bestEffortDeletePolicy(policyID: String, reason: String) async {
        let endpoint = "JSSResource/policies/id/\(policyID)"

        do {
            _ = try await apiGateway.request(
                path: endpoint,
                method: .delete,
                additionalHeaders: ["Accept": "application/xml"]
            )
            await diagnosticsReporter.report(
                source: "module.support-technician",
                category: "application-manager",
                severity: .info,
                message: "Deleted one-shot policy (\(reason)).",
                metadata: [
                    "endpoint": endpoint,
                    "policy_id": policyID,
                    "reason": reason
                ]
            )
        } catch {
            await diagnosticsReporter.reportError(
                source: "module.support-technician",
                category: "application-manager",
                message: "Failed to delete one-shot policy (\(reason)).",
                errorDescription: describe(error),
                metadata: [
                    "endpoint": endpoint,
                    "policy_id": policyID,
                    "reason": reason
                ]
            )
        }
    }

    // MARK: - Application Manager (v3.18+) — Privilege pre-flight

    /// The set of Jamf Pro privilege names the Application Manager action
    /// dispatch needs to work end-to-end.
    ///
    /// The names are the exact strings Jamf Pro emits under `account.privileges`
    /// in `GET /api/v1/auth`. Any mismatch (rename, additional privilege gate)
    /// shows up as a missing-privilege banner in the UI.
    ///
    /// Sourced from the Jamf Pro "Privileges and Deprecations" documentation
    /// and verified against a Jamf Pro 11.x tenant. When Jamf renames a
    /// privilege, this list is the one place to update.
    static let applicationManagerRequiredPrivileges: [String] = [
        "Read Computers",
        "Create Scripts",
        "Read Scripts",
        "Update Scripts",
        "Delete Scripts",
        "Create Policies",
        "Read Policies",
        "Update Policies",
        "Delete Policies",
        "Send MDM Check In Command"
    ]

    /// Calls `GET /api/v1/auth` (forcing a fresh token first) and returns
    /// the subset of `applicationManagerRequiredPrivileges` that the current
    /// token is **missing**.
    ///
    /// Returns an empty array when the token has every required privilege —
    /// the Application Manager flow is safe to dispatch. A non-empty array
    /// is the authoritative list of privilege names to show in the UI banner
    /// so the admin knows exactly which ones to grant.
    ///
    /// Reuses the framework's `JamfAPIGateway.fetchTokenAuthorizations()` —
    /// trusted utility, no rebuild needed. Emits diagnostics with the
    /// full required list, the missing list, and the token-count for
    /// operability.
    ///
    /// - Throws: Whatever the gateway throws (usually network or decoding
    ///   failures). Callers should treat a throw as "privilege state unknown"
    ///   and leave the buttons enabled with a warning banner — an overly
    ///   strict failure mode would lock out a user with a transient network
    ///   blip.
    func missingApplicationManagerPrivileges() async throws -> [String] {
        let granted = try await apiGateway.fetchTokenAuthorizations()
        let grantedSet = Set(granted)
        let missing = Self.applicationManagerRequiredPrivileges.filter { grantedSet.contains($0) == false }

        await diagnosticsReporter.report(
            source: "module.support-technician",
            category: "application-manager",
            severity: missing.isEmpty ? .info : .warning,
            message: missing.isEmpty
                ? "Application Manager pre-flight: all required privileges present."
                : "Application Manager pre-flight: \(missing.count) required privilege(s) missing.",
            metadata: [
                "privilege_count": String(granted.count),
                "required_count": String(Self.applicationManagerRequiredPrivileges.count),
                "missing_count": String(missing.count),
                "missing_list": missing.joined(separator: ", "),
                "required_list": Self.applicationManagerRequiredPrivileges.joined(separator: ", ")
            ]
        )

        return missing
    }

    // MARK: - Application Manager (v3.18+) — Action orchestrator

    /// End-to-end dispatch of a single `ApplicationAction` against the target
    /// Mac.
    ///
    /// Three phases, run in order. Each phase emits diagnostics; a failure
    /// at any phase surfaces a specific error describing *which* phase
    /// failed, so an admin reading the NDJSON log knows exactly where to
    /// look (Jamf Pro scripts page, policies page, or device history).
    ///
    /// 1. `createApplicationActionScript` — `POST /api/v1/scripts`. Uploads
    ///    the zsh wrapper with parameter 4 = app display name.
    /// 2. `createApplicationActionPolicy` — `POST /JSSResource/policies/id/0`.
    ///    Creates a once-per-computer policy scoped to the target device,
    ///    referencing the script.
    /// 3. `sendApplicationActionBlankPush` — `POST /api/v2/mdm/blank-push`.
    ///    Forces the device to check in now so the policy runs within minutes
    ///    rather than at the device's regular check-in.
    ///
    /// Both script and policy are tagged with a shared ISO-8601 timestamp
    /// in their names so the Jamf Pro admin can pair them up when reviewing
    /// generated artifacts. The ephemeral-cleanup queue (step 11) purges
    /// stale records older than 24 hours on next app launch.
    ///
    /// - Parameters:
    ///   - action: The action to dispatch.
    ///   - inventoryID: Jamf Pro inventory record ID of the target Mac.
    ///   - managementID: Client management UUID of the target Mac
    ///     (the blank push requires it).
    ///   - serialNumber: Hardware serial number of the target Mac.
    ///   - deviceDisplayName: Display name of the target Mac.
    /// - Returns: `ApplicationActionResult` with the script ID and policy ID
    ///   for cleanup bookkeeping.
    /// - Throws: Whichever phase failed, with its diagnostic already recorded.
    func triggerAppPolicy(
        action: ApplicationAction,
        inventoryID: String,
        managementID: String,
        serialNumber: String,
        deviceDisplayName: String
    ) async throws -> ApplicationActionResult {
        let timestamp = isoTimestampForGeneratedArtifacts()

        await diagnosticsReporter.report(
            source: "module.support-technician",
            category: "application-manager",
            severity: .info,
            message: "Dispatching \(action.verb.lowercased()) for \(action.appName) on \(deviceDisplayName).",
            metadata: [
                "action": action.verb.lowercased(),
                "app_name": action.appName,
                "custom_trigger": action.customTrigger,
                "inventory_id": inventoryID,
                "management_id": managementID,
                "serial_number": serialNumber,
                "timestamp": timestamp
            ]
        )

        // Phase 1: script
        let scriptID = try await createApplicationActionScript(
            action: action,
            inventoryID: inventoryID,
            serialNumber: serialNumber,
            deviceDisplayName: deviceDisplayName,
            timestamp: timestamp
        )

        // Phase 2: policy. If this fails, best-effort-delete the script we
        // just created so we don't leave orphans. Deletion failure is logged
        // but doesn't shadow the original error.
        let policyID: String
        do {
            policyID = try await createApplicationActionPolicy(
                scriptID: scriptID,
                action: action,
                inventoryID: inventoryID,
                serialNumber: serialNumber,
                deviceDisplayName: deviceDisplayName,
                timestamp: timestamp
            )
        } catch {
            await bestEffortDeleteScript(scriptID: scriptID, reason: "paired policy creation failed")
            throw error
        }

        // Phase 3: blank push. If this fails, the script + policy are left in
        // place — the device will still pick up the policy on its next
        // regularly-scheduled check-in. We surface the failure so the user
        // knows why the action didn't execute immediately, but the work isn't
        // lost.
        do {
            try await sendApplicationActionBlankPush(
                managementID: managementID,
                serialNumber: serialNumber,
                action: action
            )
        } catch {
            await diagnosticsReporter.reportError(
                source: "module.support-technician",
                category: "application-manager",
                message: "Blank push failed; script and policy remain in place for the device's next scheduled check-in.",
                errorDescription: describe(error),
                metadata: [
                    "action": action.verb.lowercased(),
                    "app_name": action.appName,
                    "inventory_id": inventoryID,
                    "management_id": managementID,
                    "serial_number": serialNumber,
                    "script_id": scriptID,
                    "policy_id": policyID
                ]
            )
            throw error
        }

        await diagnosticsReporter.report(
            source: "module.support-technician",
            category: "application-manager",
            severity: .warning,
            message: "\(action.verb) queued for \(action.appName) on \(deviceDisplayName).",
            metadata: [
                "action": action.verb.lowercased(),
                "app_name": action.appName,
                "custom_trigger": action.customTrigger,
                "inventory_id": inventoryID,
                "management_id": managementID,
                "serial_number": serialNumber,
                "script_id": scriptID,
                "policy_id": policyID,
                "timestamp": timestamp
            ]
        )

        // Record the artifacts for the ephemeral-cleanup queue so a future
        // app launch purges them after 24 hours. Fire-and-forget; a queue
        // write failure doesn't prevent the action result from flowing back
        // to the UI.
        enqueueApplicationActionCleanup(scriptID: scriptID, policyID: policyID)

        return ApplicationActionResult(
            action: action,
            inventoryID: inventoryID,
            serialNumber: serialNumber,
            scriptID: scriptID,
            policyID: policyID,
            createdAt: Date()
        )
    }

    /// Best-effort `DELETE /api/v1/scripts/{id}` used as rollback when the
    /// policy-creation step fails. Never throws — a cleanup failure is
    /// logged but doesn't shadow whatever caused the orchestrator to
    /// abort. The ephemeral-cleanup queue (step 11) will retry on next
    /// launch if this leaves an orphan behind.
    private func bestEffortDeleteScript(scriptID: String, reason: String) async {
        let endpoint = "api/v1/scripts/\(scriptID)"

        do {
            _ = try await apiGateway.request(
                path: endpoint,
                method: .delete
            )
            await diagnosticsReporter.report(
                source: "module.support-technician",
                category: "application-manager",
                severity: .info,
                message: "Rolled back orphan script after \(reason).",
                metadata: [
                    "endpoint": endpoint,
                    "script_id": scriptID,
                    "reason": reason
                ]
            )
        } catch {
            await diagnosticsReporter.reportError(
                source: "module.support-technician",
                category: "application-manager",
                message: "Failed to roll back orphan script after \(reason); ephemeral cleanup will retry on next app launch.",
                errorDescription: describe(error),
                metadata: [
                    "endpoint": endpoint,
                    "script_id": scriptID,
                    "reason": reason
                ]
            )
        }
    }

    // MARK: - Application Manager (v3.18+) — Blank push

    /// Sends an MDM blank push via `POST /api/v2/mdm/blank-push`, forcing
    /// the target Mac to check in immediately and process any queued
    /// policies (including the one this app just created).
    ///
    /// A blank push carries no command payload — it's a wake-up notification
    /// the MDM server sends via APNs. The device opens its MDM channel, pulls
    /// whatever is queued, executes it, and returns to sleep. The device will
    /// eventually check in on its own schedule anyway; the blank push is the
    /// mechanism that turns "eventually" into "within the next minute or two."
    ///
    /// Rebuilt from the existing `sendBlankPush` with explicit response
    /// validation: Jamf Pro should return a 2xx with an empty body, so this
    /// method treats any 2xx as success. Non-2xx throws through the gateway's
    /// `networkFailure` case, which includes the raw body in its message
    /// field for diagnostics. Every attempt — success or failure — emits a
    /// diagnostic event with the target management ID, serial number, and
    /// a response preview so the NDJSON log captures the full picture.
    ///
    /// - Parameters:
    ///   - managementID: The device's client management UUID, pulled from
    ///     `SupportSearchResult.clientManagementID` (preferred) or
    ///     `managementID`. Required.
    ///   - serialNumber: Hardware serial — used only for diagnostics metadata,
    ///     so the NDJSON log ties the push to the intended device.
    ///   - action: The `ApplicationAction` this push is delivering. Also only
    ///     for diagnostics metadata.
    /// - Throws: `JamfFrameworkError.networkFailure` for non-2xx responses,
    ///   or any other error the gateway throws.
    func sendApplicationActionBlankPush(
        managementID: String,
        serialNumber: String,
        action: ApplicationAction
    ) async throws {
        let endpoint = "api/v2/mdm/blank-push"
        let payload: [String: Any] = [
            "clientManagementIds": [managementID]
        ]
        let body = try JSONSerialization.data(withJSONObject: payload, options: [])
        let payloadPreview = String(data: body, encoding: .utf8) ?? "<non-utf8>"

        await diagnosticsReporter.report(
            source: "module.support-technician",
            category: "application-manager",
            severity: .info,
            message: "Sending blank push to force MDM check-in for \(action.verb.lowercased()) of \(action.appName).",
            metadata: [
                "endpoint": endpoint,
                "method": "POST",
                "management_id": managementID,
                "serial_number": serialNumber,
                "action": action.verb.lowercased(),
                "app_name": action.appName,
                "custom_trigger": action.customTrigger,
                "payload_preview": payloadPreview
            ]
        )

        let responseData: Data
        do {
            responseData = try await apiGateway.request(
                path: endpoint,
                method: .post,
                body: body
            )
        } catch {
            await diagnosticsReporter.reportError(
                source: "module.support-technician",
                category: "application-manager",
                message: "Blank push failed for \(action.verb.lowercased()) of \(action.appName).",
                errorDescription: describe(error),
                metadata: [
                    "endpoint": endpoint,
                    "management_id": managementID,
                    "serial_number": serialNumber,
                    "action": action.verb.lowercased(),
                    "app_name": action.appName
                ]
            )
            throw error
        }

        let responsePreview = String(data: responseData, encoding: .utf8) ?? "<empty>"

        await diagnosticsReporter.report(
            source: "module.support-technician",
            category: "application-manager",
            severity: .info,
            message: "Blank push accepted by Jamf Pro for \(action.verb.lowercased()) of \(action.appName).",
            metadata: [
                "endpoint": endpoint,
                "management_id": managementID,
                "serial_number": serialNumber,
                "action": action.verb.lowercased(),
                "app_name": action.appName,
                "response_bytes": String(responseData.count),
                "response_preview": responsePreview.isEmpty ? "<empty>" : responsePreview
            ]
        )
    }

    // MARK: - Application Manager (v3.18+) — One-shot policy creation

    /// Creates a one-shot Jamf Pro policy scoped to exactly one computer,
    /// referencing a previously-created script, via
    /// `POST /JSSResource/policies/id/0`.
    ///
    /// Frequency is "Once per computer" so the policy fires on the very next
    /// check-in and never again for that device. Trigger is `CHECKIN` so the
    /// paired blank push causes immediate execution. Parameter 4 on the
    /// script element carries the exact application display name so the
    /// wrapper script hits the correct custom trigger.
    ///
    /// Classic API is required — Jamf Pro's Modern API does not expose
    /// policy CRUD. The bearer token covers both APIs since Jamf Pro 10.35.
    ///
    /// - Parameters:
    ///   - scriptID: Jamf Pro script ID returned by
    ///     `createApplicationActionScript`.
    ///   - action: The `.install(appName:)` / `.uninstall(appName:)` action
    ///     this policy is delivering — used only for the policy name and
    ///     diagnostics.
    ///   - inventoryID: Jamf Pro computer inventory ID (target of the scope).
    ///   - serialNumber: Hardware serial — embedded in the policy name for
    ///     admin readability.
    ///   - deviceDisplayName: Display name of the target computer — embedded
    ///     in the policy name.
    ///   - timestamp: Same timestamp the script used. Both records share a
    ///     timestamp so an admin reading the Jamf Pro scripts and policies
    ///     pages can pair them up.
    /// - Returns: The new policy's ID as a String.
    /// - Throws: `SupportTechnicianError.unsupportedResponseShape` if the
    ///   response XML doesn't contain `<id>…</id>`; the underlying request
    ///   error otherwise.
    func createApplicationActionPolicy(
        scriptID: String,
        action: ApplicationAction,
        inventoryID: String,
        serialNumber: String,
        deviceDisplayName: String,
        timestamp: String
    ) async throws -> String {
        let endpoint = "JSSResource/policies/id/0"
        let appName = action.appName
        let actionVerb = action.verb
        let policyName = "Dashboard \(actionVerb): \(appName) (\(timestamp)) for \(deviceDisplayName) [serial \(serialNumber)]"

        let xmlBody = """
        <policy>
          <general>
            <name>\(xmlEscape(policyName))</name>
            <enabled>true</enabled>
            <trigger>CHECKIN</trigger>
            <trigger_checkin>true</trigger_checkin>
            <trigger_enrollment_complete>false</trigger_enrollment_complete>
            <trigger_login>false</trigger_login>
            <trigger_logout>false</trigger_logout>
            <trigger_network_state_changed>false</trigger_network_state_changed>
            <trigger_startup>false</trigger_startup>
            <frequency>Once per computer</frequency>
          </general>
          <scope>
            <all_computers>false</all_computers>
            <computers>
              <computer>
                <id>\(inventoryID)</id>
              </computer>
            </computers>
          </scope>
          <scripts>
            <script>
              <id>\(scriptID)</id>
              <priority>After</priority>
              <parameter4>\(xmlEscape(appName))</parameter4>
            </script>
          </scripts>
        </policy>
        """
        let bodyData = Data(xmlBody.utf8)

        await diagnosticsReporter.report(
            source: "module.support-technician",
            category: "application-manager",
            severity: .info,
            message: "Creating one-shot \(actionVerb.lowercased()) policy in Jamf Pro.",
            metadata: [
                "endpoint": endpoint,
                "method": "POST",
                "policy_name": policyName,
                "script_id": scriptID,
                "action": actionVerb.lowercased(),
                "app_name": appName,
                "inventory_id": inventoryID,
                "serial_number": serialNumber,
                "body_preview": String(xmlBody.replacingOccurrences(of: "\n", with: " ").prefix(1200))
            ]
        )

        let responseData: Data
        do {
            responseData = try await apiGateway.request(
                path: endpoint,
                method: .post,
                body: bodyData,
                additionalHeaders: ["Content-Type": "application/xml"]
            )
        } catch {
            await diagnosticsReporter.reportError(
                source: "module.support-technician",
                category: "application-manager",
                message: "Failed to create one-shot \(actionVerb.lowercased()) policy.",
                errorDescription: describe(error),
                metadata: [
                    "endpoint": endpoint,
                    "policy_name": policyName,
                    "script_id": scriptID,
                    "action": actionVerb.lowercased(),
                    "app_name": appName,
                    "inventory_id": inventoryID,
                    "serial_number": serialNumber
                ]
            )
            throw error
        }

        guard let policyID = extractPolicyIDFromXML(responseData),
              policyID.isEmpty == false
        else {
            await diagnosticsReporter.reportError(
                source: "module.support-technician",
                category: "application-manager",
                message: "Policy creation response missing <id>; cannot proceed.",
                errorDescription: "Response body lacked the expected <id>…</id> element.",
                metadata: [
                    "endpoint": endpoint,
                    "policy_name": policyName,
                    "script_id": scriptID
                ]
            )
            throw SupportTechnicianError.unsupportedResponseShape
        }

        await diagnosticsReporter.report(
            source: "module.support-technician",
            category: "application-manager",
            severity: .info,
            message: "Created one-shot \(actionVerb.lowercased()) policy.",
            metadata: [
                "endpoint": endpoint,
                "policy_id": policyID,
                "policy_name": policyName,
                "script_id": scriptID,
                "action": actionVerb.lowercased(),
                "app_name": appName,
                "inventory_id": inventoryID,
                "serial_number": serialNumber
            ]
        )

        return policyID
    }

    // MARK: - Multi-Path Request Fallback

    /// Tries multiple API paths and body candidates until one succeeds, handling
    /// version differences and payload format variations.
    ///
    /// - Parameters:
    ///   - paths: Ordered list of API paths to try.
    ///   - method: The HTTP method for the request.
    ///   - queryItems: Optional query parameters.
    ///   - bodyCandidates: Ordered list of body payloads to try for each path.
    /// - Returns: The raw response data from the first successful request.
    private func requestWithPathFallback(
        paths: [String],
        method: HTTPMethod,
        queryItems: [URLQueryItem] = [],
        bodyCandidates: [Data?] = [nil]
    ) async throws -> Data {
        var lastError: (any Error)?

        for path in paths {
            for body in bodyCandidates {
                do {
                    return try await apiGateway.request(
                        path: path,
                        method: method,
                        queryItems: queryItems,
                        body: body
                    )
                } catch {
                    lastError = error

                    if shouldTryNextPath(after: error) {
                        continue
                    }

                    throw error
                }
            }
        }

        throw lastError ?? JamfFrameworkError.authenticationFailed
    }

    // MARK: - MDM Commands

    /// Queues an MDM command for the specified device against
    /// `POST /api/v2/mdm/commands` using the documented payload shape.
    ///
    /// Privilege requirements (verified against Jamf's
    /// privileges-and-deprecations documentation on 2026-04-17):
    ///
    /// - The ENDPOINT gate privilege is `"View MDM command information in Jamf Pro API"`.
    ///   Despite the counterintuitive `"View"` on a POST endpoint, this is the
    ///   literal name required for both GET and POST of `/v2/mdm/commands`.
    ///   If this privilege is missing, every POST returns 403 INVALID_PRIVILEGE
    ///   regardless of which per-command privileges are present.
    /// - Per-command-type privileges layer on top of the gate, e.g.
    ///   `"Send Device Information Command"` for `DEVICE_INFORMATION`,
    ///   `"Send Computer Restart Command"` for computer `RESTART_DEVICE`,
    ///   `"Send Mobile Device Restart Device Command"` for mobile `RESTART_DEVICE`
    ///   (note "Device" appears twice in the mobile name).
    /// - The privilege `"Send MDM command information in Jamf Pro API"` is NOT
    ///   the gate — it's used by a different endpoint (mobile-device-groups
    ///   erase). Confusingly named; do not mistake it for the gate.
    ///
    /// Users can verify the token's actual privileges via Diagnostics → Check
    /// Token Privileges. Look for `has_view_mdm_command_information=true` in
    /// the emitted telemetry event.
    ///
    /// Note: `POST /api/v1/mdm/commands` is NOT a valid endpoint — it returns
    /// 405 Method Not Allowed and the v1 path was deprecated on 2023-10-16 per
    /// Jamf's docs. We only hit v2.
    ///
    /// - Parameters:
    ///   - commandType: The MDM command type string (e.g. "DEVICE_INFORMATION").
    ///     Valid values per the v2 MDM commands reference include
    ///     `DEVICE_INFORMATION`, `RESTART_DEVICE`, `CLEAR_PASSCODE`,
    ///     `ERASE_DEVICE`, `INSTALLED_APPLICATION_LIST`, `DEVICE_LOCK`, etc.
    ///   - managementID: The device's management identifier.
    /// - Returns: The raw response data.
    /// Generates a cryptographically random 6-digit PIN suitable for the
    /// macOS `DEVICE_LOCK` MDM command's `pin` field. Uses `SecRandomCopyBytes`
    /// via `SystemRandomNumberGenerator` — NOT `Int.random(in:)` with
    /// the default generator — so the PIN is unpredictable even on
    /// devices with weak entropy at boot.
    ///
    /// Range is 100000…999999 inclusive (always six digits; never starts
    /// with a leading zero so the Mac's firmware lock screen accepts the
    /// value without the tech having to type a leading 0).
    private nonisolated func generateLockPIN() -> String {
        var generator = SystemRandomNumberGenerator()
        let pin = Int.random(in: 100_000...999_999, using: &generator)
        return String(pin)
    }

    // Screen Sharing connection-target resolution moved to the deterministic, unit-tested
    // `SupportRemoteSupportTargetResolver` (Models/Services). The serial number is never used
    // as a host, and the `vnc://` URL is built safely (percent-encoded) by the resolved target.

    // MARK: - Remote Support (Apple-native Screen Sharing)

    /// Queues `ENABLE_REMOTE_DESKTOP` for the Mac with the given management ID so Apple Remote
    /// Management turns on at the next MDM check-in. Queueing is acceptance only — it is not
    /// readiness and never opens Screen Sharing. Returns a command identifier when the Jamf
    /// response carries one (best-effort). Routes through the existing gateway + DiagnosticsCenter.
    func enableRemoteManagement(managementID: String) async throws -> String? {
        let data = try await queueMDMCommand(commandType: "ENABLE_REMOTE_DESKTOP", managementID: managementID)
        let commandID = Self.remoteSupportCommandID(from: data)
        await diagnosticsReporter.report(
            source: "module.support-technician",
            category: "remote-support",
            severity: .info,
            message: "Queued ENABLE_REMOTE_DESKTOP for Remote Support.",
            metadata: [
                "endpoint": "api/v2/mdm/commands",
                "command_type": "ENABLE_REMOTE_DESKTOP",
                "management_id": managementID,
                "command_id": commandID ?? "unknown",
                "jamf_command_queued": "true"
            ]
        )
        return commandID
    }

    /// Queues `DISABLE_REMOTE_DESKTOP` to turn Apple Remote Management back off (cleanup).
    func disableRemoteManagement(managementID: String) async throws -> String? {
        let data = try await queueMDMCommand(commandType: "DISABLE_REMOTE_DESKTOP", managementID: managementID)
        let commandID = Self.remoteSupportCommandID(from: data)
        await diagnosticsReporter.report(
            source: "module.support-technician",
            category: "remote-support",
            severity: .info,
            message: "Queued DISABLE_REMOTE_DESKTOP for Remote Support cleanup.",
            metadata: [
                "endpoint": "api/v2/mdm/commands",
                "command_type": "DISABLE_REMOTE_DESKTOP",
                "management_id": managementID,
                "command_id": commandID ?? "unknown",
                "jamf_command_queued": "true"
            ]
        )
        return commandID
    }

    /// Best-effort extraction of a command identifier from a queue response. Returns `nil` when
    /// the response shape carries no recognizable id — the workflow tolerates an unknown id.
    private nonisolated static func remoteSupportCommandID(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let dict: [String: Any]?
        if let direct = object as? [String: Any] {
            dict = direct
        } else if let array = object as? [[String: Any]] {
            dict = array.first
        } else {
            dict = nil
        }
        guard let dict else { return nil }
        for key in ["commandUuid", "uuid", "id", "commandId"] {
            if let value = dict[key] as? String, value.isEmpty == false { return value }
            if let value = dict[key] as? Int { return String(value) }
        }
        return nil
    }

    // MARK: - Modern API MDM Commands

    /// Forces a Declarative Device Management (DDM) sync on the target
    /// device via the Modern endpoint:
    ///   POST /api/v1/ddm/{managementId}/sync   (empty body)
    ///
    /// The device sends a DeclarativeManagement status report on the
    /// next check-in, refreshing Jamf Pro's inventory cache. This is
    /// the documented Modern replacement for the Classic
    /// `UpdateInventory` command and for the raw MDM DEVICE_INFORMATION
    /// query (which fails with "Unable to perform MDM operation" on
    /// current Jamf Pro server versions).
    ///
    /// Privileges: "View MDM command information in Jamf Pro API" +
    /// "Send Declarative Management Command".
    ///
    /// Source: Der Flounder, 2025-05-14 —
    /// https://derflounder.wordpress.com/2025/05/14/forcing-a-ddm-sync-on-a-jamf-pro-managed-device-via-the-jamf-pro-api/
    private func sendDDMSync(managementID: String) async throws {
        let endpoint = "api/v1/ddm/\(managementID)/sync"

        await diagnosticsReporter.report(
            source: "module.support-technician",
            category: "ddm-sync",
            severity: .info,
            message: "Sending DDM sync request.",
            metadata: [
                "endpoint": endpoint,
                "management_id": managementID
            ]
        )

        do {
            let data = try await apiGateway.request(
                path: endpoint,
                method: .post
            )
            let responsePreview = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            await diagnosticsReporter.report(
                source: "module.support-technician",
                category: "ddm-sync",
                severity: .info,
                message: "DDM sync accepted by Jamf Pro.",
                metadata: [
                    "endpoint": endpoint,
                    "management_id": managementID,
                    "response_preview": responsePreview
                ]
            )
        } catch {
            await diagnosticsReporter.reportError(
                source: "module.support-technician",
                category: "ddm-sync",
                message: "DDM sync failed.",
                errorDescription: describe(error),
                metadata: [
                    "endpoint": endpoint,
                    "management_id": managementID
                ]
            )
            throw error
        }
    }

    /// Sends a blank APNs push via Jamf's dedicated Modern endpoint:
    ///   POST /api/v2/mdm/blank-push
    ///   { "clientManagementIds": ["<uuid>"] }
    ///
    /// A blank push carries no command payload — it's a notification
    /// that tells the device to open its MDM channel and process any
    /// queued commands immediately. Useful after queueing a RESTART /
    /// DEVICE_INFORMATION / ENABLE_REMOTE_DESKTOP when you don't want
    /// to wait for the device's next regular check-in.
    ///
    /// Privilege: `Send MDM Check In Command`.
    private func sendBlankPush(managementID: String) async throws {
        let endpoint = "api/v2/mdm/blank-push"
        let payload: [String: Any] = [
            "clientManagementIds": [managementID]
        ]
        let payloadData = try JSONSerialization.data(withJSONObject: payload, options: [])
        let payloadPreview = String(data: payloadData, encoding: .utf8) ?? "<non-utf8>"

        await diagnosticsReporter.report(
            source: "module.support-technician",
            category: "blank-push",
            severity: .info,
            message: "Sending blank push via Modern API.",
            metadata: [
                "endpoint": endpoint,
                "management_id": managementID,
                "payload_preview": payloadPreview
            ]
        )

        do {
            let data = try await apiGateway.request(
                path: endpoint,
                method: .post,
                body: payloadData
            )
            let responsePreview = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            await diagnosticsReporter.report(
                source: "module.support-technician",
                category: "blank-push",
                severity: .info,
                message: "Blank push accepted by Jamf Pro.",
                metadata: [
                    "endpoint": endpoint,
                    "management_id": managementID,
                    "response_preview": responsePreview
                ]
            )
        } catch {
            await diagnosticsReporter.reportError(
                source: "module.support-technician",
                category: "blank-push",
                message: "Blank push failed.",
                errorDescription: describe(error),
                metadata: [
                    "endpoint": endpoint,
                    "management_id": managementID,
                    "payload_preview": payloadPreview
                ]
            )
            throw error
        }
    }

    /// Queues a command via `POST /api/v2/mdm/commands`.
    ///
    /// Retained for actions that have no Classic-API equivalent (e.g.
    /// CLEAR_PASSCODE, ERASE_DEVICE, INSTALLED_APPLICATION_LIST).
    /// - Parameters:
    ///   - commandType: The MDM command type string (e.g. "DEVICE_INFORMATION").
    ///     Valid values per the v2 MDM commands reference include
    ///     `DEVICE_INFORMATION`, `RESTART_DEVICE`, `CLEAR_PASSCODE`,
    ///     `ERASE_DEVICE`, `INSTALLED_APPLICATION_LIST`, `DEVICE_LOCK`, etc.
    ///   - managementID: The device's management identifier.
    /// - Returns: The raw response data.
    private func queueMDMCommand(
        commandType: String,
        managementID: String,
        extraCommandData: [String: Any] = [:]
    ) async throws -> Data {
        // Only `POST /api/v2/mdm/commands` is supported. Jamf deprecated
        // `/api/v1/mdm/commands` on 2023-10-16; that path returns HTTP 405.
        let endpoint = "api/v2/mdm/commands"

        // Merge extra commandData fields (e.g. `pin` for DEVICE_LOCK,
        // `message` / `phoneNumber` for DEVICE_LOCK lockscreen messages,
        // `productVersion` for OS update commands) into the base
        // commandData dictionary. Callers pass `[:]` when the command
        // only needs the commandType.
        var commandData: [String: Any] = ["commandType": commandType]
        for (key, value) in extraCommandData {
            commandData[key] = value
        }

        // Three payload candidates. Candidate 0 matches the body shape
        // documented by Jamf and their community examples:
        //   {"clientData":[{"managementId":"…"}],"commandData":{"commandType":"…"}}
        // Candidates 1 and 2 exist for older/experimental Jamf Pro builds
        // that accepted variant field names. Kept because the body shape
        // was one of the things still uncertain during this investigation.
        let payloadCandidates: [[String: Any]] = [
            [
                "clientData": [["managementId": managementID]],
                "commandData": commandData
            ],
            [
                "clientData": [["clientManagementId": managementID]],
                "commandData": commandData
            ],
            [
                "managementId": managementID,
                "commandData": commandData
            ]
        ]

        // Try the full payload series once. If every candidate fails with 403,
        // force a fresh token (the cached one may carry a pre-privilege-add
        // snapshot, since Jamf OAuth tokens embed privileges at issuance) and
        // try the series again. Two total passes max.
        //
        // Verbose per-attempt logging is emitted to diagnostics so when
        // something fails we can see exactly which payload, which status
        // code, and the raw response body — no more guessing from "403
        // INVALID_PRIVILEGE" alone.
        for pass in 0..<2 {
            if pass == 1 {
                await diagnosticsReporter.report(
                    source: "module.support-technician",
                    category: "mdm-command",
                    severity: .warning,
                    message: "All payload candidates returned 403 on first pass; forcing token refresh and retrying.",
                    metadata: [
                        "command_type": commandType,
                        "management_id": managementID,
                        "endpoint": endpoint
                    ]
                )
                await apiGateway.invalidateCachedToken()
            }

            var passError: (any Error)?
            var sawPrivilegeDenial = false

            for (index, payload) in payloadCandidates.enumerated() {
                let payloadData = try JSONSerialization.data(withJSONObject: payload, options: [])
                let payloadPreview = String(data: payloadData, encoding: .utf8) ?? "<non-utf8>"

                do {
                    let response = try await apiGateway.request(
                        path: endpoint,
                        method: .post,
                        body: payloadData
                    )

                    await diagnosticsReporter.report(
                        source: "module.support-technician",
                        category: "mdm-command",
                        severity: .info,
                        message: "MDM command queued successfully.",
                        metadata: [
                            "command_type": commandType,
                            "management_id": managementID,
                            "endpoint": endpoint,
                            "payload_candidate_index": String(index),
                            "payload_preview": payloadPreview,
                            "pass": String(pass)
                        ]
                    )
                    return response
                } catch {
                    passError = error

                    await diagnosticsReporter.reportError(
                        source: "module.support-technician",
                        category: "mdm-command",
                        message: "MDM command attempt failed.",
                        errorDescription: describe(error),
                        metadata: [
                            "command_type": commandType,
                            "management_id": managementID,
                            "endpoint": endpoint,
                            "payload_candidate_index": String(index),
                            "payload_preview": payloadPreview,
                            "pass": String(pass)
                        ]
                    )

                    // 400 = wrong payload shape. Try next candidate immediately
                    // without counting this as a privilege-denial.
                    if isNetworkFailure(error, statusCode: 400) {
                        continue
                    }

                    // 403 / 404 / 405 (typed .forbidden/.notFound OR raw
                    // networkFailure status). Record that we saw a privilege
                    // denial in this pass so the pass-1 token refresh path
                    // only runs when it would actually help, then try the
                    // next payload candidate to rule out field-name issues.
                    if isEndpointUnavailable(error) {
                        sawPrivilegeDenial = true
                        continue
                    }

                    // Anything else (5xx, 401 after gateway's own 401 retry,
                    // network transport) is not worth trying more candidates.
                    throw error
                }
            }

            // End of pass. If no 403 occurred, there's no benefit to a token
            // refresh retry — rethrow whatever the last error was.
            if sawPrivilegeDenial == false {
                throw passError ?? JamfFrameworkError.authenticationFailed
            }

            // Fell through without a success and we did see a 403 — if this
            // was pass 0, loop again with a fresh token. If it was pass 1,
            // the next iteration won't execute and we fall out of the loop.
        }

        // Both passes exhausted with 403s on every candidate.
        throw JamfFrameworkError.forbidden(
            message: "MDM command \(commandType) rejected on POST \(endpoint) after two passes (cache refresh included). Check Diagnostics → Check Token Privileges and verify View MDM command information in Jamf Pro API is present, plus the per-command privilege (e.g. Send Device Information Command for DEVICE_INFORMATION, Send Computer Restart Command for RESTART_DEVICE on a Mac, Send Mobile Device Restart Device Command for RESTART_DEVICE on iOS). The Diagnostics log contains the raw response body for each attempt."
        )
    }

    private func describe(_ error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    // MARK: - LAPS

    /// A local admin password account resolved from the LAPS accounts endpoint.
    private struct LAPSAccount {
        /// The local admin account username.
        let username: String

        /// The password GUID for fetching the specific password version, if available.
        let passwordGUID: String?
    }

    /// Resolves the preferred LAPS account for a device by fetching the accounts list
    /// and returning the first account with a username.
    ///
    /// - Parameter clientManagementID: The device's client management identifier.
    /// - Returns: The resolved LAPS account.
    /// - Throws: `SupportTechnicianError.noLAPSAccounts` if no accounts are found.
    private func resolvePreferredLAPSAccount(for clientManagementID: String) async throws -> LAPSAccount {
        let data = try await requestWithPathFallback(
            paths: [
                "api/v2/local-admin-password/\(clientManagementID)/accounts"
            ],
            method: .get
        )

        let object = try jsonObject(from: data)
        let accountDictionaries = dictionaryArray(from: object)

        for dictionary in accountDictionaries {
            guard let username =
                extractString(using: ["username", "accountName", "name", "localAdminAccount"], from: dictionary)
            else {
                continue
            }

            let passwordGUID = extractString(using: ["passwordGuid", "guid", "accountGuid"], from: dictionary)
            return LAPSAccount(username: username, passwordGUID: passwordGUID)
        }

        throw SupportTechnicianError.noLAPSAccounts
    }

    /// Fetches the LAPS password for a specific account, optionally using a password GUID
    /// for precise version targeting.
    private func fetchLAPSPassword(
        clientManagementID: String,
        accountName: String,
        passwordGUID: String?
    ) async throws -> String {
        let encodedAccountName = accountName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? accountName
        var paths = [String]()

        // Prefer the GUID-specific path when available
        if let passwordGUID,
           passwordGUID.isEmpty == false
        {
            let encodedGUID = passwordGUID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? passwordGUID
            paths.append(
                "api/v2/local-admin-password/\(clientManagementID)/account/\(encodedAccountName)/\(encodedGUID)/password"
            )
        }

        paths.append(
            "api/v2/local-admin-password/\(clientManagementID)/account/\(encodedAccountName)/password"
        )

        let data = try await requestWithPathFallback(paths: paths, method: .get)

        return try extractSecretValue(
            from: data,
            preferredKeyFragments: [
                "password",
                "plainTextPassword"
            ]
        )
    }

    // MARK: - Application Manager (v3.18+) — Small helpers

    /// Extracts `<id>…</id>` from the XML response returned by Jamf Pro's
    /// Classic create-policy endpoint. Trivial parse — no XMLParser needed
    /// for this single-value case.
    private nonisolated func extractPolicyIDFromXML(_ data: Data) -> String? {
        guard let xml = String(data: data, encoding: .utf8) else { return nil }
        let openTag = "<id>"
        let closeTag = "</id>"
        guard let openRange = xml.range(of: openTag),
              let closeRange = xml.range(of: closeTag, range: openRange.upperBound..<xml.endIndex)
        else {
            return nil
        }
        let id = xml[openRange.upperBound..<closeRange.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return id.isEmpty ? nil : id
    }

    /// Escapes characters with special meaning in XML content. Used when
    /// injecting technician-provided strings (app display name, policy name)
    /// into the Classic API XML body.
    private nonisolated func xmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    /// ISO-8601 timestamp formatted as `yyyyMMdd'T'HHmmss'Z'` — embedded in
    /// system-created script and policy names so an admin can match pairs
    /// and bulk-clean Dashboard-generated artifacts later.
    private nonisolated func isoTimestampForGeneratedArtifacts() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: Date())
    }

    // MARK: - Jamf Pro Web UI Deep Links

    /// Builds the Jamf Pro web UI URL for a device's management page. Used by
    /// the "Open in Jamf" action so a technician can jump straight to the
    /// device's record in the tenant console when the full web UI is needed.
    ///
    /// URL format for Jamf Pro 11.x:
    /// - Computer: `https://<server>/computers.html?id=<inventoryId>&o=r`
    /// - Mobile:   `https://<server>/mobileDevices.html?id=<inventoryId>&o=r`
    ///
    /// The `o=r` query parameter selects the device record's Management tab.
    ///
    /// - Throws: `SupportTechnicianError` if the server URL isn't configured.
    func jamfProDeviceManagementURL(
        inventoryID: String,
        assetType: SupportAssetType
    ) async throws -> URL {
        guard let baseURL = await apiGateway.currentServerBaseURL() else {
            throw SupportTechnicianError.unsupportedAction
        }

        let page: String
        switch assetType {
        case .computer:
            page = "computers.html"
        case .mobileDevice:
            page = "mobileDevices.html"
        }

        var components = URLComponents(
            url: baseURL.appending(path: page),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "id", value: inventoryID),
            URLQueryItem(name: "o", value: "r")
        ]

        guard let url = components?.url else {
            throw SupportTechnicianError.unsupportedAction
        }
        return url
    }

    // MARK: - Management ID Resolution

    /// Resolves the management ID from a device detail, trying `managementID` first,
    /// then falling back to `clientManagementID`.
    private func resolveManagementID(from detail: SupportDeviceDetail) throws -> String {
        if let managementID = detail.summary.managementID,
           managementID.isEmpty == false
        {
            return managementID
        }

        if let clientManagementID = detail.summary.clientManagementID,
           clientManagementID.isEmpty == false
        {
            return clientManagementID
        }

        throw SupportTechnicianError.missingManagementID
    }

    /// Resolves the client management ID from a device detail, trying
    /// `clientManagementID` first, then falling back to `managementID`.
    private func resolveClientManagementID(from detail: SupportDeviceDetail) throws -> String {
        if let clientManagementID = detail.summary.clientManagementID,
           clientManagementID.isEmpty == false
        {
            return clientManagementID
        }

        if let managementID = detail.summary.managementID,
           managementID.isEmpty == false
        {
            return managementID
        }

        throw SupportTechnicianError.missingClientManagementID
    }

    // MARK: - Secret Value Extraction

    /// Extracts a sensitive string value (password, recovery key, device PIN)
    /// from a JSON response, preferring keys that match `preferredKeyFragments`.
    ///
    /// Delegates to `SupportSecretValueExtractor`, which honours fragment
    /// priority, prefers an exact key match over a substring match, and never
    /// returns a metadata field — e.g. FileVault's
    /// `individualRecoveryKeyValidityStatus` (= "VALID"), which also contains
    /// the `recoveryKey` fragment. See that type for the rules.
    private func extractSecretValue(
        from data: Data,
        preferredKeyFragments: [String]
    ) throws -> String {
        do {
            return try SupportSecretValueExtractor.extract(
                from: data,
                preferredKeyFragments: preferredKeyFragments
            )
        } catch SupportSecretValueExtractor.ExtractionError.noSecretValue {
            throw SupportTechnicianError.unsupportedSecretPayload
        }
    }

    // MARK: - JSON Parsing Utilities

    /// Extracts the root dictionary from a JSON response, unwrapping common container
    /// keys like "results", "computer", "mobileDevice", etc.
    private func rootDictionary(from data: Data) throws -> [String: Any] {
        let object = try jsonObject(from: data)

        if let dictionary = object as? [String: Any] {
            // Try unwrapping common container keys
            for key in ["results", "result", "item", "inventory", "computer", "mobileDevice", "device", "data"] {
                if let nestedDictionary = dictionary[key] as? [String: Any] {
                    return nestedDictionary
                }

                if let nestedArray = dictionary[key] as? [Any],
                   let first = nestedArray.first as? [String: Any]
                {
                    return first
                }
            }

            return dictionary
        }

        if let array = object as? [Any],
           let first = array.first as? [String: Any]
        {
            return first
        }

        throw SupportTechnicianError.unsupportedResponseShape
    }

    /// Deserializes raw data into a JSON object.
    private func jsonObject(from data: Data) throws -> Any {
        try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    /// Extracts an array of dictionaries from various JSON container shapes,
    /// probing known wrapper keys when the value is itself a dictionary.
    private func dictionaryArray(from value: Any?) -> [[String: Any]] {
        if let dictionaries = value as? [[String: Any]] {
            return dictionaries
        }

        if let array = value as? [Any] {
            let directDictionaries = array.compactMap { $0 as? [String: Any] }
            if directDictionaries.isEmpty == false {
                return directDictionaries
            }

            for element in array {
                let nested = dictionaryArray(from: element)
                if nested.isEmpty == false {
                    return nested
                }
            }

            return []
        }

        if let dictionary = value as? [String: Any] {
            for key in ["results", "items", "devices", "computers", "mobileDevices", "data", "inventory"] {
                let nested = dictionaryArray(from: dictionary[key])
                if nested.isEmpty == false {
                    return nested
                }
            }

            return [dictionary]
        }

        return []
    }

    /// Extracts a string from a dictionary using multiple dot-separated key paths.
    /// Returns the first non-nil, non-empty result.
    private func extractString(
        using paths: [String],
        from dictionary: [String: Any]
    ) -> String? {
        for path in paths {
            guard let resolvedValue = resolveValue(atPath: path, in: dictionary),
                  let extracted = extractStringValue(from: resolvedValue)
            else {
                continue
            }

            return extracted
        }

        return nil
    }

    /// Resolves a value at a dot-separated key path within a nested dictionary structure.
    /// Supports traversal through arrays by mapping each element.
    private func resolveValue(atPath path: String, in dictionary: [String: Any]) -> Any? {
        // STRICT case-sensitive lookup only — matches the Mobile Device
        // Search module's resolver behaviour exactly. Earlier revisions
        // added a recursive "deep find" fallback that walked the entire
        // tree looking for the leaf key by name. That was the source of
        // the "hardware information is wrong" regression: when the strict
        // path failed, deep-find would happily return the first key with
        // the right name from anywhere in the tree — including unrelated
        // sections — which then surfaced as bogus values in the General /
        // Hardware frames.
        //
        // Returning nil when the strict path doesn't resolve is correct:
        // the view renders an "Unavailable" placeholder instead of
        // confidently displaying wrong data.
        return resolveValueStrict(atPath: path, in: dictionary)
    }

    // `deepFindValue` / `deepFindMatch` / `isUsefulMatch` were removed in
    // 3.22.5 — they caused incorrect values to appear in the Hardware /
    // General frames by matching unrelated same-named keys elsewhere in
    // the payload. Strict-path-only is the correct behaviour; see the
    // comment on `resolveValue(atPath:in:)`.

    /// Exact case-sensitive dot-path resolver.
    private func resolveValueStrict(atPath path: String, in dictionary: [String: Any]) -> Any? {
        let components = path.split(separator: ".").map(String.init)
        guard components.isEmpty == false else { return nil }

        var current: Any = dictionary
        for component in components {
            if let currentDictionary = current as? [String: Any] {
                guard let next = currentDictionary[component] else { return nil }
                current = next
                continue
            }
            if let currentArray = current as? [Any] {
                let mapped = currentArray.compactMap { element -> Any? in
                    (element as? [String: Any])?[component]
                }
                guard mapped.isEmpty == false else { return nil }
                current = mapped.count == 1 ? mapped[0] : mapped
                continue
            }
            return nil
        }
        return current
    }

    // `resolveValueCaseInsensitive` was removed in 3.22.5. Mobile Device
    // Search resolves strict-case-sensitive paths against the v2 inventory
    // endpoint and the Support Technician module now matches that
    // behaviour exactly.

    /// Converts a JSON value to a displayable string, handling String, Bool, Int,
    /// Double, NSNumber, Dictionary, and Array types.
    private func extractStringValue(from value: Any?) -> String? {
        switch value {
        case let stringValue as String:
            let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let boolValue as Bool:
            return boolValue ? "true" : "false"
        case let intValue as Int:
            return String(intValue)
        case let doubleValue as Double:
            return String(doubleValue)
        case let number as NSNumber:
            return number.stringValue
        case let dictionary as [String: Any]:
            // Try preferred display keys first
            if let preferred =
                extractStringValue(from: dictionary["displayName"]) ??
                extractStringValue(from: dictionary["name"]) ??
                extractStringValue(from: dictionary["value"]) ??
                extractStringValue(from: dictionary["id"])
            {
                return preferred
            }

            // Flatten all key-value pairs into a comma-separated string
            let flattened = dictionary
                .keys
                .sorted()
                .compactMap { key -> String? in
                    guard let nestedValue = extractStringValue(from: dictionary[key]) else {
                        return nil
                    }

                    return "\(key): \(nestedValue)"
                }

            guard flattened.isEmpty == false else {
                return nil
            }

            return flattened.joined(separator: ", ")

        case let array as [Any]:
            let values = array.compactMap { extractStringValue(from: $0) }
            guard values.isEmpty == false else {
                return nil
            }

            return values.joined(separator: ", ")
        default:
            return nil
        }
    }

    /// Converts a dictionary to a pretty-printed JSON string for the raw payload view.
    private func prettyJSONString(from dictionary: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(dictionary),
              let data = try? JSONSerialization.data(withJSONObject: dictionary, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }

        return string
    }

    // MARK: - Section Building

    /// Builds structured detail sections and routes them into the redesigned
    /// category buckets.
    ///
    /// Each top-level key becomes a section. Nested dictionaries expand into
    /// key-value items, arrays show a count and up to 5 preview items, and
    /// scalar values become single-item sections.
    ///
    /// The `extensionAttributes` key is intentionally skipped here — it is
    /// handled by `extractExtensionAttributes(from:)` which produces typed
    /// `SupportExtensionAttribute` instances. Letting it flow through the
    /// generic array branch was the cause of the unreadable "item 1: {...}"
    /// rendering the redesign is replacing.
    private func buildSectionsAndCategorize(
        from dictionary: [String: Any]
    ) -> (sections: [SupportDetailSection], categorized: CategorizedDeviceDetail) {
        var sections: [SupportDetailSection] = []
        var bucketed: [SupportDeviceCategory: [SupportDetailSection]] = [:]

        // Real iPad / iPhone payloads (v1 mobile classic) nest the
        // platform-specific fields under a typed key — `ios`, `tvos`,
        // `visionos`, `watchos`. That bucket contains a HUGE mix of
        // hardware, security, network, applications, profiles, etc.
        // Flattening the `ios` dict as a single section would route
        // everything into `.other` (since the key name itself doesn't
        // match any category). Instead, expand the nest INTO the top-
        // level iteration so each sub-key gets bucketed into its proper
        // category — `security` → .security, `applications` →
        // .applications, etc.
        var workingDictionary = dictionary
        let platformNests = ["ios", "tvos", "visionos", "watchos", "computer"]
        for nestKey in platformNests {
            guard let nested = workingDictionary[nestKey] as? [String: Any] else {
                continue
            }
            for (subKey, subValue) in nested where workingDictionary[subKey] == nil {
                workingDictionary[subKey] = subValue
            }
            // Drop the original platform key so its blob doesn't end up
            // as a separate confusing section.
            workingDictionary.removeValue(forKey: nestKey)
        }

        for key in workingDictionary.keys.sorted() {
            // NOTE: previously this loop skipped `extensionAttributes` so
            // the typed `extractExtensionAttributes` had exclusive ownership.
            // That regressed visibility — whenever the typed extractor
            // missed a tenant-specific shape, the EA data disappeared
            // entirely because the raw section was never built. Now we
            // build the raw section for every key (EA included) so the
            // frame always has a fallback dump.

            guard let value = workingDictionary[key] else {
                continue
            }

            let category = categorize(rawKey: key)

            if let nestedDictionary = value as? [String: Any] {
                let items = nestedDictionary
                    .keys
                    .sorted()
                    .compactMap { nestedKey -> SupportDetailItem? in
                        guard let nestedValue = nestedDictionary[nestedKey],
                              let displayValue = displayString(for: nestedValue)
                        else {
                            return nil
                        }

                        return SupportDetailItem(key: nestedKey, value: displayValue)
                    }

                if items.isEmpty == false {
                    let section = SupportDetailSection(title: sectionTitle(for: key), items: items)
                    sections.append(section)
                    bucketed[category, default: []].append(section)
                }

                continue
            }

            if let array = value as? [Any] {
                // Pretty-print arrays. Old behaviour emitted `count` plus
                // `item 1: <stringified dict>` blobs that were unreadable.
                // New behaviour: for each element, if it's a dict, treat
                // the most descriptive field (name / displayName / title)
                // as the label and emit either a `name → value` row (when
                // a value field exists) or expand the element's
                // distinguishing keys into individual rows. Arrays of
                // scalars get one row per element.
                let items = prettyItems(forArray: array)
                if items.isEmpty == false {
                    let section = SupportDetailSection(
                        title: sectionTitle(for: key),
                        items: items
                    )
                    sections.append(section)
                    bucketed[category, default: []].append(section)
                }
                continue
            }

            if let scalar = displayString(for: value) {
                let section = SupportDetailSection(
                    title: sectionTitle(for: key),
                    items: [SupportDetailItem(key: key, value: scalar)]
                )
                sections.append(section)
                bucketed[category, default: []].append(section)
            }
        }

        return (sections, CategorizedDeviceDetail(sectionsByCategory: bucketed))
    }

    /// Turns an arbitrary `[Any]` value into a readable flat list of
    /// `SupportDetailItem` rows for raw-section display. Mirrors the
    /// `extensionAttributes` parsing instinct ("name → value" pairs) for
    /// every array shape so configurationProfiles, groupMemberships,
    /// certificates, profiles, etc. all render readable rows instead of
    /// stringified-dict blobs.
    ///
    /// Heuristics, in order:
    ///   1. Scalars (string / number / bool) — one row per element with a
    ///      blank label.
    ///   2. Dicts with a `name`/`displayName`/`title` AND a `value` —
    ///      emit `name → value`.
    ///   3. Dicts with a `name`/`displayName`/`title` only — use that as
    ///      the label and concatenate the remaining significant keys into
    ///      the value (skipping ids and timestamps).
    ///   4. Dicts without a name — emit each significant key as its own
    ///      row, prefixed with the element index.
    ///
    /// Cap is 100 emitted rows per section so a huge `applications` array
    /// doesn't blow up the inner ScrollView.
    private func prettyItems(forArray array: [Any]) -> [SupportDetailItem] {
        var rows: [SupportDetailItem] = []
        let nameKeys = ["name", "displayName", "title", "label", "profileName"]
        let valueKeys = ["value", "version", "status", "state", "identifier", "scope"]
        let ignoreKeys: Set<String> = [
            "id", "uuid", "guid", "definitionId",
            "createdAt", "updatedAt", "redeployed",
            "dateUpdated", "dateCreated"
        ]
        let maxRows = 100

        for (index, element) in array.enumerated() {
            if rows.count >= maxRows {
                rows.append(
                    SupportDetailItem(
                        key: "…",
                        value: "Showing first \(maxRows) of \(array.count) entries."
                    )
                )
                break
            }

            // Scalar
            if let scalar = extractStringValue(from: element),
               (element is [String: Any]) == false,
               (element is [Any]) == false
            {
                rows.append(SupportDetailItem(key: "\(index + 1)", value: scalar))
                continue
            }

            guard let dict = element as? [String: Any] else {
                if let preview = displayString(for: element) {
                    rows.append(SupportDetailItem(key: "\(index + 1)", value: preview))
                }
                continue
            }

            // Best-effort name + value
            let name = nameKeys.lazy.compactMap { self.extractStringValue(from: dict[$0]) }.first
            let value = valueKeys.lazy.compactMap { key -> String? in
                if key == "value", let array = dict[key] as? [Any] {
                    let joined = array.compactMap { self.extractStringValue(from: $0) }.joined(separator: ", ")
                    return joined.isEmpty ? nil : joined
                }
                return self.extractStringValue(from: dict[key])
            }.first

            if let name, let value {
                rows.append(SupportDetailItem(key: name, value: value))
                continue
            }
            if let name {
                // Compose value from non-ignored remaining keys.
                let rest = dict.keys
                    .sorted()
                    .filter { key in
                        ignoreKeys.contains(key) == false
                            && nameKeys.contains(key) == false
                    }
                    .compactMap { key -> String? in
                        guard let displayValue = self.extractStringValue(from: dict[key]) else { return nil }
                        return "\(key): \(displayValue)"
                    }
                    .joined(separator: " · ")
                rows.append(SupportDetailItem(
                    key: name,
                    value: rest.isEmpty ? "(no additional fields)" : rest
                ))
                continue
            }

            // No name — flatten this element's significant fields.
            let elementRows = dict.keys
                .sorted()
                .filter { ignoreKeys.contains($0) == false }
                .compactMap { key -> SupportDetailItem? in
                    guard let displayValue = self.extractStringValue(from: dict[key]) else { return nil }
                    return SupportDetailItem(
                        key: "[\(index + 1)] \(key)",
                        value: displayValue
                    )
                }
            rows.append(contentsOf: elementRows)
        }

        return rows
    }

    /// Top-level raw payload keys recognized as the Extension Attributes
    /// array. Matched case-insensitively so both modern (`extensionAttributes`)
    /// and snake-case variants from legacy endpoints route to the typed
    /// extractor instead of the generic flattener.
    private static let extensionAttributeKeys: Set<String> = [
        "extensionattributes",
        "extension_attributes"
    ]

    /// Maps a raw top-level inventory key (e.g. `hardware`, `userAndLocation`,
    /// `diskEncryption`) to its `SupportDeviceCategory`. The mapping uses
    /// case-insensitive contains so minor key drift across Jamf Pro API
    /// versions still routes correctly.
    private func categorize(rawKey: String) -> SupportDeviceCategory {
        let key = rawKey.lowercased()

        // ----- OS family (top-level flat keys from v1 mobile classic) -----
        if key.contains("operatingsystem")
            || key == "os"
            || key.contains("os_")
            || key.hasPrefix("osversion")
            || key.hasPrefix("osbuild")
            || key.hasPrefix("ossupplemental")
            || key.hasPrefix("osrapid")
            || key == "type"   // v1 mobile platform indicator ("ios", "tvos", etc.)
        {
            return .os
        }

        // ----- Extension Attributes -----
        if key.contains("extensionattribute") || key == "extension_attributes" {
            return .extensionAttributes
        }

        // ----- Hardware -----
        if key.contains("hardware")
            || key.contains("model")
            || key.contains("battery")
            || key == "bleCapable".lowercased()
            || key.contains("capacityMb".lowercased())
            || key.contains("availableMb".lowercased())
            || key.contains("percentageUsed".lowercased())
            || key == "softwareUpdateDeviceId".lowercased()
        {
            return .hardware
        }

        // ----- Storage -----
        if key.contains("storage")
            || key.contains("disk")
            || key.contains("volume")
            || key.contains("partition")
        {
            return .storage
        }

        // ----- Security -----
        if key.contains("security")
            || key.contains("encryption")
            || key.contains("filevault")
            || key.contains("gatekeeper")
            || key.contains("xprotect")
            || key.contains("recoverylock")
            || key.contains("activationlock")
            || key.contains("certificate")
            || key.contains("passcode")
            || key.contains("supervis")
            || key.contains("jailbroken")
            || key.contains("attestation")
            || key.contains("lostmode")
            || key.contains("cloudbackup")
            || key.contains("locatorservice")
            || key.contains("mdmcapableusers")
        {
            return .security
        }

        // ----- Network -----
        if key.contains("network")
            || key.contains("wifi")
            || key.contains("ethernet")
            || key.contains("ipaddress")
            || key.contains("bluetoothmac")
            || key.contains("macaddress")
            || key.contains("imei")
            || key.contains("meid")
            || key.contains("iccid")
            || key.contains("carrier")
            || key.contains("hotspot")
            || key.contains("voiceroaming")
            || key.contains("dataroaming")
            || key.contains("cellular")
            || key.contains("phonenumber")
        {
            return .network
        }

        // ----- Profiles -----
        if key.contains("configurationprofile")
            || (key.contains("profile") && key.contains("group") == false)
        {
            return .profiles
        }

        // ----- Groups -----
        if key == "groups" || key.contains("groupmembership") || key.contains("membership") {
            return .groups
        }

        // ----- Applications -----
        if key.contains("application") || key == "ebooks" || key == "attachments" {
            return .applications
        }

        // ----- General (catch-all for identity/ownership/timestamps) -----
        if key.contains("general")
            || key.contains("summary")
            || key.contains("userandlocation")
            || key.contains("user_and_location")
            || key.contains("location")
            || key.contains("site")
            || key.contains("purchasing")
            || key == "id"
            || key == "udid"
            || key == "name"
            || key == "serialnumber"
            || key == "assettag"
            || key == "managementid"
            || key == "managed"
            || key == "deviceownershiplevel"
            || key.contains("enrollment")
            || key.contains("timestamp")
            || key.contains("timezone")
            || key.contains("declarative")
            || key == "enforcename"
        {
            return .general
        }

        return .other
    }

    /// Parses Jamf extension attributes into typed `SupportExtensionAttribute`
    /// instances regardless of where they appear in the payload (top-level,
    /// nested under `general`, or nested under `userAndLocation`).
    ///
    /// Each element of the array is expected to be a dictionary with a
    /// `name` and a `value` (string or array of strings). The previous
    /// generic-array rendering produced lines like `"item 1: { ... }"`
    /// which is the bug this method exists to fix.
    private func extractExtensionAttributes(
        from payload: [String: Any]
    ) -> [SupportExtensionAttribute] {
        let candidatePaths: [String] = [
            "extensionAttributes",
            "general.extensionAttributes",
            "userAndLocation.extensionAttributes",
            "location.extensionAttributes"
        ]

        for path in candidatePaths {
            let resolved = resolveValue(atPath: path, in: payload)
            guard let array = resolved as? [Any] else {
                continue
            }

            let parsed = array.compactMap(parseExtensionAttribute(from:))
            if parsed.isEmpty == false {
                return parsed
            }
        }

        return []
    }

    /// Single-element parser used by `extractExtensionAttributes`. Returns
    /// `nil` for entries whose `name` is missing — the table view has no
    /// useful row to render without it.
    private func parseExtensionAttribute(from element: Any) -> SupportExtensionAttribute? {
        guard let dict = element as? [String: Any] else {
            return nil
        }

        let attributeID = extractStringValue(from: dict["id"])
            ?? extractStringValue(from: dict["definitionId"])
            ?? ""
        guard let name = extractStringValue(from: dict["name"])
            ?? extractStringValue(from: dict["displayName"])
        else {
            return nil
        }

        // Three shapes seen in the wild:
        //   * v1 mobile classic: `value: [String]` (array of strings).
        //   * v2 computer `userAndLocation.extensionAttributes`: pluralized
        //     `values: [String]`.
        //   * Older v1 / scalar: `value: String`.
        // Check arrays first (handles both `value` and `values`).
        let value: String
        if let arrayValue = dict["values"] as? [Any] {
            let joined = arrayValue.compactMap { extractStringValue(from: $0) }.joined(separator: ", ")
            value = joined
        } else if let arrayValue = dict["value"] as? [Any] {
            let joined = arrayValue.compactMap { extractStringValue(from: $0) }.joined(separator: ", ")
            value = joined
        } else if let stringValue = dict["value"] as? String {
            value = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let nestedValue = extractStringValue(from: dict["value"])
            ?? extractStringValue(from: dict["values"])
        {
            value = nestedValue
        } else {
            value = ""
        }

        let type = extractStringValue(from: dict["dataType"]) ?? extractStringValue(from: dict["type"])
        let category = extractStringValue(from: dict["categoryName"]) ?? extractStringValue(from: dict["category"])

        return SupportExtensionAttribute(
            attributeID: attributeID,
            name: name,
            value: value,
            type: type,
            category: category
        )
    }

    /// Extracts model, CPU, RAM, storage, and battery fields used by the
    /// General/Hardware frames.
    ///
    /// **Computer path** — reads explicit `hardware.cpuType`,
    /// `hardware.coreCount`, `hardware.totalRamMegabytes`, and the nested
    /// `hardware.storage.disks[].partitions[]` shape. Falls back to the
    /// older `hardware.storageCapacityMegabytes` /
    /// `general.bootDriveAvailableSpaceMegabytes` flat shape.
    ///
    /// **Mobile path** — Jamf inventory does NOT expose CPU/RAM directly
    /// for iOS/iPadOS. Reads `hardware.modelIdentifier` and looks it up in
    /// `SupportTechnicianDeviceSpecCatalog` to derive chip name, CPU/GPU/Neural-core
    /// counts, and RAM (`ramGB(forCapacityMb:)` handles the M4 iPad Pro
    /// split-tier case). Storage and battery use the flat
    /// `hardware.capacityMb`, `hardware.availableSpaceMb`,
    /// `hardware.usedSpacePercentage`, `hardware.batteryLevel`, and
    /// `hardware.batteryHealth` paths the Mobile Device Search module
    /// also reads from.
    private func extractHardwareSpecs(
        from payload: [String: Any],
        assetType: SupportAssetType
    ) -> SupportHardwareSpecs? {
        // Field paths cover three Jamf API shapes:
        //   * v2-nested (computers): `hardware.X`, `general.X`
        //   * v1-classic mobile: top-level flat + `ios.X` / `tvos.X` /
        //     `visionos.X` / `watchos.X` for platform-specific fields
        //   * Modern flat: bare top-level keys
        // Strict resolveValue means the first matching path wins; any
        // path that doesn't resolve simply moves on.
        let modelName = extractString(
            using: [
                "hardware.model", "general.model", "model",
                "ios.model", "tvos.model", "visionos.model", "watchos.model"
            ],
            from: payload
        )
        let modelIdentifier = extractString(
            using: [
                "hardware.modelIdentifier", "general.modelIdentifier", "modelIdentifier",
                "ios.modelIdentifier", "tvos.modelIdentifier",
                "visionos.modelIdentifier", "watchos.modelIdentifier",
                "softwareUpdateDeviceId"
            ],
            from: payload
        )
        let modelNumber = extractString(
            using: [
                "hardware.modelNumber", "general.modelNumber", "modelNumber",
                "ios.modelNumber", "tvos.modelNumber",
                "visionos.modelNumber", "watchos.modelNumber"
            ],
            from: payload
        )

        // Computer-side direct fields.
        var cpuType = extractString(
            using: ["hardware.cpuType", "hardware.processorType", "processorType"],
            from: payload
        )
        var coreCount = positiveInt(
            extractInt(
            using: ["hardware.coreCount", "hardware.processorCount", "hardware.cpuCount", "coreCount"],
            from: payload
            )
        )
        let cpuSpeedMhz = positiveInt(
            extractInt(
            using: ["hardware.processorSpeedMhz", "hardware.cpuSpeedMhz", "processorSpeedMhz"],
            from: payload
            )
        )
        var totalRamMB = positiveInt(
            extractInt(
            using: ["hardware.totalRamMegabytes", "hardware.totalRamMb", "totalRamMegabytes"],
            from: payload
            )
        )

        let (storageTotal, storageAvailable) = extractStorageMegabytes(
            from: payload, assetType: assetType
        )
        let usedSpacePercentage = extractInt(
            using: [
                "hardware.usedSpacePercentage", "usedSpacePercentage",
                "ios.percentageUsed", "tvos.percentageUsed",
                "visionos.percentageUsed", "watchos.percentageUsed"
            ],
            from: payload
        )
        let batteryLevel = extractInt(
            using: [
                // Computer paths — Macs use `hardware.batteryCapacityPercent`.
                "hardware.batteryCapacityPercent",
                "hardware.batteryLevel",
                "hardware.batteryPercentage",
                "batteryLevel",
                "hardware.batteryCapacity",
                // Mobile typed-nest variants.
                "ios.batteryLevel", "tvos.batteryLevel",
                "visionos.batteryLevel", "watchos.batteryLevel"
            ],
            from: payload
        )
        let batteryHealth = extractString(
            using: [
                "hardware.batteryHealth", "batteryHealth",
                "ios.batteryHealth", "tvos.batteryHealth",
                "visionos.batteryHealth", "watchos.batteryHealth"
            ],
            from: payload
        )
        let bluetoothMacAddress = extractString(
            using: [
                "hardware.bluetoothMacAddress",
                "bluetoothMacAddress",
                "general.bluetoothMacAddress"
            ],
            from: payload
        )
        let wifiMacAddress = extractString(
            using: [
                "hardware.wifiMacAddress",
                "hardware.macAddress",
                "general.macAddress",
                "wifiMacAddress",
                "macAddress"
            ],
            from: payload
        )

        // Derive missing chip / cores / RAM from Support Technician's own
        // model-identifier catalog. This mirrors the Mobile Device Search
        // process without making the modules communicate with each other.
        var chipName: String?
        var gpuCoreCount: Int?
        var neuralCoreCount: Int?
        var gpuCoreDescription: String?
        var cpuFrequencyDescription: String?
        var memoryDescription: String?
        if let identifier = modelIdentifier,
           let info = SupportTechnicianDeviceSpecCatalog.info(for: identifier)
        {
            chipName = info.chipName
            // Only fill in derived CPU fields when the payload didn't carry them
            // (so Macs that report cpuType="Apple M3" / coreCount=8 directly
            // aren't replaced by the catalog).
            if coreCount == nil { coreCount = info.cpuCoreCount }
            if cpuType == nil { cpuType = info.chipName }
            gpuCoreCount = info.gpuCoreCount
            gpuCoreDescription = info.gpuCoreDescription
            neuralCoreCount = info.neuralCoreCount
            cpuFrequencyDescription = info.cpuFrequencyDescription
            memoryDescription = info.memoryDescription
            if totalRamMB == nil, let ramGB = info.ramGB(storageTotal) {
                totalRamMB = ramGB * 1024
            }
        }

        let specs = SupportHardwareSpecs(
            modelName: modelName,
            modelIdentifier: modelIdentifier,
            modelNumber: modelNumber,
            cpuType: cpuType,
            chipName: chipName,
            coreCount: coreCount,
            gpuCoreCount: gpuCoreCount,
            gpuCoreDescription: gpuCoreDescription,
            neuralCoreCount: neuralCoreCount,
            cpuSpeedMhz: cpuSpeedMhz,
            cpuFrequencyDescription: cpuFrequencyDescription,
            totalRamMB: totalRamMB,
            memoryDescription: memoryDescription,
            storageTotalMB: storageTotal,
            storageAvailableMB: storageAvailable,
            usedSpacePercentage: usedSpacePercentage,
            batteryLevel: batteryLevel,
            batteryHealth: batteryHealth,
            bluetoothMacAddress: bluetoothMacAddress,
            wifiMacAddress: wifiMacAddress
        )

        return specs.isEmpty ? nil : specs
    }

    /// Returns the (totalMB, availableMB) tuple for the device's primary
    /// volume.
    ///
    /// For mobile devices Jamf uses flat `hardware.capacityMb` /
    /// `hardware.availableSpaceMb`. For computers the modern shape is
    /// nested `hardware.storage.disks[].partitions[].sizeMegabytes`. The
    /// extractor tries flat first (covers mobile + older Mac inventory),
    /// then the nested shape.
    private func extractStorageMegabytes(
        from payload: [String: Any],
        assetType: SupportAssetType
    ) -> (total: Int?, available: Int?) {
        // Flat / mobile shape — winner for iOS/iPadOS, also works on older Macs.
        // Real iPad payloads from this tenant use `ios.capacityMb` /
        // `ios.availableMb` — adding those (and the equivalents for tvOS,
        // visionOS, watchOS) ensures storage isn't lost to wrong paths.
        let flatTotal = extractInt(
            using: [
                "hardware.capacityMb",
                "hardware.storageCapacityMegabytes",
                "general.storageCapacityMegabytes",
                "storage.capacityMb",
                "storage.storageCapacityMegabytes",
                "capacityMb",
                "ios.capacityMb", "tvos.capacityMb",
                "visionos.capacityMb", "watchos.capacityMb"
            ],
            from: payload
        )
        let flatAvailable = extractInt(
            using: [
                "hardware.availableSpaceMb",
                "general.bootDriveAvailableSpaceMegabytes",
                "hardware.bootDriveAvailableSpaceMegabytes",
                "storage.bootDriveAvailableSpaceMegabytes",
                "storage.availableSpaceMb",
                "availableSpaceMb",
                "ios.availableMb", "tvos.availableMb",
                "visionos.availableMb", "watchos.availableMb"
            ],
            from: payload
        )

        if flatTotal != nil {
            return (flatTotal, flatAvailable)
        }

        // Modern Mac shape: storage.disks[].partitions[].
        let diskPathCandidates = [
            "hardware.storage.disks",
            "storage.disks",
            "disks"
        ]
        for diskPath in diskPathCandidates {
            guard let disks = resolveValue(atPath: diskPath, in: payload) as? [Any] else {
                continue
            }
            var bestTotal: Int?
            var bestAvailable: Int?
            for disk in disks {
                guard let diskDict = disk as? [String: Any] else {
                    continue
                }
                if let diskSize = positiveInt(extractInt(from: diskDict["sizeMegabytes"])),
                   diskSize > (bestTotal ?? 0)
                {
                    bestTotal = diskSize
                    bestAvailable = flatAvailable
                }

                guard let partitions = diskDict["partitions"] as? [Any] else { continue }
                for partition in partitions {
                    guard let partitionDict = partition as? [String: Any] else { continue }
                    let total = positiveInt(extractInt(from: partitionDict["sizeMegabytes"]))
                    let avail = positiveInt(extractInt(from: partitionDict["availableMegabytes"])) ?? flatAvailable
                    guard let total else { continue }
                    if total > (bestTotal ?? 0) {
                        bestTotal = total
                        bestAvailable = avail
                    }
                }
            }
            if bestTotal != nil {
                return (bestTotal, bestAvailable)
            }
        }

        return (flatAvailable == nil ? nil : nil, flatAvailable)
    }

    /// Extracts OS version / build / supplemental build / RSR data for the
    /// OS frame. Reads `general.osVersion` (mobile + modern computer),
    /// `operatingSystem.version` (computer alternate), `general.osBuild`,
    /// `general.osSupplementalBuildVersion`, `general.osRapidSecurityResponse`,
    /// and falls back to root-level keys.
    private func extractOSInfo(from payload: [String: Any]) -> SupportOSInfo? {
        // v1 mobile classic stores these at the top level; v2 nests under
        // `general.X` or `operatingSystem.X`.
        let version = extractString(
            using: [
                "general.osVersion",
                "operatingSystem.version",
                "osVersion"
            ],
            from: payload
        )
        let build = extractString(
            using: [
                "general.osBuild",
                "operatingSystem.build",
                "osBuild"
            ],
            from: payload
        )
        let supplementalBuild = extractString(
            using: [
                "general.osSupplementalBuildVersion",
                "operatingSystem.supplementalBuildVersion",
                "osSupplementalBuildVersion"
            ],
            from: payload
        )
        let rsr = extractString(
            using: [
                "general.osRapidSecurityResponse",
                "operatingSystem.rapidSecurityResponse",
                "osRapidSecurityResponse"
            ],
            from: payload
        )
        // Mobile classic uses `type` ("ios" / "tvos" / "visionos" /
        // "watchos") to indicate the platform — surface that as the OS
        // name when no explicit operatingSystem.name field is present.
        let osName = extractString(
            using: [
                "operatingSystem.name",
                "general.osName",
                "osName",
                "type"
            ],
            from: payload
        )

        let info = SupportOSInfo(
            version: version,
            build: build,
            supplementalBuildVersion: supplementalBuild,
            rapidSecurityResponseVersion: rsr,
            osName: osName
        )
        return info.isEmpty ? nil : info
    }

    /// Extracts security-posture fields for the Security frame. Combines
    /// mobile-leaning paths (`security.activationLockEnabled`,
    /// `security.passcodePresent`, `general.supervised`) with computer-
    /// leaning paths (`diskEncryption.individualRecoveryKeyValidityStatus`,
    /// `security.firewallEnabled`, `security.gatekeeperStatus`,
    /// `security.sipStatus`).
    private func extractSecurityProfile(from payload: [String: Any]) -> SupportSecurityProfile? {
        // For mobile classic the security block is nested under the
        // typed platform key — `ios.security.X` / `tvos.security.X` etc.
        // Append those variants alongside the v2 nested and bare paths.
        let reportedEncrypted = extractBool(
            using: [
                "security.isEncrypted", "hardware.isEncrypted", "encrypted",
                "diskEncryption.fileVault2Enabled",
                "ios.security.isEncrypted", "tvos.security.isEncrypted",
                "visionos.security.isEncrypted", "watchos.security.isEncrypted"
            ],
            from: payload
        )
        let fileVaultState = extractString(
            using: [
                "operatingSystem.fileVault2Status",
                "diskEncryption.bootPartitionEncryptionDetails.partitionFileVault2State",
                "security.fileVault2Status"
            ],
            from: payload
        )
        let isEncrypted = reportedEncrypted ?? encryptionStateIsEnabled(fileVaultState)
        let blockEncryptionCapable = extractBool(
            using: [
                "hardware.blockEncryptionCapable", "blockEncryptionCapable",
                "ios.security.blockLevelEncryptionCapable",
                "tvos.security.blockLevelEncryptionCapable",
                "visionos.security.blockLevelEncryptionCapable",
                "watchos.security.blockLevelEncryptionCapable",
                "blockLevelEncryptionCapable"
            ],
            from: payload
        )
        let fileEncryptionCapable = extractBool(
            using: [
                "hardware.fileEncryptionCapable", "fileEncryptionCapable",
                "ios.security.fileLevelEncryptionCapable",
                "tvos.security.fileLevelEncryptionCapable",
                "visionos.security.fileLevelEncryptionCapable",
                "watchos.security.fileLevelEncryptionCapable",
                "fileLevelEncryptionCapable"
            ],
            from: payload
        )
        let hardwareEncryptionSupported = extractInt(
            using: [
                "hardware.hardwareEncryptionSupported",
                "security.hardwareEncryption",
                "hardwareEncryptionSupported",
                "ios.security.hardwareEncryption",
                "hardwareEncryption"
            ],
            from: payload
        )
        let dataProtected = extractBool(
            using: [
                "security.dataProtected", "dataProtected",
                "ios.security.dataProtected",
                "tvos.security.dataProtected",
                "visionos.security.dataProtected",
                "watchos.security.dataProtected"
            ],
            from: payload
        )
        let activationLockEnabled = extractBool(
            using: [
                "security.activationLockEnabled", "activationLockEnabled",
                "ios.security.activationLockEnabled",
                "tvos.security.activationLockEnabled",
                "visionos.security.activationLockEnabled",
                "watchos.security.activationLockEnabled"
            ],
            from: payload
        )
        let lostModeEnabled = extractBool(
            using: [
                "security.lostModeEnabled", "lostModeEnabled",
                "ios.security.lostModeEnabled",
                "tvos.security.lostModeEnabled",
                "visionos.security.lostModeEnabled",
                "watchos.security.lostModeEnabled"
            ],
            from: payload
        )
        let passcodePresent = extractBool(
            using: [
                "security.passcodePresent", "passcodePresent",
                "ios.security.passcodePresent",
                "tvos.security.passcodePresent",
                "visionos.security.passcodePresent",
                "watchos.security.passcodePresent"
            ],
            from: payload
        )
        let passcodeCompliant = extractBool(
            using: [
                "security.passcodeCompliant", "passcodeCompliant",
                "ios.security.passcodeCompliant",
                "tvos.security.passcodeCompliant",
                "visionos.security.passcodeCompliant",
                "watchos.security.passcodeCompliant"
            ],
            from: payload
        )
        let passcodeCompliantWithProfile = extractBool(
            using: [
                "security.passcodeCompliantWithProfile", "passcodeCompliantWithProfile",
                "ios.security.passcodeCompliantWithProfile",
                "tvos.security.passcodeCompliantWithProfile",
                "visionos.security.passcodeCompliantWithProfile",
                "watchos.security.passcodeCompliantWithProfile"
            ],
            from: payload
        )
        let supervised = extractBool(
            using: ["general.supervised", "supervised"],
            from: payload
        )
        let jailbroken = extractBool(
            using: [
                "security.jailbroken", "hardware.jailbrokenIndicator", "jailbroken",
                "ios.security.jailbreakDetected",
                "ios.security.jailbroken",
                "jailbreakDetected"
            ],
            from: payload
        )
        let fileVaultStatus = extractString(
            using: [
                "operatingSystem.fileVault2Status",
                "security.fileVault2Status",
                "diskEncryption.bootPartitionEncryptionDetails.partitionFileVault2State",
                "diskEncryption.diskEncryptionConfigurationName"
            ],
            from: payload
        )
        let recoveryKeyStatus = extractString(
            using: [
                "diskEncryption.individualRecoveryKeyValidityStatus",
                "individualRecoveryKeyValidityStatus"
            ],
            from: payload
        )
        let recoveryLockEnabled = extractBool(
            using: ["security.recoveryLockEnabled", "recoveryLockEnabled"],
            from: payload
        )
        let firewallEnabled = extractBool(
            using: ["security.firewallEnabled", "firewallEnabled"],
            from: payload
        )
        let gatekeeperStatus = extractString(
            using: ["security.gatekeeperStatus", "gatekeeperStatus"],
            from: payload
        )
        let sipStatus = extractString(
            using: ["security.sipStatus", "sipStatus"],
            from: payload
        )
        let xprotectVersion = extractString(
            using: ["security.xprotectVersion", "xprotectVersion"],
            from: payload
        )
        let secureBootLevel = extractString(
            using: ["security.secureBootLevel", "secureBootLevel"],
            from: payload
        )
        let externalBootLevel = extractString(
            using: ["security.externalBootLevel", "externalBootLevel"],
            from: payload
        )
        let autoLoginDisabled = extractBool(
            using: ["security.autoLoginDisabled", "autoLoginDisabled"],
            from: payload
        )
        let remoteDesktopEnabled = extractBool(
            using: ["security.remoteDesktopEnabled", "remoteDesktopEnabled"],
            from: payload
        )
        let bootstrapTokenAllowed = extractBool(
            using: ["security.bootstrapTokenAllowed", "bootstrapTokenAllowed"],
            from: payload
        )
        let bootstrapTokenEscrowedStatus = extractString(
            using: [
                "security.bootstrapTokenEscrowedStatus",
                "security.bootstrapTokenEscrowed",
                "bootstrapTokenEscrowedStatus"
            ],
            from: payload
        )
        let attestationStatus = extractString(
            using: ["security.attestationStatus", "attestationStatus"],
            from: payload
        )
        let lastSuccessfulAttestation = extractString(
            using: [
                "security.lastSuccessfulAttestation",
                "security.lastSuccessfulAttestationDate",
                "lastSuccessfulAttestation"
            ],
            from: payload
        )

        let profile = SupportSecurityProfile(
            isEncrypted: isEncrypted,
            blockEncryptionCapable: blockEncryptionCapable,
            fileEncryptionCapable: fileEncryptionCapable,
            hardwareEncryptionSupported: hardwareEncryptionSupported,
            dataProtected: dataProtected,
            activationLockEnabled: activationLockEnabled,
            lostModeEnabled: lostModeEnabled,
            passcodePresent: passcodePresent,
            passcodeCompliant: passcodeCompliant,
            passcodeCompliantWithProfile: passcodeCompliantWithProfile,
            supervised: supervised,
            jailbroken: jailbroken,
            fileVaultStatus: fileVaultStatus,
            recoveryKeyStatus: recoveryKeyStatus,
            recoveryLockEnabled: recoveryLockEnabled,
            firewallEnabled: firewallEnabled,
            gatekeeperStatus: gatekeeperStatus,
            sipStatus: sipStatus,
            xprotectVersion: xprotectVersion,
            secureBootLevel: secureBootLevel,
            externalBootLevel: externalBootLevel,
            autoLoginDisabled: autoLoginDisabled,
            remoteDesktopEnabled: remoteDesktopEnabled,
            bootstrapTokenAllowed: bootstrapTokenAllowed,
            bootstrapTokenEscrowedStatus: bootstrapTokenEscrowedStatus,
            attestationStatus: attestationStatus,
            lastSuccessfulAttestation: lastSuccessfulAttestation
        )
        return profile.isEmpty ? nil : profile
    }

    /// Extracts IP / MAC / cellular fields for the Network frame.
    private func extractNetworkInfo(from payload: [String: Any]) -> SupportNetworkInfo? {
        // v1 mobile classic stores MACs + IP at the top level; cellular
        // details (IMEI, carrier, ICCID, etc.) live under
        // `ios.network.X` (or the matching typed-platform sibling).
        let ipAddress = extractString(
            using: ["general.ipAddress", "general.lastIpAddress", "ipAddress", "lastIpAddress"],
            from: payload
        )
        let lastReportedIp = extractString(
            using: ["general.lastReportedIp", "general.reportedIpAddress", "lastReportedIp"],
            from: payload
        )
        let lastReportedIpV4 = extractString(
            using: ["general.lastReportedIpV4", "lastReportedIpV4"],
            from: payload
        )
        let lastReportedIpV6 = extractString(
            using: ["general.lastReportedIpV6", "lastReportedIpV6"],
            from: payload
        )
        let wifiMacAddress = extractString(
            using: [
                "hardware.wifiMacAddress",
                "hardware.macAddress",
                "general.macAddress",
                "wifiMacAddress",
                "macAddress"
            ],
            from: payload
        )
        let bluetoothMacAddress = extractString(
            using: [
                "hardware.bluetoothMacAddress",
                "bluetoothMacAddress",
                "general.bluetoothMacAddress"
            ],
            from: payload
        )
        let hostname = extractString(
            using: ["general.hostName", "general.hostname", "hostName"],
            from: payload
        )
        let networkAdapterType = extractString(
            using: ["hardware.networkAdapterType", "networkAdapterType"],
            from: payload
        )
        let alternateMacAddress = extractString(
            using: ["hardware.altMacAddress", "altMacAddress"],
            from: payload
        )
        let alternateNetworkAdapterType = extractString(
            using: ["hardware.altNetworkAdapterType", "altNetworkAdapterType"],
            from: payload
        )
        let nicSpeed = extractString(
            using: ["hardware.nicSpeed", "nicSpeed"],
            from: payload
        )
        let bleCapable = extractBool(
            using: [
                "hardware.bleCapable", "bleCapable",
                "ios.bleCapable", "tvos.bleCapable",
                "visionos.bleCapable", "watchos.bleCapable"
            ],
            from: payload
        )
        let cellularCarrier = extractString(
            using: [
                "network.currentCarrierNetwork",
                "hardware.currentCarrierNetwork",
                "currentCarrierNetwork",
                "ios.network.currentCarrierNetwork",
                "tvos.network.currentCarrierNetwork",
                "visionos.network.currentCarrierNetwork",
                "watchos.network.currentCarrierNetwork"
            ],
            from: payload
        )
        let cellularTechnology = extractString(
            using: [
                "network.cellularTechnology",
                "ios.network.cellularTechnology",
                "cellularTechnology"
            ],
            from: payload
        )
        let imei = extractString(
            using: [
                "hardware.imei", "imei",
                "ios.network.imei", "tvos.network.imei",
                "visionos.network.imei", "watchos.network.imei"
            ],
            from: payload
        )
        let imei2 = extractString(
            using: ["hardware.imei2", "imei2", "ios.network.imei2"],
            from: payload
        )
        let meid = extractString(
            using: [
                "hardware.meid", "meid",
                "ios.network.meid", "tvos.network.meid",
                "visionos.network.meid", "watchos.network.meid"
            ],
            from: payload
        )
        let iccid = extractString(
            using: [
                "hardware.iccid", "iccid",
                "ios.network.iccid", "tvos.network.iccid",
                "visionos.network.iccid", "watchos.network.iccid"
            ],
            from: payload
        )
        let eid = extractString(
            using: [
                "hardware.eid", "eid",
                "ios.network.eid", "tvos.network.eid",
                "visionos.network.eid", "watchos.network.eid"
            ],
            from: payload
        )
        let phoneNumber = extractString(
            using: ["network.phoneNumber", "ios.network.phoneNumber", "phoneNumber"],
            from: payload
        )
        let dataRoamingEnabled = extractBool(
            using: [
                "network.dataRoamingEnabled",
                "ios.network.dataRoamingEnabled",
                "dataRoamingEnabled"
            ],
            from: payload
        )
        let voiceRoamingEnabled = extractBool(
            using: [
                "network.voiceRoamingEnabled",
                "ios.network.voiceRoamingEnabled",
                "voiceRoamingEnabled"
            ],
            from: payload
        )
        let roaming = extractBool(
            using: ["network.roaming", "ios.network.roaming", "roaming"],
            from: payload
        )
        let personalHotspotEnabled = extractBool(
            using: [
                "network.personalHotspotEnabled",
                "ios.network.personalHotspotEnabled",
                "personalHotspotEnabled"
            ],
            from: payload
        )
        let hasReportedAddress = [
            ipAddress,
            lastReportedIp,
            lastReportedIpV4,
            lastReportedIpV6
        ]
            .contains { value in
                guard let value else { return false }
                return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            }
        let adapterText = [
            networkAdapterType,
            alternateNetworkAdapterType
        ]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        let hasNetworkHardware = adapterText.isEmpty == false
            || wifiMacAddress != nil
            || bluetoothMacAddress != nil
            || alternateMacAddress != nil
        let connectionActive: Bool? = hasReportedAddress ? true : (hasNetworkHardware ? false : nil)
        let wifiEnabled: Bool? = {
            if adapterText.contains("ieee80211")
                || adapterText.contains("wi-fi")
                || adapterText.contains("wifi")
                || adapterText.contains("airport")
            {
                return true
            }
            if wifiMacAddress != nil {
                return true
            }
            if adapterText.isEmpty == false {
                return false
            }
            return nil
        }()
        let bluetoothEnabled: Bool? = {
            if bluetoothMacAddress != nil {
                return true
            }
            return bleCapable
        }()
        let ssid = extractSSID(from: payload)

        let info = SupportNetworkInfo(
            ipAddress: ipAddress,
            lastReportedIp: lastReportedIp,
            lastReportedIpV4: lastReportedIpV4,
            lastReportedIpV6: lastReportedIpV6,
            connectionActive: connectionActive,
            wifiMacAddress: wifiMacAddress,
            wifiEnabled: wifiEnabled,
            ssid: ssid,
            bluetoothMacAddress: bluetoothMacAddress,
            bluetoothEnabled: bluetoothEnabled,
            hostname: hostname,
            networkAdapterType: networkAdapterType,
            alternateMacAddress: alternateMacAddress,
            alternateNetworkAdapterType: alternateNetworkAdapterType,
            nicSpeed: nicSpeed,
            bleCapable: bleCapable,
            cellularCarrier: cellularCarrier,
            cellularTechnology: cellularTechnology,
            imei: imei,
            imei2: imei2,
            meid: meid,
            iccid: iccid,
            eid: eid,
            phoneNumber: phoneNumber,
            dataRoamingEnabled: dataRoamingEnabled,
            voiceRoamingEnabled: voiceRoamingEnabled,
            roaming: roaming,
            personalHotspotEnabled: personalHotspotEnabled
        )
        return info.isEmpty ? nil : info
    }

    /// Resolves the Wi-Fi SSID the device is currently joined to.
    ///
    /// Jamf Pro's native inventory schema does not carry the connected
    /// network name for computers or mobile devices (the `network` section
    /// is cellular-only), so the realistic source is a script-based
    /// Extension Attribute. We match an EA whose name reads like an SSID
    /// field, and also probe a few plausible native keys in case a future
    /// Jamf release exposes one.
    private func extractSSID(from payload: [String: Any]) -> String? {
        if let native = extractString(
            using: [
                "general.wifiNetwork", "general.ssid",
                "network.ssid", "network.wifiNetwork",
                "ios.network.ssid", "wifiNetwork", "ssid"
            ],
            from: payload
        ) {
            return native
        }

        let nameTokens = [
            "ssid", "wi-fi network", "wifi network",
            "wireless network", "current network", "airport network"
        ]
        for attribute in extractExtensionAttributes(from: payload) {
            let name = attribute.name.lowercased()
            guard nameTokens.contains(where: { name.contains($0) }) else { continue }
            let value = attribute.value.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.isEmpty == false {
                return value
            }
        }
        return nil
    }

    // MARK: - Extension Attribute Catalogs

    /// Fetches the tenant-wide mobile-device extension-attribute catalog.
    /// Mirrors the Mobile Device Search module's behaviour — same endpoint,
    /// same response shape. Returns sorted by name for stable rendering.
    func fetchMobileDeviceExtensionAttributeCatalog(
        bypassCache: Bool = false
    ) async throws -> [SupportExtensionAttributeDefinition] {
        try await fetchExtensionAttributeCatalog(
            path: "api/v2/mobile-device-extension-attributes",
            cacheKey: "mobile",
            bypassCache: bypassCache
        )
    }

    /// Fetches the tenant-wide computer extension-attribute catalog.
    func fetchComputerExtensionAttributeCatalog(
        bypassCache: Bool = false
    ) async throws -> [SupportExtensionAttributeDefinition] {
        try await fetchExtensionAttributeCatalog(
            path: "api/v2/computer-extension-attributes",
            cacheKey: "computer",
            bypassCache: bypassCache
        )
    }

    private func fetchExtensionAttributeCatalog(
        path: String,
        cacheKey: String,
        bypassCache: Bool
    ) async throws -> [SupportExtensionAttributeDefinition] {
        let data: Data
        if bypassCache == false,
           let cached = await cache.cachedExtensionAttributeCatalog(key: cacheKey)
        {
            data = cached
        } else {
            let queryItems = [
                URLQueryItem(name: "page", value: "0"),
                URLQueryItem(name: "page-size", value: "500"),
                URLQueryItem(name: "sort", value: "name:asc")
            ]
            data = try await apiGateway.request(
                path: path,
                method: .get,
                queryItems: queryItems
            )
            await cache.storeExtensionAttributeCatalog(data, key: cacheKey)
        }

        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any] else {
            return []
        }
        // Jamf wraps the catalog as {"totalCount": N, "results": [...]}.
        let results = (dict["results"] as? [Any])
            ?? (dict["extensionAttributes"] as? [Any])
            ?? []
        return results.compactMap { element -> SupportExtensionAttributeDefinition? in
            guard let entry = element as? [String: Any] else { return nil }
            let idValue: String
            if let intID = entry["id"] as? Int { idValue = String(intID) }
            else if let strID = entry["id"] as? String { idValue = strID }
            else if let number = entry["id"] as? NSNumber { idValue = number.stringValue }
            else { return nil }
            guard let name = extractStringValue(from: entry["name"]) else { return nil }
            let popup = entry["popupMenuChoices"] as? [String]
                ?? entry["popupChoices"] as? [String]
            return SupportExtensionAttributeDefinition(
                attributeID: idValue,
                name: name,
                description: extractStringValue(from: entry["description"]),
                dataType: extractStringValue(from: entry["dataType"]),
                inputType: extractStringValue(from: entry["inputType"]),
                popupChoices: popup,
                category: extractStringValue(from: entry["categoryName"])
                    ?? extractStringValue(from: entry["category"])
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Per-account local password operations

    /// Rotates the password of a specific local admin account managed by
    /// Jamf's Local Admin Password (LAPS) feature, returning the new
    /// Jamf-generated password as a sensitive value.
    ///
    /// This is the per-row password reset surfaced from the User Accounts
    /// frame. Each row in the Admin Accounts / User Accounts / Jamf
    /// Management groups can call into it with its own `username`; the
    /// existing `.rotateLAPSPassword` action keeps its previous behaviour
    /// (resolves and rotates whichever account `resolvePreferredLAPSAccount`
    /// returns as the device's preferred LAPS account).
    ///
    /// Endpoint:
    /// ```
    /// POST /api/v2/local-admin-password/{clientManagementId}/account/{accountName}/rotate
    /// ```
    ///
    /// Returns the new password Jamf generated for the account, which the
    /// view model surfaces via `SupportActionResult.sensitiveValue` (same
    /// one-time-display + copy-to-clipboard treatment as
    /// `viewLAPSAccountPassword` / `viewJamfManagementAccountPassword`).
    ///
    /// Only works for accounts that are registered with Jamf's LAPS
    /// feature. Accounts not enrolled in LAPS return `404` from Jamf;
    /// the view model's graceful-error handling surfaces the not-found
    /// message in the failure popup so the technician knows the rotate
    /// endpoint can't reach that specific account.
    ///
    /// - Parameters:
    ///   - detail: The selected device's detail record (Mac-only).
    ///   - username: The local-account name to rotate (e.g. `"jssmanage"`,
    ///     `"localadmin"`, an admin or user account from the frame).
    /// - Returns: A `SupportActionResult` whose `sensitiveValue` carries
    ///   the new password; `detail` carries a copyable summary.
    /// - Throws: `SupportTechnicianError.unsupportedAction` for mobile
    ///   devices (no local user accounts on iOS / iPadOS / tvOS / etc.);
    ///   `SupportTechnicianError.missingClientManagementID` when the
    ///   device record has no Jamf management identifier; framework
    ///   errors for the underlying request.
    func resetLocalUserPassword(
        for detail: SupportDeviceDetail,
        username: String
    ) async throws -> SupportActionResult {
        guard detail.summary.assetType == .computer else {
            throw SupportTechnicianError.unsupportedAction
        }

        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            throw SupportTechnicianError.unsupportedAction
        }

        let clientManagementID = try resolveClientManagementID(from: detail)
        let encodedAccountName = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? trimmed

        await diagnosticsReporter.report(
            source: "module.support-technician",
            category: "management",
            severity: .info,
            message: "Rotating local-admin password via LAPS per-account endpoint.",
            metadata: [
                "asset_type": detail.summary.assetType.rawValue,
                "inventory_id": detail.summary.inventoryID,
                "client_management_id": clientManagementID,
                "account_name": trimmed,
                "endpoint": "api/v2/local-admin-password/\(clientManagementID)/account/\(encodedAccountName)/rotate"
            ]
        )

        let data = try await apiGateway.request(
            path: "api/v2/local-admin-password/\(clientManagementID)/account/\(encodedAccountName)/rotate",
            method: .post,
            body: nil
        )

        // Jamf's rotate response shape includes the rotated password under
        // a `password` / `newPassword` / `plainTextPassword` key. The
        // existing `extractSecretValue` helper handles all three plus the
        // GUID-keyed wrapper shapes the LAPS view path also tolerates.
        let password = try extractSecretValue(
            from: data,
            preferredKeyFragments: [
                "password",
                "plainTextPassword",
                "newPassword"
            ]
        )

        return SupportActionResult(
            title: "Reset password (\(trimmed))",
            detail: "Rotated the password for the \"\(trimmed)\" account on \(detail.summary.displayName). The new password is shown once — copy it now if you need it. Subsequent views fetch it again from Jamf's LAPS endpoint.",
            sensitiveValue: password
        )
    }

    // MARK: - Command History

    /// Fetches a device's recent MDM command history for the Command
    /// History frame.
    ///
    /// Primary path is `GET /api/v2/mdm/commands?filter=clientManagementId==<uuid>`
    /// (works for both computers and mobile devices, requires "View MDM
    /// command information in Jamf Pro API"). Falls back to the Classic
    /// `JSSResource/computerhistory/id/{id}` or
    /// `JSSResource/mobiledevicehistory/id/{id}` endpoint when the modern
    /// endpoint returns 403 — Classic uses a different XML response shape
    /// but provides the same grouped pending/completed/failed view.
    ///
    /// Returns up to `pageSize` records (default 100). Empty array is a
    /// valid return value (the device has no command history); callers
    /// should not treat that as an error.
    func fetchCommandHistory(
        for detail: SupportDeviceDetail,
        pageSize: Int = 100
    ) async throws -> SupportMDMCommandHistory {
        // Modern endpoint first.
        let commandManagementID = [
            detail.summary.clientManagementID,
            detail.summary.managementID
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.isEmpty == false }
        if let managementID = commandManagementID,
           managementID.isEmpty == false
        {
            guard let filter = Self.commandHistoryFilter(for: managementID) else {
                throw JamfFrameworkError.authenticationFailed
            }
            do {
                let data = try await apiGateway.request(
                    path: "api/v2/mdm/commands",
                    method: .get,
                    queryItems: [
                        URLQueryItem(name: "page", value: "0"),
                        URLQueryItem(name: "page-size", value: String(pageSize)),
                        URLQueryItem(name: "sort", value: "dateSent:desc"),
                        URLQueryItem(name: "filter", value: filter)
                    ]
                )
                let records = Self.parseModernMDMCommandHistory(from: data)

                // Persist the raw payload + a flat shape summary so the
                // exact Jamf response can be inspected after a test send.
                // The colored bucket boxes reading zero against a non-empty
                // response is a parse/bucket fault, and these two artifacts
                // pinpoint it without another debugging round.
                Self.dumpPayloadForDiagnostics(
                    rawJSON: String(data: data, encoding: .utf8) ?? "<non-utf8>",
                    deviceID: managementID,
                    kind: "command-history"
                )
                let shape = Self.commandHistoryShapeSummary(data: data, records: records)
                await diagnosticsReporter.report(
                    source: "module.support-technician",
                    category: "command-history",
                    severity: records.isEmpty ? .warning : .info,
                    message: "Parsed modern MDM command history.",
                    metadata: shape
                )

                return SupportMDMCommandHistory(
                    records: records,
                    fetchedAt: Date(),
                    source: .modern
                )
            } catch {
                // Fall through to Classic path if the modern endpoint
                // returned 403 (privilege gap) or 400 (filter rejected on
                // older tenants).
                if isNetworkFailure(error, statusCode: 403) == false,
                   isNetworkFailure(error, statusCode: 400) == false
                {
                    throw error
                }
            }
        }

        // Classic fallback — by inventory ID, returns grouped history.
        let classicPath = detail.summary.assetType == .computer
            ? "JSSResource/computerhistory/id/\(detail.summary.inventoryID)"
            : "JSSResource/mobiledevicehistory/id/\(detail.summary.inventoryID)"
        let data = try await apiGateway.request(
            path: classicPath,
            method: .get,
            queryItems: [],
            body: nil
        )
        let records = Self.parseClassicMDMCommandHistory(from: data)
        return SupportMDMCommandHistory(
            records: records,
            fetchedAt: Date(),
            source: .classic
        )
    }

    nonisolated static func commandHistoryFilter(for managementID: String) -> String? {
        let trimmed = managementID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }
        let escaped = JamfRSQLFilter.escapeSingleQuoted(trimmed)
        return "clientManagementId=='\(escaped)'"
    }

    /// Parses the response from `GET /api/v2/mdm/commands`.
    ///
    /// The response shape varies across Jamf Pro versions, so this parser
    /// is deliberately permissive:
    /// - Top level may be a bare JSON array `[ … ]` or a paginated object
    ///   `{"results":[ … ]}` / `{"commands":[ … ]}`. The previous version
    ///   only handled the object form and returned `[]` for a top-level
    ///   array — which silently dropped every record (the bucket boxes
    ///   then read zero even though the device had command history).
    /// - Each command's `commandType` and `status` may live flat on the
    ///   entry or nested inside a `command` object. Status in particular
    ///   is often nested; reading only the flat `status` key made every
    ///   record resolve to `(unknown)` → `.other`, so no colored bucket
    ///   ever incremented. Fields are now resolved against both the flat
    ///   entry and the nested `command` object.
    nonisolated static func parseModernMDMCommandHistory(from data: Data) -> [SupportMDMCommandRecord] {
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }
        return modernCommandResultsArray(from: object).compactMap { element in
            guard let entry = element as? [String: Any] else { return nil }
            let nested = entry["command"] as? [String: Any]

            let uuid = commandHistoryField(["uuid", "id", "commandUuid"], entry, nested)
                ?? UUID().uuidString
            // `command` can be a bare string ("DeviceInformation") or an
            // object carrying `commandType`/`name`; check both forms.
            let command = commandHistoryField(["commandType", "name"], entry, nested)
                ?? (entry["command"] as? String)
                ?? commandHistoryStringValue(from: entry["command"])
                ?? "(unknown)"
            let status = commandHistoryField(
                ["status", "commandStatus", "state", "commandState"],
                entry,
                nested
            ) ?? "(unknown)"
            let dateSent = commandHistoryField(
                ["dateSent", "date_time_issued", "issued", "issuedAt"],
                entry,
                nested
            )
            let dateCompleted = commandHistoryField(
                ["dateCompleted", "date_time_completed", "completed", "acknowledgedAt"],
                entry,
                nested
            )

            var errorReasons: [String] = []
            for source in [entry, nested].compactMap({ $0 }) {
                if let reasons = source["errorReasons"] as? [String] {
                    errorReasons = reasons
                    break
                } else if let reasons = source["errorReasons"] as? [Any] {
                    errorReasons = reasons.compactMap { commandHistoryStringValue(from: $0) }
                    break
                } else if let reason = commandHistoryStringValue(from: source["errorReason"])
                    ?? commandHistoryStringValue(from: source["failureReason"])
                {
                    errorReasons = [reason]
                    break
                }
            }

            return SupportMDMCommandRecord(
                uuid: uuid,
                commandType: command,
                status: status,
                dateSent: dateSent,
                dateCompleted: dateCompleted,
                errorReasons: errorReasons,
                source: .modern
            )
        }
    }

    /// Locates the array of command entries in a modern-endpoint response,
    /// tolerating a top-level array, the paginated `results`/`commands`
    /// object, or any other object whose first array value holds objects.
    nonisolated static func modernCommandResultsArray(from object: Any) -> [Any] {
        if let array = object as? [Any] { return array }
        guard let dict = object as? [String: Any] else { return [] }
        if let results = dict["results"] as? [Any] { return results }
        if let commands = dict["commands"] as? [Any] { return commands }
        for value in dict.values {
            if let array = value as? [Any], array.contains(where: { $0 is [String: Any] }) {
                return array
            }
        }
        return []
    }

    /// Returns the first non-empty string value for `keys`, checking the
    /// flat entry first and then a nested `command` object. Lets the parser
    /// tolerate both flat (`entry.status`) and nested (`entry.command.status`)
    /// field placement without duplicating the fallback chain per field.
    private nonisolated static func commandHistoryField(
        _ keys: [String],
        _ entry: [String: Any],
        _ nested: [String: Any]?
    ) -> String? {
        for key in keys {
            if let value = commandHistoryStringValue(from: entry[key]) {
                return value
            }
        }
        if let nested {
            for key in keys {
                if let value = commandHistoryStringValue(from: nested[key]) {
                    return value
                }
            }
        }
        return nil
    }

    /// Builds a flat, log-safe summary of a modern command-history response
    /// and the records the parser produced from it. Captured in the
    /// `command-history` diagnostics category so a single test send reveals
    /// the exact response shape (top-level kind, keys, where `commandType`
    /// and the status field actually live) and whether every record landed
    /// in a colored bucket — instead of debugging blind from byte counts.
    nonisolated static func commandHistoryShapeSummary(
        data: Data,
        records: [SupportMDMCommandRecord]
    ) -> [String: String] {
        var summary: [String: String] = [
            "byte_count": String(data.count),
            "parsed_count": String(records.count)
        ]

        if let object = try? JSONSerialization.jsonObject(with: data) {
            if let array = object as? [Any] {
                summary["top_level"] = "array"
                summary["top_level_count"] = String(array.count)
            } else if let dict = object as? [String: Any] {
                summary["top_level"] = "object"
                summary["top_keys"] = dict.keys.sorted().joined(separator: ",")
            } else {
                summary["top_level"] = "scalar"
            }
            let results = modernCommandResultsArray(from: object)
            summary["results_count"] = String(results.count)
            if let first = results.first as? [String: Any] {
                summary["first_keys"] = first.keys.sorted().joined(separator: ",")
                if let nested = first["command"] as? [String: Any] {
                    summary["first_command_keys"] = nested.keys.sorted().joined(separator: ",")
                }
            }
        } else {
            summary["top_level"] = "non-json"
        }

        if let first = records.first {
            summary["first_status"] = first.status
            summary["first_command_type"] = first.commandType
            summary["first_bucket"] = first.bucket.rawValue
        }

        // Bucket distribution — the headline signal. If history is present
        // (parsed_count > 0) but every bucket is zero, the status field is
        // landing somewhere the parser/bucketing doesn't read.
        let order: [SupportMDMCommandRecord.Bucket] = [.pending, .completed, .failed, .notNow, .other]
        let counts = records.reduce(into: [SupportMDMCommandRecord.Bucket: Int]()) { acc, record in
            acc[record.bucket, default: 0] += 1
        }
        summary["buckets"] = order
            .map { "\($0.rawValue)=\(counts[$0] ?? 0)" }
            .joined(separator: " ")

        return summary
    }

    /// Parses the Classic API history response (returned as XML on most
    /// Jamf Pro tenants but the gateway transparently converts to JSON
    /// when `Accept: application/json` is on the request).
    nonisolated static func parseClassicMDMCommandHistory(from data: Data) -> [SupportMDMCommandRecord] {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any] else {
            return []
        }
        // The Classic shape wraps everything in `computer_history` or
        // `mobile_device_history`. Inside there's `commands.completed`,
        // `commands.pending`, `commands.failed`.
        let history = (dict["computer_history"] as? [String: Any])
            ?? (dict["mobile_device_history"] as? [String: Any])
            ?? dict
        let commands = history["commands"] as? [String: Any] ?? [:]

        func extract(_ key: String, status: String) -> [SupportMDMCommandRecord] {
            let array = commands[key] as? [Any] ?? []
            return array.compactMap { element in
                guard let entry = element as? [String: Any] else { return nil }
                let commandName = commandHistoryStringValue(from: entry["name"])
                    ?? commandHistoryStringValue(from: entry["command"])
                    ?? "(unknown)"
                let uuid = commandHistoryStringValue(from: entry["uuid"])
                    ?? commandHistoryStringValue(from: entry["id"])
                    ?? UUID().uuidString
                let dateSent = commandHistoryStringValue(from: entry["date_time_issued"])
                    ?? commandHistoryStringValue(from: entry["issued"])
                let dateCompleted = commandHistoryStringValue(from: entry["date_time_completed"])
                    ?? commandHistoryStringValue(from: entry["completed"])
                let errorReasons: [String]
                if let reason = commandHistoryStringValue(from: entry["failed_reason"]), reason.isEmpty == false {
                    errorReasons = [reason]
                } else {
                    errorReasons = []
                }
                return SupportMDMCommandRecord(
                    uuid: uuid,
                    commandType: commandName,
                    status: status,
                    dateSent: dateSent,
                    dateCompleted: dateCompleted,
                    errorReasons: errorReasons,
                    source: .classic
                )
            }
        }

        return extract("completed", status: "Completed")
            + extract("pending", status: "Pending")
            + extract("failed", status: "Failed")
    }

    private nonisolated static func commandHistoryStringValue(from value: Any?) -> String? {
        switch value {
        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let bool as Bool:
            return bool ? "true" : "false"
        case let number as NSNumber:
            return number.stringValue
        case let dict as [String: Any]:
            for key in ["displayName", "name", "value", "id", "commandType"] {
                if let value = commandHistoryStringValue(from: dict[key]) {
                    return value
                }
            }
            return nil
        default:
            return nil
        }
    }

    /// Extracts device group memberships from any of the known Jamf payload
    /// shapes: `groupMemberships[]` (computer), `mobileDeviceGroups[]`
    /// (mobile), `general.groupMemberships[]`, or recursive deep-find on
    /// `groupMemberships`. Each element is parsed for id/name/smart-group
    /// flag with multiple key variants.
    private func extractDeviceGroups(
        from payload: [String: Any]
    ) -> [SupportDeviceGroup] {
        // Real iPad payload uses top-level `groups[]` with
        // `{groupId, groupName, smart, groupDescription}` entries.
        // Computers (v1 classic) use `groupMemberships[]`. Try them all.
        let candidatePaths: [String] = [
            "groups",
            "groupMemberships",
            "mobileDeviceGroups",
            "general.groupMemberships",
            "general.mobileDeviceGroups",
            "deviceGroups"
        ]

        for path in candidatePaths {
            guard let resolved = resolveValue(atPath: path, in: payload) else {
                continue
            }
            if let array = resolved as? [Any] {
                let groups = array.compactMap(parseDeviceGroup(from:))
                if groups.isEmpty == false {
                    return groups
                }
            }
        }
        return []
    }

    private func parseDeviceGroup(from element: Any) -> SupportDeviceGroup? {
        if let stringName = element as? String, stringName.isEmpty == false {
            return SupportDeviceGroup(groupID: "", name: stringName, isSmart: nil)
        }
        guard let dict = element as? [String: Any] else { return nil }
        let groupID = extractStringValue(from: dict["id"])
            ?? extractStringValue(from: dict["groupId"])
            ?? ""
        guard let name = extractStringValue(from: dict["groupName"])
            ?? extractStringValue(from: dict["name"])
            ?? extractStringValue(from: dict["displayName"])
        else {
            return nil
        }
        // v1 iPad payload uses `smart: bool`; v2 uses `smartGroup: bool` or
        // `isSmart: bool`. Cover all three.
        let smart: Bool?
        if let bool = dict["smart"] as? Bool { smart = bool }
        else if let bool = dict["smartGroup"] as? Bool { smart = bool }
        else if let bool = dict["isSmart"] as? Bool { smart = bool }
        else if let n = dict["smart"] as? NSNumber { smart = n.boolValue }
        else if let n = dict["smartGroup"] as? NSNumber { smart = n.boolValue }
        else { smart = nil }
        return SupportDeviceGroup(groupID: groupID, name: name, isSmart: smart)
    }

    /// Extracts configuration profiles assigned to the device from the
    /// `configurationProfiles[]` section (computers & mobile). Falls back
    /// through several variant container names so any tenant's shape is
    /// covered.
    private func extractConfigurationProfiles(
        from payload: [String: Any]
    ) -> [SupportDeviceProfile] {
        // Mobile classic stores profiles under the platform-typed key
        // (`ios.configurationProfiles`, etc) plus a parallel
        // `ios.provisioningProfiles` array. Computers and v2 use the
        // top-level `configurationProfiles[]`.
        let candidatePaths: [String] = [
            "configurationProfiles",
            "configuration_profiles",
            "profiles",
            "userProfiles",
            "user_profiles",
            "ios.configurationProfiles",
            "tvos.configurationProfiles",
            "visionos.configurationProfiles",
            "watchos.configurationProfiles",
            "ios.provisioningProfiles",
            "tvos.provisioningProfiles",
            "visionos.provisioningProfiles",
            "watchos.provisioningProfiles"
        ]
        var collected: [SupportDeviceProfile] = []
        for path in candidatePaths {
            guard let resolved = resolveValue(atPath: path, in: payload) else { continue }
            guard let array = resolved as? [Any] else { continue }
            for element in array {
                if let parsed = parseDeviceProfile(from: element) {
                    collected.append(parsed)
                }
            }
        }
        // Dedupe by id+name
        var seen = Set<String>()
        return collected.filter { profile in
            let key = "\(profile.profileID):\(profile.name)"
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }

    private func parseDeviceProfile(from element: Any) -> SupportDeviceProfile? {
        guard let dict = element as? [String: Any] else { return nil }
        let profileID = extractStringValue(from: dict["id"])
            ?? extractStringValue(from: dict["profileId"])
            ?? extractStringValue(from: dict["profileIdentifier"])
            ?? ""
        guard let name = extractStringValue(from: dict["displayName"])
            ?? extractStringValue(from: dict["name"])
            ?? extractStringValue(from: dict["profileName"])
        else {
            return nil
        }
        let identifier = extractStringValue(from: dict["uuid"])
            ?? extractStringValue(from: dict["profileIdentifier"])
            ?? extractStringValue(from: dict["identifier"])
        let scope = extractStringValue(from: dict["scope"])
            ?? extractStringValue(from: dict["target"])
        return SupportDeviceProfile(
            profileID: profileID,
            name: name,
            identifier: identifier,
            scope: scope
        )
    }

    // MARK: - Tenant-wide Policies

    /// Lists every policy in the tenant via Classic API
    /// `GET /JSSResource/policies`. Returns a list of `{id, name}` records
    /// from `<policies><policy><id>…</id><name>…</name></policy>…</policies>`.
    /// Used by the new Policy frame to give technicians a scrollable index
    /// of policies regardless of which device they're viewing.
    func fetchAllPolicies(bypassCache: Bool = false) async throws -> [SupportPolicy] {
        // Cache-first: tenant policies don't change often and fetching
        // them from /JSSResource/policies on every detail-view visit is
        // the worst offender against "don't rage-bang the server".
        let data: Data
        if bypassCache == false,
           let cachedData = await cache.cachedPolicies()
        {
            data = cachedData
        } else {
            let fetched = try await apiGateway.request(
                path: "JSSResource/policies",
                method: .get,
                queryItems: [],
                body: nil
            )
            data = fetched
            await cache.storePolicies(fetched)
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }
        // Classic returns either { "policies": [ {id, name} ] }, or a
        // nested wrapper depending on Accept header. Walk both shapes.
        func extractArray(from any: Any) -> [Any]? {
            if let dict = any as? [String: Any] {
                if let array = dict["policies"] as? [Any] { return array }
                for value in dict.values {
                    if let array = value as? [Any] { return array }
                }
            }
            if let array = any as? [Any] { return array }
            return nil
        }
        guard let array = extractArray(from: object) else { return [] }
        return array.compactMap { element -> SupportPolicy? in
            guard let dict = element as? [String: Any] else { return nil }
            let idValue = dict["id"]
            let policyID: String
            if let number = idValue as? NSNumber { policyID = number.stringValue }
            else if let string = idValue as? String { policyID = string }
            else { return nil }
            guard let name = extractStringValue(from: dict["name"]) else { return nil }
            return SupportPolicy(
                policyID: policyID,
                name: name,
                category: extractStringValue(from: dict["category"]),
                enabled: dict["enabled"] as? Bool,
                frequency: extractStringValue(from: dict["frequency"])
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Writes the most recent payload to the sandboxed Documents folder so
    /// the operator can inspect the exact shape Jamf returned. Filename is
    /// `last-<kind>-<id>.json` — per-device so successive loads don't
    /// clobber each other (handy when comparing iPad vs Mac responses, or
    /// the detail payload vs the command-history payload for one device).
    nonisolated static func dumpPayloadForDiagnostics(
        rawJSON: String,
        deviceID: String,
        kind: String = "detail-payload"
    ) {
        guard let documents = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else { return }
        let folder = documents.appendingPathComponent("ForsettiDiagnostics", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let safeID = deviceID.replacingOccurrences(of: "/", with: "_")
        let url = folder.appendingPathComponent("last-\(kind)-\(safeID).json")
        try? rawJSON.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Boolean extractor mirroring `extractString` and `extractInt`. Recognises
    /// `Bool`, `NSNumber` (0/1), and the literal strings `"true"`/`"false"`.
    private func extractBool(
        using paths: [String],
        from dictionary: [String: Any]
    ) -> Bool? {
        for path in paths {
            guard let resolved = resolveValue(atPath: path, in: dictionary) else {
                continue
            }
            if let boolValue = resolved as? Bool {
                return boolValue
            }
            if let number = resolved as? NSNumber {
                return number.boolValue
            }
            if let stringValue = resolved as? String {
                let lower = stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if lower == "true" || lower == "yes" || lower == "1" { return true }
                if lower == "false" || lower == "no" || lower == "0" { return false }
            }
        }
        return nil
    }

    /// Companion to `extractString(using:from:)` for integer fields. Walks
    /// the candidate paths in order; the first one that resolves to an
    /// `NSNumber` or a parseable string wins.
    private func extractInt(
        using paths: [String],
        from dictionary: [String: Any]
    ) -> Int? {
        for path in paths {
            guard let resolved = resolveValue(atPath: path, in: dictionary) else {
                continue
            }
            if let intValue = resolved as? Int {
                return intValue
            }
            if let number = resolved as? NSNumber {
                return number.intValue
            }
            if let stringValue = resolved as? String, let parsed = Int(stringValue) {
                return parsed
            }
            if let doubleValue = resolved as? Double {
                return Int(doubleValue)
            }
        }
        return nil
    }

    private func positiveInt(_ value: Int?) -> Int? {
        guard let value, value > 0 else { return nil }
        return value
    }

    private func encryptionStateIsEnabled(_ state: String?) -> Bool? {
        guard let state else { return nil }
        let normalized = state.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalized.isEmpty == false else { return nil }
        if normalized.contains("unencrypted") || normalized.contains("not encrypted") {
            return false
        }
        if normalized.contains("encrypted") || normalized.contains("boot_encrypted") {
            return true
        }
        if normalized == "enabled" || normalized == "true" || normalized == "valid" {
            return true
        }
        if normalized == "disabled" || normalized == "false" || normalized == "invalid" {
            return false
        }
        return nil
    }

    private func extractInt(from value: Any?) -> Int? {
        switch value {
        case let intValue as Int:
            return intValue
        case let number as NSNumber:
            return number.intValue
        case let doubleValue as Double:
            return Int(doubleValue)
        case let stringValue as String:
            let normalized = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                .split(separator: ".")
                .first
                .map(String.init) ?? ""
            return Int(normalized)
        default:
            return nil
        }
    }

    /// Converts a camelCase or snake_case key into a human-readable section title.
    private func sectionTitle(for value: String) -> String {
        value
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { word in
                let text = String(word)
                return text.prefix(1).uppercased() + text.dropFirst()
            }
            .joined(separator: " ")
    }

    /// Converts a JSON value to a display string, truncating to 280 characters.
    private func displayString(for value: Any?) -> String? {
        guard let value else {
            return nil
        }

        if let stringValue = extractStringValue(from: value) {
            if stringValue.count > 280 {
                let endIndex = stringValue.index(stringValue.startIndex, offsetBy: 280)
                return "\(stringValue[..<endIndex])..."
            }

            return stringValue
        }

        return nil
    }

    // MARK: - Diagnostics

    /// Flattens a nested JSON dictionary into dot-path keyed string values for
    /// efficient diagnostic lookups.
    private func flattenForDiagnostics(from dictionary: [String: Any]) -> [String: String] {
        var output: [String: String] = [:]
        flatten(value: dictionary, currentPath: nil, output: &output)
        return output
    }

    /// Recursively flattens a JSON value into dot-path keyed entries.
    /// Arrays are represented by index notation (e.g. "items[0].name") and capped at 5 entries.
    private func flatten(
        value: Any,
        currentPath: String?,
        output: inout [String: String]
    ) {
        if let dictionary = value as? [String: Any] {
            for (key, nestedValue) in dictionary {
                let nextPath = currentPath.map { "\($0).\(key)" } ?? key
                flatten(value: nestedValue, currentPath: nextPath, output: &output)
            }
            return
        }

        if let array = value as? [Any] {
            if let path = currentPath {
                output[path + ".count"] = String(array.count)
            }

            for (index, nestedValue) in array.prefix(5).enumerated() {
                let nextPath = currentPath.map { "\($0)[\(index)]" } ?? "[\(index)]"
                flatten(value: nestedValue, currentPath: nextPath, output: &output)
            }
            return
        }

        guard let currentPath,
              let resolved = extractStringValue(from: value)
        else {
            return
        }

        output[currentPath] = resolved
    }

    /// Extracts application names from the raw inventory payload by probing
    /// multiple known key paths for application data.
    private func extractApplicationNames(from dictionary: [String: Any]) -> [String] {
        // v1 mobile classic puts installed apps under `ios.applications` /
        // `tvos.applications` etc. (one row per app with `name`,
        // `identifier`, `shortVersion`, `version`). v2 / computers use
        // the flat `applications` array.
        let applicationPathCandidates = [
            "applications",
            "applicationList",
            "general.applications",
            "softwareUpdates",
            "licensedSoftware",
            "software",
            "ios.applications",
            "tvos.applications",
            "visionos.applications",
            "watchos.applications"
        ]

        var names = Set<String>()

        for path in applicationPathCandidates {
            guard let value = resolveValue(atPath: path, in: dictionary) else {
                continue
            }

            let dictionaries = dictionaryArray(from: value)
            for dictionary in dictionaries {
                if let name =
                    extractString(using: ["name", "displayName", "bundleId", "identifier"], from: dictionary)
                {
                    names.insert(name)
                }
            }

            if let values = value as? [Any] {
                for element in values {
                    if let scalar = extractStringValue(from: element) {
                        names.insert(scalar)
                    }
                }
            }
        }

        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Builds health diagnostic items from the search result and flattened inventory values.
    ///
    /// Checks include management ID presence, user assignment, inventory age,
    /// FileVault status (computers), supervision state (mobile), and application count.
    private func buildDiagnostics(
        for result: SupportSearchResult,
        flattenedValues: [String: String],
        applications: [String]
    ) -> [SupportDiagnosticItem] {
        var diagnostics: [SupportDiagnosticItem] = []

        // Management ID check
        if result.managementID == nil {
            diagnostics.append(
                SupportDiagnosticItem(
                    title: "Management Identifier",
                    value: "Missing",
                    severity: .critical
                )
            )
        } else {
            diagnostics.append(
                SupportDiagnosticItem(
                    title: "Management Identifier",
                    value: "Present",
                    severity: .info
                )
            )
        }

        // User assignment check
        if let username = result.username,
           username.isEmpty == false
        {
            diagnostics.append(
                SupportDiagnosticItem(
                    title: "Assigned User",
                    value: username,
                    severity: .info
                )
            )
        } else {
            diagnostics.append(
                SupportDiagnosticItem(
                    title: "Assigned User",
                    value: "Not assigned",
                    severity: .warning
                )
            )
        }

        // Inventory age check -- warn if older than 14 days
        if let inventoryDate = resolveInventoryDate(from: result, flattenedValues: flattenedValues) {
            let ageInDays = Int(Date().timeIntervalSince(inventoryDate) / 86_400)
            let severity: SupportDiagnosticSeverity = ageInDays > 14 ? .warning : .info
            diagnostics.append(
                SupportDiagnosticItem(
                    title: "Inventory Age",
                    value: "\(max(ageInDays, 0)) day(s)",
                    severity: severity
                )
            )
        }

        // Device-type-specific diagnostics
        switch result.assetType {
        case .computer:
            if let fileVaultValue =
                flattenedValues["diskEncryption.fileVault2Enabled"] ??
                flattenedValues["general.fileVault2Enabled"]
            {
                let isEnabled = boolValue(from: fileVaultValue)
                diagnostics.append(
                    SupportDiagnosticItem(
                        title: "FileVault",
                        value: isEnabled ? "Enabled" : "Disabled",
                        severity: isEnabled ? .info : .warning
                    )
                )
            }

        case .mobileDevice:
            if let supervisedValue =
                flattenedValues["general.supervised"] ??
                flattenedValues["supervised"]
            {
                let isSupervised = boolValue(from: supervisedValue)
                diagnostics.append(
                    SupportDiagnosticItem(
                        title: "Supervision",
                        value: isSupervised ? "Supervised" : "Not supervised",
                        severity: isSupervised ? .info : .warning
                    )
                )
            }
        }

        // Application count
        diagnostics.append(
            SupportDiagnosticItem(
                title: "Discovered Applications",
                value: "\(applications.count)",
                severity: applications.isEmpty ? .warning : .info
            )
        )

        return diagnostics
    }

    // MARK: - Date Parsing

    /// Resolves the inventory date from the search result or flattened values,
    /// trying multiple known key paths.
    private func resolveInventoryDate(
        from result: SupportSearchResult,
        flattenedValues: [String: String]
    ) -> Date? {
        let candidates = [
            result.lastInventoryUpdate,
            flattenedValues["general.lastInventoryUpdateDate"],
            flattenedValues["general.lastInventoryUpdate"],
            flattenedValues["general.reportDate"],
            flattenedValues["general.lastContactTime"],
            flattenedValues["lastInventoryUpdateDate"],
            flattenedValues["reportDate"],
            flattenedValues["lastContactTime"]
        ]

        for candidate in candidates {
            guard let candidate else {
                continue
            }

            if let parsed = parseDate(candidate) {
                return parsed
            }
        }

        return nil
    }

    /// Parses a date string, trying ISO 8601 with fractional seconds, ISO 8601 standard,
    /// then Unix timestamp (auto-detecting milliseconds vs. seconds).
    private func parseDate(_ value: String) -> Date? {
        if let date = iso8601FractionalFormatter.date(from: value) {
            return date
        }

        if let date = iso8601Formatter.date(from: value) {
            return date
        }

        // Try Unix timestamp -- auto-detect milliseconds vs seconds
        if let unixSeconds = Double(value) {
            if unixSeconds > 100_000_000_000 {
                return Date(timeIntervalSince1970: unixSeconds / 1000)
            }

            return Date(timeIntervalSince1970: unixSeconds)
        }

        return nil
    }

    /// Converts a string to a boolean, recognizing common truthy values.
    private func boolValue(from value: String) -> Bool {
        switch value.lowercased() {
        case "true", "yes", "1", "managed", "enabled":
            return true
        default:
            return false
        }
    }

    // MARK: - Deduplication and Sorting

    /// Removes duplicate search results by composite asset-type + inventory-ID key.
    private func dedupe(_ results: [SupportSearchResult]) -> [SupportSearchResult] {
        var seen = Set<String>()
        var deduped: [SupportSearchResult] = []

        for result in results {
            let dedupeKey = "\(result.assetType.rawValue)-\(result.inventoryID)"
            guard seen.insert(dedupeKey).inserted else {
                continue
            }

            deduped.append(result)
        }

        return deduped
    }

    /// Sorts search results by asset type first, then display name, then serial number.
    private func sortByAssetAndName(lhs: SupportSearchResult, rhs: SupportSearchResult) -> Bool {
        if lhs.assetType != rhs.assetType {
            return lhs.assetType.rawValue.localizedCaseInsensitiveCompare(rhs.assetType.rawValue) == .orderedAscending
        }

        let nameComparison = lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName)
        if nameComparison != .orderedSame {
            return nameComparison == .orderedAscending
        }

        return lhs.serialNumber.localizedCaseInsensitiveCompare(rhs.serialNumber) == .orderedAscending
    }

    // MARK: - RSQL Filter Building

    /// Builds an RSQL filter for computer inventory search with the given escaped query.
    /// Uses wildcard wrapping when `useWildcard` is true for substring matching.
    private func buildComputerFilter(withEscapedQuery query: String, useWildcard: Bool) -> String {
        let value = useWildcard ? "*\(query)*" : query
        let conditions = [
            "general.name==\"\(value)\"",
            "hardware.serialNumber==\"\(value)\"",
            "userAndLocation.username==\"\(value)\"",
            "userAndLocation.email==\"\(value)\""
        ]

        return "(\(conditions.joined(separator: ",")))"
    }

    /// Escapes backslashes and double quotes for RSQL double-quoted strings.
    private func escapeRSQLString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Escapes backslashes and single quotes for RSQL single-quoted strings.
    private func escapeSingleQuoteRSQLString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
    }

    // MARK: - Error Classification

    /// Returns `true` if the error indicates this computer endpoint version
    /// is not supported (400/403/404).
    ///
    /// Thin wrapper around the shared `Error.matchesJamf(status:)` helper
    /// so the classification rules for "try next version" live in one
    /// place (`JamfFrameworkError+Matching.swift`) rather than drifting
    /// across modules.
    private func shouldTryNextComputerEndpoint(after error: any Error) -> Bool {
        error.matchesJamf(status: 400, 403, 404)
    }

    /// Returns `true` if the error indicates this API path is not available
    /// at this version (400/403/404/405). Used by `requestWithPathFallback`
    /// to advance to the next candidate path.
    private func shouldTryNextPath(after error: any Error) -> Bool {
        error.matchesJamf(status: 400, 403, 404, 405)
    }

    /// Returns `true` if the error is a 400 that specifically mentions
    /// "section" parameters, indicating the section encoding mode should
    /// be changed. Kept as a dedicated helper because it inspects the
    /// response message body (not just the status code) — the shared
    /// classification extension can't do that.
    private func isSectionParameterError(_ error: any Error) -> Bool {
        guard case let JamfFrameworkError.networkFailure(statusCode, message) = error else {
            return false
        }

        guard statusCode == 400 else {
            return false
        }

        let normalized = message.lowercased()
        if normalized.contains("section") == false {
            return false
        }

        return normalized.contains("invalid") ||
            normalized.contains("java.util.set") ||
            normalized.contains("request parameter")
    }

    /// Returns `true` if the error is a network failure with the specified
    /// status code. Preserved because some call sites (e.g., MDM command
    /// pass-1 400 retry, wildcard-vs-exact filter fallback) care about a
    /// *specific* code rather than the "endpoint unavailable" set.
    private func isNetworkFailure(_ error: any Error, statusCode: Int) -> Bool {
        error.matchesJamf(status: statusCode)
    }

    /// Whether an error indicates the endpoint is unavailable to this
    /// caller — 403/404/405. Thin wrapper around the shared
    /// `Error.isJamfEndpointUnavailable` helper.
    private func isEndpointUnavailable(_ error: any Error) -> Bool {
        error.isJamfEndpointUnavailable
    }
}

/// Support Technician-local copy of the Mobile Device Search PreStage
/// extraction behavior. The modules do not call each other, so this parser
/// intentionally duplicates the response-shape handling needed for mobile
/// detail payloads such as `general.enrollmentMethodPrestage`.
nonisolated enum SupportTechnicianPrestageParser {
    private static let enrolledStatusLabel = "Enrolled"
    private static let notEnrolledStatusLabel = "Not Enrolled"

    static func displayValue(from payload: [String: Any]) -> String? {
        // `enrollmentMethod` is the field Jamf inventory actually populates
        // with the device's PreStage, in two shapes the recursive scan below
        // doesn't reach (the key isn't named "*prestage*"). Resolve it first.
        if let enrollmentMethodName = enrollmentMethodPrestageName(from: payload) {
            return enrollmentMethodName
        }

        let prestage = extractPrestageNameAndID(from: payload)
        let status = extractPrestageEnrollmentStatus(from: payload)

        return prestageDisplayValue(
            status: status,
            profileName: prestage.name,
            profileID: prestage.id
        )
    }

    /// Resolves the PreStage assignment from the device's `enrollmentMethod`.
    /// Two real Jamf inventory shapes:
    ///   * Computers — `general.enrollmentMethod` is an object:
    ///     `{ objectType: "PreStage enrollment", objectName: "<name>" }`.
    ///     `objectName` is only a PreStage when `objectType` says so; other
    ///     methods (User-Initiated, Enrollment Invitation, …) put a different
    ///     label there, so the `objectType` gate prevents mislabeling.
    ///   * Mobile — top-level `enrollmentMethod` is a string:
    ///     `"PreStage enrollment: <name> (<id>)"`.
    /// Returns the bare PreStage name, or nil when not PreStage-enrolled.
    static func enrollmentMethodPrestageName(from payload: [String: Any]) -> String? {
        let method = (payload["general"] as? [String: Any])?["enrollmentMethod"]
            ?? payload["enrollmentMethod"]

        if let object = method as? [String: Any] {
            let type = (extractString(from: object["objectType"]) ?? "").lowercased()
            guard type.contains("prestage") else { return nil }
            return extractString(from: object["objectName"])
        }

        if let raw = extractString(from: method) {
            return prestageName(fromEnrollmentMethodString: raw)
        }
        return nil
    }

    /// Parses `"PreStage enrollment: <name> (<id>)"` down to `<name>`,
    /// tolerating PreStage names that themselves contain "PreStage" or
    /// parentheses. Returns nil for non-PreStage enrollment-method strings.
    static func prestageName(fromEnrollmentMethodString raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.lowercased().contains("prestage") else { return nil }

        var name = trimmed
        if let colon = name.firstIndex(of: ":") {
            name = String(name[name.index(after: colon)...])
        }
        name = name.trimmingCharacters(in: .whitespaces)

        // Strip a trailing " (<id>)" suffix when the parenthesized text is
        // purely numeric — Jamf appends the PreStage ID this way.
        if name.hasSuffix(")"), let open = name.lastIndex(of: "(") {
            let inside = name[name.index(after: open)..<name.index(before: name.endIndex)]
            if inside.isEmpty == false, inside.allSatisfy(\.isNumber) {
                name = String(name[..<open]).trimmingCharacters(in: .whitespaces)
            }
        }
        return name.isEmpty ? nil : name
    }

    private static func prestageDisplayValue(
        status: String?,
        profileName: String?,
        profileID: String?
    ) -> String? {
        let normalizedStatus = normalizePrestageStatus(status)
        let normalizedName = normalizeComponent(profileName)
        let normalizedID = normalizeComponent(profileID)
        let profileDisplay: String?

        switch (normalizedName, normalizedID) {
        case let (name?, id?):
            profileDisplay = "\(name) (ID: \(id))"
        case let (name?, nil):
            profileDisplay = name
        case let (nil, id?):
            profileDisplay = id
        case (nil, nil):
            profileDisplay = nil
        }

        if let normalizedStatus, let profileDisplay {
            return "\(normalizedStatus) - \(profileDisplay)"
        }
        if let profileDisplay {
            return profileDisplay
        }
        return normalizedStatus
    }

    private static func extractPrestageNameAndID(from value: Any, inPrestageContext: Bool = false) -> (name: String?, id: String?) {
        if let dictionary = value as? [String: Any] {
            var foundName =
                extractString(from: dictionary["prestageEnrollmentProfileName"]) ??
                extractString(from: dictionary["prestageName"])
            var foundID =
                extractString(from: dictionary["prestageEnrollmentProfileId"]) ??
                extractString(from: dictionary["prestageId"])

            if inPrestageContext {
                foundName = foundName ??
                    extractString(from: dictionary["profileName"]) ??
                    extractString(from: dictionary["displayName"]) ??
                    extractString(from: dictionary["name"])
                foundID = foundID ??
                    extractString(from: dictionary["mobileDevicePrestageId"]) ??
                    extractString(from: dictionary["profileId"]) ??
                    extractString(from: dictionary["id"])
            }

            for prestageKey in ["enrollmentMethodPrestage", "prestageEnrollmentProfile", "prestageEnrollment", "prestage"] {
                if let prestageObject = dictionary[prestageKey] {
                    let nested = extractPrestageNameAndID(from: prestageObject, inPrestageContext: true)
                    foundName = foundName ?? nested.name
                    foundID = foundID ?? nested.id
                }
            }

            for (key, nestedValue) in dictionary where key.lowercased().contains("prestage") {
                let lowerKey = key.lowercased()
                if foundName == nil && lowerKey.contains("name") {
                    foundName = extractString(from: nestedValue)
                }
                if foundID == nil && lowerKey.contains("id") {
                    foundID = extractString(from: nestedValue)
                }

                let nested = extractPrestageNameAndID(from: nestedValue, inPrestageContext: true)
                foundName = foundName ?? nested.name
                foundID = foundID ?? nested.id
            }

            if foundName != nil || foundID != nil {
                return (foundName, foundID)
            }

            for nestedValue in dictionary.values {
                let nested = extractPrestageNameAndID(from: nestedValue, inPrestageContext: false)
                if nested.name != nil || nested.id != nil {
                    return nested
                }
            }
        }

        if let array = value as? [Any] {
            for element in array {
                let nested = extractPrestageNameAndID(from: element, inPrestageContext: inPrestageContext)
                if nested.name != nil || nested.id != nil {
                    return nested
                }
            }
        }

        return (nil, nil)
    }

    private static func extractPrestageEnrollmentStatus(from value: Any, inPrestageContext: Bool = false) -> String? {
        if let dictionary = value as? [String: Any] {
            let preferredKeys = [
                "prestageEnrollmentStatus",
                "managementStatus",
                "enrollmentStatus",
                "managed",
                "isManaged",
                "enrolled",
                "isEnrolled"
            ]

            if inPrestageContext {
                for key in preferredKeys {
                    if let normalized = normalizePrestageStatus(extractString(from: dictionary[key])) {
                        return normalized
                    }
                }
            } else {
                for key in ["prestageEnrollmentStatus", "generalPrestageEnrollmentStatus"] {
                    if let normalized = normalizePrestageStatus(extractString(from: dictionary[key])) {
                        return normalized
                    }
                }
            }

            for prestageKey in ["enrollmentMethodPrestage", "prestageEnrollmentProfile", "prestageEnrollment", "prestage"] {
                if let nested = dictionary[prestageKey],
                   let normalized = extractPrestageEnrollmentStatus(from: nested, inPrestageContext: true)
                {
                    return normalized
                }
            }

            for (key, nestedValue) in dictionary where key.lowercased().contains("prestage") {
                let lowerKey = key.lowercased()
                if isPrestageStatusKey(lowerKey) {
                    if let normalized = normalizePrestageStatus(extractString(from: nestedValue)) {
                        return normalized
                    }
                }
                if let nested = extractPrestageEnrollmentStatus(from: nestedValue, inPrestageContext: true) {
                    return nested
                }
            }

            for nestedValue in dictionary.values {
                if let nested = extractPrestageEnrollmentStatus(from: nestedValue, inPrestageContext: false) {
                    return nested
                }
            }
        }

        if let array = value as? [Any] {
            for element in array {
                if let nested = extractPrestageEnrollmentStatus(from: element, inPrestageContext: inPrestageContext) {
                    return nested
                }
            }
        }

        return nil
    }

    private static func isPrestageStatusKey(_ lowerKey: String) -> Bool {
        lowerKey.contains("status") ||
            lowerKey == "managementstatus" ||
            lowerKey == "managed" ||
            lowerKey == "ismanaged" ||
            lowerKey == "enrolled" ||
            lowerKey == "isenrolled"
    }

    private static func normalizePrestageStatus(_ value: String?) -> String? {
        guard let normalized = normalizeComponent(value) else {
            return nil
        }

        switch normalized.lowercased() {
        case "true", "managed", "enrolled":
            return enrolledStatusLabel
        case "false", "unmanaged", "not enrolled":
            return notEnrolledStatusLabel
        default:
            if normalized.lowercased().contains("not enrolled") ||
                normalized.lowercased().contains("unmanaged")
            {
                return notEnrolledStatusLabel
            }

            if normalized.lowercased().contains("enrolled") ||
                normalized.lowercased().contains("managed")
            {
                return enrolledStatusLabel
            }

            return normalized
        }
    }

    private static func normalizeComponent(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func extractString(from value: Any?) -> String? {
        switch value {
        case let stringValue as String:
            return normalizeComponent(stringValue)
        case let boolValue as Bool:
            return boolValue ? "true" : "false"
        case let intValue as Int:
            return String(intValue)
        case let doubleValue as Double:
            return String(doubleValue)
        case let number as NSNumber:
            return number.stringValue
        case let dictionary as [String: Any]:
            return extractString(from: dictionary["profileName"]) ??
                extractString(from: dictionary["displayName"]) ??
                extractString(from: dictionary["name"]) ??
                extractString(from: dictionary["value"]) ??
                extractString(from: dictionary["id"]) ??
                extractString(from: dictionary["mobileDevicePrestageId"])
        default:
            return nil
        }
    }

    // MARK: - Mobile PreStage Scope Resolution
    //
    // The mobile-device detail payload carries NO inline PreStage assignment
    // (its `enrollmentMethod` is null and no `prestage*` field is present —
    // verified against live payload dumps). The only source is the prestage
    // scope API: list every mobile-device-prestage, read each one's scope
    // (serial numbers), and match the device's serial. These parsers mirror
    // the shapes the Mobile Device Search module already handles.

    /// Parses one page of `GET api/v2/mobile-device-prestages` into `[id: displayName]`.
    static func mobilePrestageNames(fromListPage page: [String: Any]) -> [String: String] {
        var names: [String: String] = [:]
        for item in objectArray(in: page, preferredKeys: ["results", "prestages", "mobileDevicePrestages", "items", "data"]) {
            guard let id = extractString(from: item["id"]) ?? extractString(from: item["prestageId"]) else {
                continue
            }
            let name = extractString(from: item["displayName"])
                ?? extractString(from: item["name"])
                ?? extractString(from: item["profileName"])
                ?? "Pre-Stage \(id)"
            names[id] = name
        }
        return names
    }

    /// Parses one page of `GET api/v2/mobile-device-prestages/{id}/scope` into
    /// normalized (trimmed, uppercased) serial numbers.
    ///
    /// Mirrors the proven `MobileDeviceSearchViewModel.parseMobileScopeSerials`
    /// so both modules cover the same response shapes: an array of assignment
    /// objects (under `assignments`/`results`/…), serials nested in device
    /// objects, a flat `serialNumbers` array (top-level OR nested under
    /// `assignments`), a top-level JSON array, and a fuzzy "serial" key
    /// fallback. Takes the raw deserialized JSON so a top-level array response
    /// is handled too.
    static func mobilePrestageScopeSerials(fromScopeJSON jsonObject: Any) -> [String] {
        if let dictionary = jsonObject as? [String: Any] {
            let preferredKeys = ["assignments", "results", "devices", "mobileDevices", "items", "data"]

            for key in preferredKeys {
                guard let objects = dictionaryArray(from: dictionary[key]), objects.isEmpty == false else {
                    continue
                }
                let serials = objects.compactMap(scopeSerial(fromAssignment:))
                if serials.isEmpty == false { return serials }
            }

            for value in dictionary.values {
                guard let objects = dictionaryArray(from: value), objects.isEmpty == false else {
                    continue
                }
                let serials = objects.compactMap(scopeSerial(fromAssignment:))
                if serials.isEmpty == false { return serials }
            }

            // Flat `serialNumbers: [..]` shape, top-level or nested under a
            // container key (`extractStringArray` drills into dict containers).
            if let serialNumbers =
                extractStringArray(from: dictionary["serialNumbers"]) ??
                extractStringArray(from: dictionary["assignments"]) ??
                extractStringArray(from: dictionary["results"]) {
                return serialNumbers.compactMap(normalizeSerial)
            }
        }

        if let objects = dictionaryArray(from: jsonObject), objects.isEmpty == false {
            return objects.compactMap(scopeSerial(fromAssignment:))
        }

        if let serialNumbers = extractStringArray(from: jsonObject) {
            return serialNumbers.compactMap(normalizeSerial)
        }

        return []
    }

    /// Dictionary-shaped entry point retained for existing callers/tests.
    static func mobilePrestageScopeSerials(fromScopePage page: [String: Any]) -> [String] {
        mobilePrestageScopeSerials(fromScopeJSON: page)
    }

    /// Trims whitespace and uppercases a serial number; nil for empty input.
    static func normalizeSerial(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              trimmed.isEmpty == false
        else {
            return nil
        }
        return trimmed.uppercased()
    }

    /// Extracts a serial from one scope-assignment dictionary: direct keys
    /// first, then nested device objects, then a fuzzy "serial" key fallback.
    private static func scopeSerial(fromAssignment item: [String: Any]) -> String? {
        var serial = extractString(from: item["serialNumber"])
            ?? extractString(from: item["serial"])
            ?? extractString(from: item["hardwareSerialNumber"])

        for key in ["mobileDevice", "device", "inventoryRecord", "inventory", "item"] {
            guard let nested = item[key] as? [String: Any] else { continue }
            serial = serial
                ?? extractString(from: nested["serialNumber"])
                ?? extractString(from: nested["serial"])
        }

        // Last resort: any key whose name contains "serial".
        if serial == nil {
            serial = extractValue(matching: "serial", in: item)
        }

        return normalizeSerial(serial)
    }

    /// Coerces a value into an array of dictionaries, unwrapping nested arrays
    /// and well-known container keys. Mirrors the proven MobileDeviceSearch
    /// helper so both modules accept the same scope/list response shapes.
    private static func dictionaryArray(from value: Any?) -> [[String: Any]]? {
        if let dictionaries = value as? [[String: Any]] {
            return dictionaries
        }

        if let array = value as? [Any] {
            let dictionaries = array.compactMap { $0 as? [String: Any] }
            if dictionaries.isEmpty == false {
                return dictionaries
            }
            for element in array {
                if let nested = dictionaryArray(from: element), nested.isEmpty == false {
                    return nested
                }
            }
            return []
        }

        if let dictionary = value as? [String: Any] {
            for key in ["results", "mobileDevices", "devices", "items", "data"] where dictionary.keys.contains(key) {
                if let nested = dictionaryArray(from: dictionary[key]) {
                    return nested
                }
            }
        }

        return nil
    }

    /// Coerces a value into an array of strings, drilling into dict containers
    /// (`serialNumbers`/`serials`/`items`/`values`) when handed a dictionary.
    private static func extractStringArray(from value: Any?) -> [String]? {
        if let strings = value as? [String] {
            let cleaned = strings.compactMap { extractString(from: $0) }
            return cleaned.isEmpty ? nil : cleaned
        }
        if let array = value as? [Any] {
            let cleaned = array.compactMap { extractString(from: $0) }
            return cleaned.isEmpty ? nil : cleaned
        }
        if let dictionary = value as? [String: Any] {
            return extractStringArray(from: dictionary["serialNumbers"])
                ?? extractStringArray(from: dictionary["serials"])
                ?? extractStringArray(from: dictionary["items"])
                ?? extractStringArray(from: dictionary["values"])
        }
        return nil
    }

    /// Returns the first string value whose key contains `keyFragment`
    /// (case-insensitive), recursing into nested dictionaries.
    private static func extractValue(matching keyFragment: String, in dictionary: [String: Any]) -> String? {
        for (key, value) in dictionary {
            if key.localizedCaseInsensitiveContains(keyFragment),
               let extracted = extractString(from: value) {
                return extracted
            }
            if let nested = value as? [String: Any],
               let nestedValue = extractValue(matching: keyFragment, in: nested) {
                return nestedValue
            }
        }
        return nil
    }

    /// Finds the first non-empty array of dictionaries under the preferred
    /// keys, then falls back to any array-of-dictionaries value on the page.
    private static func objectArray(in page: [String: Any], preferredKeys: [String]) -> [[String: Any]] {
        for key in preferredKeys {
            if let array = page[key] as? [Any] {
                let dictionaries = array.compactMap { $0 as? [String: Any] }
                if dictionaries.isEmpty == false { return dictionaries }
            }
        }
        for value in page.values {
            if let array = value as? [Any] {
                let dictionaries = array.compactMap { $0 as? [String: Any] }
                if dictionaries.isEmpty == false { return dictionaries }
            }
        }
        return []
    }
}

//endofline
