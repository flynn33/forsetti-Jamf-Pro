import Foundation

actor ReportsInventoryService {
    private enum ComputerEndpointVersion: String, CaseIterable {
        case v3
        case v2
        case v1

        var path: String {
            "api/\(rawValue)/computers-inventory"
        }

        var supportedSections: Set<ComputerInventorySection> {
            switch self {
            case .v1:
                return Set(ComputerInventorySection.allCases)
            case .v2, .v3:
                return Set(ComputerInventorySection.allCases).subtracting([.plugins, .fonts])
            }
        }
    }

    private enum MobileSectionEncoding {
        case modern
        case legacy
        case none
    }

    /// In-memory snapshot of the tenant's inventory the service holds onto
    /// after the first successful load. Every subsequent `loadReport` call
    /// filters this snapshot client-side rather than hitting Jamf Pro
    /// again. Cleared by `invalidateCache()` (called from the view model's
    /// Refresh path) and naturally discarded when the actor instance goes
    /// away — which happens when the Reports module's root view is torn
    /// down, so closing and re-opening the module gets fresh data.
    private struct Cache {
        let directory: ReportsLocationDirectory
        let computers: [ReportDeviceRecord]
        let mobileDevices: [ReportDeviceRecord]
        let loadedAt: Date
        let serverLabel: String?

        func records(for domains: Set<ReportInventoryDomain>) -> [ReportDeviceRecord] {
            var out: [ReportDeviceRecord] = []
            if domains.contains(.computer) {
                out.append(contentsOf: computers)
            }
            if domains.contains(.mobile) {
                out.append(contentsOf: mobileDevices)
            }
            return out
        }
    }

    private let apiGateway: JamfAPIGateway
    private let diagnosticsReporter: any DiagnosticsReporting
    private let resolver = ReportDeviceIdentityResolver()
    private let aggregator = ReportsAggregator()

    private let source = "module.reports"

    /// Currently held cache snapshot. `nil` after construction and after
    /// `invalidateCache()`. The first `loadReport` call that observes `nil`
    /// triggers the cache build; concurrent callers see a single in-flight
    /// build via Swift's actor reentrancy because cache assignment happens
    /// after the build completes.
    private var cache: Cache?

    /// Display name of the Extension Attribute whose value drives the
    /// Locations panel of a generated report. The EA is expected to exist
    /// under this exact name on both the computer and mobile sides of the
    /// tenant (case-insensitive). When it is absent the record buckets as
    /// "Unassigned" in the panel.
    private static let locationExtensionAttributeName = "Billing GL & Store NO"

    /// Computer inventory sections the cache always requests. Covers every
    /// `ReportField` whose `computerSection` is non-nil in the catalog, so
    /// any criterion the user adds later can be evaluated client-side
    /// without re-fetching. Skips heavy or rarely-used sections (plugins,
    /// fonts, packages, applications, …) because they bloat the payload
    /// and aren't referenced by any catalog field today.
    private static let cacheComputerSections: Set<ComputerInventorySection> = [
        .general,
        .hardware,
        .operatingSystem,
        .userAndLocation,
        .extensionAttributes
    ]

    /// Mobile inventory sections the cache always requests. Same rationale
    /// as `cacheComputerSections`.
    private static let cacheMobileSections: Set<MobileDeviceInventorySection> = [
        .general,
        .hardware,
        .location,
        .security,
        .extensionAttributes
    ]

    init(apiGateway: JamfAPIGateway, diagnosticsReporter: any DiagnosticsReporting) {
        self.apiGateway = apiGateway
        self.diagnosticsReporter = diagnosticsReporter
    }

    // MARK: - Public API

    func loadDefaultData() async throws -> ReportDataSet {
        try await loadReport(request: .defaultCounts)
    }

    /// Returns the timestamp of the current cache snapshot, or `nil` when
    /// no cache has been built since the last `invalidateCache()`. The
    /// view model can use this to render a "Cache built at …" hint.
    func cacheLoadedAt() -> Date? {
        cache?.loadedAt
    }

    /// Drops the in-memory cache so the next `loadReport` call re-fetches
    /// from Jamf Pro. Called by `ReportsViewModel.refreshDefaultCounts()`
    /// when the user taps the toolbar Refresh button.
    func invalidateCache() {
        cache = nil
    }

    func loadReport(request: ReportRequest) async throws -> ReportDataSet {
        let plan = ReportsQueryPlanner.makePlan(for: request)
        let wasCacheHit = cache != nil

        await diagnosticsReporter.report(
            source: source,
            category: "load-start",
            severity: .info,
            message: "Reports inventory load started.",
            metadata: [
                "domain_count": String(plan.domains.count),
                "criteria_count": String(request.criteria.count),
                "cache_hit": String(wasCacheHit)
            ]
        )

        do {
            // First call rebuilds the cache from Jamf; every subsequent
            // call short-circuits to the in-memory snapshot. The cache
            // intentionally holds both domains plus every section a
            // catalog field can need, so criteria can be evaluated
            // client-side without re-issuing inventory requests.
            let snapshot = try await ensureCache()

            // All cached records that fall within the request's domain
            // set. The criteria are then applied entirely client-side —
            // the planner's `computerServerFilter` and `mobileServerFilter`
            // are unused under the caching architecture, but the planner
            // is kept whole because `matches(record:criteria:)` and
            // `validate(_:)` still drive every filter and validation
            // decision the view model needs.
            let candidate = snapshot.records(for: plan.domains)
            let filtered = candidate.filter {
                ReportsQueryPlanner.matches(record: $0, criteria: request.criteria)
            }
            let aggregate = aggregator.aggregate(records: filtered)

            await diagnosticsReporter.report(
                source: source,
                category: "load-finish",
                severity: .info,
                message: "Reports inventory load finished.",
                metadata: [
                    "cache_hit": String(wasCacheHit),
                    "candidate_count": String(candidate.count),
                    "filtered_record_count": String(filtered.count),
                    "unknown_count": String(aggregate.unknownCount),
                    "inferred_count": String(aggregate.inferredCount)
                ]
            )

            return ReportDataSet(
                records: filtered,
                aggregate: aggregate,
                generatedAt: Date(),
                serverLabel: snapshot.serverLabel
            )
        } catch {
            await diagnosticsReporter.reportError(
                source: source,
                category: "load",
                message: "Reports inventory load failed.",
                errorDescription: describe(error)
            )
            throw error
        }
    }

    // MARK: - Cache build

    /// Returns the existing cache or builds a new one on cache miss. The
    /// build fetches the location directory, computer inventory, and
    /// mobile inventory in parallel; pages within each fetch remain
    /// sequential because Jamf Pro paginates by index. Diagnostics
    /// telemetry brackets the build with `cache-build-start` and
    /// `cache-build-finish` events so operators can see when the heavy
    /// fetch happened on a given session.
    private func ensureCache() async throws -> Cache {
        if let cache {
            return cache
        }

        let buildStartedAt = Date()
        await diagnosticsReporter.report(
            source: source,
            category: "cache-build-start",
            severity: .info,
            message: "Reports inventory cache build started.",
            metadata: [
                "computer_sections": String(Self.cacheComputerSections.count),
                "mobile_sections": String(Self.cacheMobileSections.count)
            ]
        )

        async let directoryTask = loadLocationDirectory()
        async let serverHostTask = apiGateway.currentServerBaseURL()

        let directory = await directoryTask
        let computers = try await fetchAllComputers(directory: directory)
        let mobileDevices = try await fetchAllMobileDevices()
        let serverLabel = await serverHostTask?.host

        let snapshot = Cache(
            directory: directory,
            computers: computers,
            mobileDevices: mobileDevices,
            loadedAt: Date(),
            serverLabel: serverLabel
        )
        cache = snapshot

        await diagnosticsReporter.report(
            source: source,
            category: "cache-build-finish",
            severity: .info,
            message: "Reports inventory cache built.",
            metadata: [
                "computer_count": String(computers.count),
                "mobile_count": String(mobileDevices.count),
                "elapsed_seconds": format(elapsedSince: buildStartedAt)
            ]
        )

        return snapshot
    }

    /// Cache-build variant of the prior `fetchComputers(plan:directory:)`.
    /// Always requests `cacheComputerSections` with no server-side filter
    /// so the resulting array is the unfiltered universe of computer
    /// records the rest of the module's lifetime works against.
    private func fetchAllComputers(directory: ReportsLocationDirectory) async throws -> [ReportDeviceRecord] {
        var records: [ReportDeviceRecord] = []
        var page = 0
        var pageCount = 0
        var totalCount: Int?

        while true {
            let data = try await requestComputerPage(
                sections: Self.cacheComputerSections,
                filter: nil,
                page: page
            )
            let decoded = try ReportsJSON.decodePage(from: data)
            totalCount = decoded.totalCount ?? totalCount
            let pageRecords = decoded.records.map { makeComputerRecord(from: $0, directory: directory) }
            records.append(contentsOf: pageRecords)
            pageCount += 1

            if ReportsPaginationPolicy.shouldStop(
                pageRecordCount: pageRecords.count,
                page: page,
                totalCount: totalCount,
                accumulatedCount: records.count
            ) {
                break
            }

            page += 1
        }

        await diagnosticsReporter.report(
            source: source,
            category: "computer-pages",
            severity: .info,
            message: "Fetched computer inventory pages for cache.",
            metadata: [
                "page_count": String(pageCount),
                "record_count": String(records.count)
            ]
        )

        return records
    }

    /// Cache-build variant of the prior `fetchMobileDevices(plan:)`. Always
    /// requests `cacheMobileSections` with no server-side filter so the
    /// resulting array is the unfiltered universe of mobile records.
    private func fetchAllMobileDevices() async throws -> [ReportDeviceRecord] {
        var records: [ReportDeviceRecord] = []
        var page = 0
        var pageCount = 0
        var totalCount: Int?

        while true {
            let data = try await requestMobilePage(
                sections: Self.cacheMobileSections,
                filter: nil,
                page: page
            )
            let decoded = try ReportsJSON.decodePage(from: data)
            totalCount = decoded.totalCount ?? totalCount
            let pageRecords = decoded.records.map { makeMobileRecord(from: $0) }
            records.append(contentsOf: pageRecords)
            pageCount += 1

            if ReportsPaginationPolicy.shouldStop(
                pageRecordCount: pageRecords.count,
                page: page,
                totalCount: totalCount,
                accumulatedCount: records.count
            ) {
                break
            }

            page += 1
        }

        await diagnosticsReporter.report(
            source: source,
            category: "mobile-pages",
            severity: .info,
            message: "Fetched mobile device inventory pages for cache.",
            metadata: [
                "page_count": String(pageCount),
                "record_count": String(records.count)
            ]
        )

        return records
    }

    /// Helper used by the cache-build diagnostics to format the elapsed
    /// time in seconds with one decimal place, without pulling in
    /// `DateComponentsFormatter`. Returns a `String` so the metadata
    /// dictionary remains `[String: String]`.
    private nonisolated func format(elapsedSince start: Date) -> String {
        let seconds = -start.timeIntervalSinceNow
        return String(format: "%.1f", seconds)
    }

    private func requestComputerPage(
        sections: Set<ComputerInventorySection>,
        filter: String?,
        page: Int
    ) async throws -> Data {
        var lastError: (any Error)?

        for version in ComputerEndpointVersion.allCases {
            let supportedSections = sections.intersection(version.supportedSections)
            var queryItems: [URLQueryItem] = [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "page-size", value: String(ReportsPaginationPolicy.defaultPageSize)),
                URLQueryItem(name: "sort", value: "general.name:asc")
            ]
            queryItems.append(contentsOf: supportedSections.sorted { $0.rawValue < $1.rawValue }.map {
                URLQueryItem(name: "section", value: $0.rawValue)
            })
            if let filter, filter.isEmpty == false {
                queryItems.append(URLQueryItem(name: "filter", value: filter))
            }

            do {
                return try await apiGateway.request(path: version.path, queryItems: queryItems)
            } catch {
                lastError = error
                continue
            }
        }

        throw lastError ?? JamfFrameworkError.notFound(message: "Computer inventory endpoint unavailable.")
    }

    private func requestMobilePage(
        sections: Set<MobileDeviceInventorySection>,
        filter: String?,
        page: Int
    ) async throws -> Data {
        var lastError: (any Error)?
        for encoding in [MobileSectionEncoding.modern, .legacy, .none] {
            var queryItems: [URLQueryItem] = [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "page-size", value: String(ReportsPaginationPolicy.defaultPageSize)),
                URLQueryItem(name: "sort", value: "displayName:asc")
            ]

            if encoding != .none {
                queryItems.append(contentsOf: sections.sorted { $0.rawValue < $1.rawValue }.map {
                    URLQueryItem(
                        name: "section",
                        value: encoding == .legacy ? legacyMobileSectionValue(for: $0) : $0.rawValue
                    )
                })
            }

            if let filter, filter.isEmpty == false {
                queryItems.append(URLQueryItem(name: "filter", value: filter))
            }

            do {
                return try await apiGateway.request(path: "api/v2/mobile-devices/detail", queryItems: queryItems)
            } catch {
                lastError = error
                continue
            }
        }

        throw lastError ?? JamfFrameworkError.notFound(message: "Mobile device inventory endpoint unavailable.")
    }

    private func makeComputerRecord(from raw: [String: Any], directory: ReportsLocationDirectory) -> ReportDeviceRecord {
        let id = ReportsJSON.string(from: raw, paths: ["id", "computerId", "general.id"]) ?? UUID().uuidString
        let displayName = ReportsJSON.string(from: raw, paths: ["general.name", "computerName", "name"])
        let serialNumber = ReportsJSON.string(from: raw, paths: ["hardware.serialNumber", "serialNumber"])
        let model = ReportsJSON.string(from: raw, paths: ["hardware.model", "model"])
        let modelIdentifier = ReportsJSON.string(from: raw, paths: ["hardware.modelIdentifier", "modelIdentifier"])
        let osVersion = ReportsJSON.string(from: raw, paths: ["operatingSystem.version", "osVersion"])
        let osBuild = ReportsJSON.string(from: raw, paths: ["operatingSystem.build", "osBuild"])
        let platform = ReportsJSON.string(from: raw, paths: ["general.platform", "platform"])
        let buildingId = ReportsJSON.string(from: raw, paths: ["userAndLocation.buildingId"])
        let departmentId = ReportsJSON.string(from: raw, paths: ["userAndLocation.departmentId"])
        // Prefer the resolved name from the buildings/departments directory.
        // Fall back to any literal name Jamf returned, then to the raw ID so
        // operators still see *something* if the lookup endpoints were
        // unreachable.
        let resolvedBuilding = directory.buildingName(for: buildingId)
            ?? ReportsJSON.string(from: raw, paths: ["userAndLocation.building", "building"])
            ?? buildingId
        let resolvedDepartment = directory.departmentName(for: departmentId)
            ?? ReportsJSON.string(from: raw, paths: ["userAndLocation.department", "department"])
            ?? departmentId
        let location = ReportDeviceLocation(
            building: resolvedBuilding,
            department: resolvedDepartment,
            room: ReportsJSON.string(from: raw, paths: ["userAndLocation.room", "room"]),
            assignedName: ReportsJSON.string(from: raw, paths: ["userAndLocation.realname", "userAndLocation.username", "username"]),
            email: ReportsJSON.string(from: raw, paths: ["userAndLocation.email", "email"])
        )
        let management = ReportDeviceManagement(
            managed: ReportsJSON.bool(from: raw, paths: ["general.remoteManagement.managed", "general.managed", "managed"]),
            supervised: ReportsJSON.bool(from: raw, paths: ["general.supervised", "supervised"]),
            ownership: nil
        )
        let metrics = ReportHardwareMetrics(
            capacityMb: ReportsJSON.int(from: raw, paths: ["hardware.storageCapacityMb", "hardware.totalCapacityMb"]),
            availableSpaceMb: ReportsJSON.int(from: raw, paths: ["hardware.availableSpaceMb"]),
            usedSpacePercentage: nil,
            batteryLevel: ReportsJSON.int(from: raw, paths: ["hardware.batteryCapacityPercent"]),
            batteryHealth: nil
        )
        let identity = resolver.resolve(
            domain: .computer,
            model: model,
            modelIdentifier: modelIdentifier,
            modelNumber: nil,
            capacityMb: metrics.capacityMb,
            platformHint: platform
        )

        return ReportDeviceRecord(
            id: "computer-\(id)",
            domain: .computer,
            deviceType: identity.deviceType,
            displayName: displayName,
            serialNumber: serialNumber,
            model: model,
            modelIdentifier: modelIdentifier,
            modelNumber: nil,
            osVersion: osVersion,
            osBuild: osBuild,
            location: location,
            management: management,
            hardwareMetrics: metrics,
            identity: identity,
            fieldValues: makeFieldValues(
                deviceType: identity.deviceType,
                displayName: displayName,
                serialNumber: serialNumber,
                model: identity.marketingName ?? model,
                modelIdentifier: modelIdentifier,
                modelNumber: nil,
                osVersion: osVersion,
                osBuild: osBuild,
                location: location,
                management: management,
                metrics: metrics,
                identity: identity,
                enrollmentDate: ReportsEnrollmentDate.normalize(ReportsJSON.string(from: raw, paths: ["general.lastEnrolledDate", "lastEnrolledDate"])),
                extensionAttributes: ReportsJSON.string(from: raw, paths: ["extensionAttributes", "extensionAttributes[].values[]"]),
                locationExtensionAttribute: ReportsJSON.extensionAttributeValue(named: Self.locationExtensionAttributeName, from: raw)
            )
        )
    }

    private func makeMobileRecord(from raw: [String: Any]) -> ReportDeviceRecord {
        let id = ReportsJSON.string(from: raw, paths: ["id", "mobileDeviceId", "general.id"]) ?? UUID().uuidString
        let displayName = ReportsJSON.string(from: raw, paths: ["general.displayName", "general.deviceName", "displayName", "deviceName", "name"])
        let serialNumber = ReportsJSON.string(from: raw, paths: ["hardware.serialNumber", "general.serialNumber", "serialNumber"])
        let model = ReportsJSON.string(from: raw, paths: ["hardware.model", "general.model", "model"])
        let modelIdentifier = ReportsJSON.string(from: raw, paths: ["hardware.modelIdentifier", "general.modelIdentifier", "modelIdentifier"])
        let modelNumber = ReportsJSON.string(from: raw, paths: ["hardware.modelNumber", "general.modelNumber", "modelNumber"])
        let osVersion = ReportsJSON.string(from: raw, paths: ["general.osVersion", "osVersion"])
        let osBuild = ReportsJSON.string(from: raw, paths: ["general.osBuild", "osBuild"])
        let location = ReportDeviceLocation(
            building: ReportsJSON.string(from: raw, paths: ["userAndLocation.building", "location.building", "building"]),
            department: ReportsJSON.string(from: raw, paths: ["userAndLocation.department", "location.department", "department"]),
            room: ReportsJSON.string(from: raw, paths: ["userAndLocation.room", "location.room", "room"]),
            assignedName: ReportsJSON.string(from: raw, paths: ["userAndLocation.username", "location.username", "username"]),
            email: ReportsJSON.string(from: raw, paths: ["userAndLocation.emailAddress", "location.emailAddress", "emailAddress", "email"])
        )
        let metrics = ReportHardwareMetrics(
            capacityMb: ReportsJSON.int(from: raw, paths: ["hardware.capacityMb", "capacityMb"]),
            availableSpaceMb: ReportsJSON.int(from: raw, paths: ["hardware.availableSpaceMb", "availableSpaceMb"]),
            usedSpacePercentage: ReportsJSON.int(from: raw, paths: ["hardware.usedSpacePercentage", "usedSpacePercentage"]),
            batteryLevel: ReportsJSON.int(from: raw, paths: ["hardware.batteryLevel", "batteryLevel"]),
            batteryHealth: ReportsJSON.string(from: raw, paths: ["hardware.batteryHealth", "batteryHealth"])
        )
        let management = ReportDeviceManagement(
            managed: ReportsJSON.bool(from: raw, paths: ["general.managed", "managed"]),
            supervised: ReportsJSON.bool(from: raw, paths: ["security.supervised", "general.supervised", "supervised"]),
            ownership: ReportsJSON.string(from: raw, paths: ["general.deviceOwnershipType", "deviceOwnershipType"])
        )
        let identity = resolver.resolve(
            domain: .mobile,
            model: model,
            modelIdentifier: modelIdentifier,
            modelNumber: modelNumber,
            capacityMb: metrics.capacityMb,
            platformHint: nil
        )

        return ReportDeviceRecord(
            id: "mobile-\(id)",
            domain: .mobile,
            deviceType: identity.deviceType,
            displayName: displayName,
            serialNumber: serialNumber,
            model: model,
            modelIdentifier: modelIdentifier,
            modelNumber: modelNumber,
            osVersion: osVersion,
            osBuild: osBuild,
            location: location,
            management: management,
            hardwareMetrics: metrics,
            identity: identity,
            fieldValues: makeFieldValues(
                deviceType: identity.deviceType,
                displayName: displayName,
                serialNumber: serialNumber,
                model: identity.marketingName ?? model,
                modelIdentifier: modelIdentifier,
                modelNumber: modelNumber,
                osVersion: osVersion,
                osBuild: osBuild,
                location: location,
                management: management,
                metrics: metrics,
                identity: identity,
                enrollmentDate: ReportsEnrollmentDate.normalize(ReportsJSON.string(from: raw, paths: ["general.lastEnrolledDate", "lastEnrolledDate"])),
                extensionAttributes: ReportsJSON.string(from: raw, paths: ["extensionAttributes", "extensionAttributes[].values[]"]),
                locationExtensionAttribute: ReportsJSON.extensionAttributeValue(named: Self.locationExtensionAttributeName, from: raw)
            )
        )
    }

    private func makeFieldValues(
        deviceType: ReportDeviceType,
        displayName: String?,
        serialNumber: String?,
        model: String?,
        modelIdentifier: String?,
        modelNumber: String?,
        osVersion: String?,
        osBuild: String?,
        location: ReportDeviceLocation,
        management: ReportDeviceManagement,
        metrics: ReportHardwareMetrics,
        identity: ReportDeviceIdentity,
        enrollmentDate: String?,
        extensionAttributes: String?,
        locationExtensionAttribute: String?
    ) -> [String: String] {
        var values: [String: String] = [
            "deviceType": deviceType.displayName,
            "sourceConfidence": identity.confidence.displayName
        ]

        func set(_ key: String, _ value: String?) {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, trimmed.isEmpty == false {
                values[key] = trimmed
            }
        }

        set("name", displayName)
        set("serialNumber", serialNumber)
        set("model", model)
        set("modelIdentifier", modelIdentifier)
        set("modelNumber", modelNumber)
        set("osVersion", osVersion)
        set("osBuild", osBuild)
        set("enrollmentDate", enrollmentDate)
        set("building", location.building)
        set("department", location.department)
        set("room", location.room)
        set("assignedName", location.assignedName)
        set("email", location.email)
        set("ownership", management.ownership)
        set("batteryHealth", metrics.batteryHealth)
        set("marketingName", identity.marketingName)
        set("chipName", identity.chipName)
        set("extensionAttributes", extensionAttributes)
        set(ReportDeviceRecord.locationExtensionAttributeFieldKey, locationExtensionAttribute)

        if let managed = management.managed { values["managed"] = String(managed) }
        if let supervised = management.supervised { values["supervised"] = String(supervised) }
        if let capacityMb = metrics.capacityMb { values["capacityMb"] = String(capacityMb) }
        if let available = metrics.availableSpaceMb { values["availableSpaceMb"] = String(available) }
        if let used = metrics.usedSpacePercentage { values["usedSpacePercentage"] = String(used) }
        if let battery = metrics.batteryLevel { values["batteryLevel"] = String(battery) }

        return values
    }

    private func legacyMobileSectionValue(for section: MobileDeviceInventorySection) -> String {
        switch section {
        case .location: return "LOCATION"
        case .configurationProfiles: return "CONFIGURATION_PROFILES"
        case .mobileDeviceGroups: return "GROUPS"
        default: return section.rawValue
        }
    }

    private func describe(_ error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private func loadLocationDirectory() async -> ReportsLocationDirectory {
        async let buildings = fetchIDNameTable(path: "api/v1/buildings", diagnosticsCategory: "buildings-lookup")
        async let departments = fetchIDNameTable(path: "api/v1/departments", diagnosticsCategory: "departments-lookup")
        return ReportsLocationDirectory(buildings: await buildings, departments: await departments)
    }

    private func fetchIDNameTable(path: String, diagnosticsCategory: String) async -> [String: String] {
        do {
            let data = try await apiGateway.request(
                path: path,
                queryItems: [URLQueryItem(name: "page-size", value: "1000")]
            )
            let page = try ReportsJSON.decodePage(from: data)
            var table: [String: String] = [:]
            for record in page.records {
                guard let id = ReportsJSON.string(from: record, paths: ["id"]),
                      let name = ReportsJSON.string(from: record, paths: ["name"])
                else { continue }
                table[id] = name
            }
            return table
        } catch {
            await diagnosticsReporter.report(
                source: source,
                category: diagnosticsCategory,
                severity: .warning,
                message: "Unable to load \(path); building/department names will fall back to raw IDs.",
                metadata: ["error": describe(error)]
            )
            return [:]
        }
    }
}

/// Normalizes a Jamf enrollment timestamp to a clean, sortable calendar date.
///
/// Jamf Pro returns `lastEnrolledDate` as ISO 8601 (e.g. `2024-05-12T14:30:00.000Z`).
/// We surface the date portion (`YYYY-MM-DD`), which is unambiguous and sorts
/// chronologically as plain text in the details table and exports. A value that
/// doesn't match the ISO shape is passed through unchanged so no data is dropped.
/// Internal (not private) so it can be unit-tested directly.
enum ReportsEnrollmentDate {
    // `nonisolated` so these pure helpers can be called from `ReportsInventoryService`'s
    // actor-isolated context without a cross-actor hop, matching `ReportsJSON`.
    nonisolated static func normalize(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              trimmed.isEmpty == false else { return nil }
        if let tIndex = trimmed.firstIndex(of: "T") {
            let datePart = String(trimmed[..<tIndex])
            if isISODate(datePart) { return datePart }
        }
        if isISODate(trimmed) { return trimmed }
        return trimmed
    }

    /// True when `value` is a `YYYY-MM-DD` calendar date.
    nonisolated static func isISODate(_ value: String) -> Bool {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2 else { return false }
        return parts.allSatisfy { $0.allSatisfy(\.isNumber) }
    }
}

private enum ReportsJSON {
    nonisolated struct Page {
        let records: [[String: Any]]
        let totalCount: Int?
    }

    nonisolated static func decodePage(from data: Data) throws -> Page {
        let root = try JSONSerialization.jsonObject(with: data)
        if let array = root as? [[String: Any]] {
            return Page(records: array, totalCount: nil)
        }

        guard let object = root as? [String: Any] else {
            return Page(records: [], totalCount: nil)
        }

        let totalCount = int(from: object, paths: ["totalCount", "total", "page.totalElements"])
        for key in ["results", "computers", "mobileDevices", "mobile_devices", "devices", "data"] {
            if let array = object[key] as? [[String: Any]] {
                return Page(records: array, totalCount: totalCount)
            }
        }

        return Page(records: [], totalCount: totalCount)
    }

    nonisolated static func string(from object: [String: Any], paths: [String]) -> String? {
        for path in paths {
            if let value = value(from: object, path: path),
               let string = stringify(value)
            {
                return string
            }
        }
        return nil
    }

    nonisolated static func int(from object: [String: Any], paths: [String]) -> Int? {
        for path in paths {
            if let value = value(from: object, path: path),
               let int = intValue(value)
            {
                return int
            }
        }
        return nil
    }

    nonisolated static func bool(from object: [String: Any], paths: [String]) -> Bool? {
        for path in paths {
            if let value = value(from: object, path: path),
               let bool = boolValue(value)
            {
                return bool
            }
        }
        return nil
    }

    /// Returns the value of the extension attribute whose `name` matches
    /// `targetName` (case-insensitive, whitespace-trimmed) on the supplied
    /// inventory record. Tolerates both Jamf response shapes:
    ///
    /// - Computers: `{ "name": "...", "values": ["..."] }` (always an array)
    /// - Mobile:    `{ "name": "...", "value": "..." }` (string or array)
    ///
    /// When the EA carries multiple values they are joined with `", "`.
    /// Returns `nil` when the EA is absent, has no value, or the record
    /// does not include the extensionAttributes section at all.
    nonisolated static func extensionAttributeValue(named targetName: String, from object: [String: Any]) -> String? {
        guard let array = object["extensionAttributes"] as? [[String: Any]] else {
            return nil
        }
        let normalized = targetName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        for entry in array {
            guard let entryName = entry["name"] as? String else { continue }
            let candidate = entryName
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard candidate == normalized else { continue }

            // Computer inventory shape — `values` is always an array.
            if let values = entry["values"] as? [Any] {
                let strings = values.compactMap { stringify($0) }
                return strings.isEmpty ? nil : strings.joined(separator: ", ")
            }
            // Mobile inventory shape — `value` may be a single string or an array.
            if let value = entry["value"] {
                if let arrayValue = value as? [Any] {
                    let strings = arrayValue.compactMap { stringify($0) }
                    return strings.isEmpty ? nil : strings.joined(separator: ", ")
                }
                return stringify(value)
            }
        }
        return nil
    }

    nonisolated private static func value(from root: Any, path: String) -> Any? {
        let parts = path.split(separator: ".").map(String.init)
        return value(from: root, parts: parts)
    }

    nonisolated private static func value(from current: Any, parts: [String]) -> Any? {
        guard let first = parts.first else {
            return current
        }

        if first.hasSuffix("[]") {
            let key = String(first.dropLast(2))
            guard let dict = current as? [String: Any],
                  let array = dict[key] as? [Any]
            else {
                return nil
            }
            let remaining = Array(parts.dropFirst())
            let values = array.compactMap { value(from: $0, parts: remaining) }
            return values.isEmpty ? nil : values
        }

        if let dict = current as? [String: Any],
           let next = dict[first]
        {
            return value(from: next, parts: Array(parts.dropFirst()))
        }

        return nil
    }

    nonisolated private static func stringify(_ value: Any) -> String? {
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let bool = value as? Bool {
            return String(bool)
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        if let array = value as? [Any] {
            let values = array.compactMap(stringify)
            return values.isEmpty ? nil : values.joined(separator: "; ")
        }
        if let dict = value as? [String: Any] {
            let values = dict.values.compactMap(stringify)
            return values.isEmpty ? nil : values.joined(separator: "; ")
        }
        return nil
    }

    nonisolated private static func intValue(_ value: Any) -> Int? {
        if let int = value as? Int { return int }
        if let double = value as? Double { return Int(double) }
        if let number = value as? NSNumber { return number.intValue }
        if let string = stringify(value) {
            let normalized = string.split(separator: ".").first.map(String.init) ?? string
            return Int(normalized)
        }
        return nil
    }

    nonisolated private static func boolValue(_ value: Any) -> Bool? {
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        guard let string = stringify(value)?.lowercased() else { return nil }
        switch string {
        case "true", "yes", "1", "managed", "supervised": return true
        case "false", "no", "0", "unmanaged", "unsupervised": return false
        default: return nil
        }
    }
}
