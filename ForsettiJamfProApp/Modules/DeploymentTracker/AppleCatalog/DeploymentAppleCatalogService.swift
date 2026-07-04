import Foundation

// MARK: - Apple Catalog service
//
// The catalog service resolves local hardware information from Apple model
// identifiers, part numbers, vendor SKUs, imported catalog entries, and Jamf
// inventory summaries. Enrichment writes only to Tracker-owned fields.
nonisolated struct DeploymentAppleCatalogService: Sendable {
    private static let embeddedCatalogSourceName = "Deployment Tracker Embedded Apple Catalog"
    private static let embeddedCatalogSourceType = "embedded-model-identifier"

    private let hardwareDerivationService: DeploymentHardwareDerivationService

    init(hardwareDerivationService: DeploymentHardwareDerivationService = DeploymentHardwareDerivationService()) {
        self.hardwareDerivationService = hardwareDerivationService
    }

    func resolve(
        device: DeploymentDevice,
        entries: [DeploymentAppleHardwareCatalogEntry],
        abmSnapshot: AppleBusinessDeviceSnapshot? = nil,
        jamfSnapshot: JamfInventoryDeviceSnapshot? = nil,
        vendorModel: String? = nil
    ) -> DeploymentAppleCatalogResolution {
        // Jamf inventory often carries the model identifier and capacity values
        // needed to disambiguate Apple hardware. Derive that data first, then
        // compare it against active catalog candidates.
        let derivedHardwareInfo = jamfSnapshot.map { hardwareDerivationService.derive(from: $0.payloadSummary) }
        let activeEntries = candidateEntries(
            for: device,
            entries: entries,
            derivedHardwareInfo: derivedHardwareInfo
        )
        let candidates = activeEntries.map { entry in
            score(
                entry,
                device: device,
                derivedHardwareInfo: derivedHardwareInfo,
                abmSnapshot: abmSnapshot,
                jamfSnapshot: jamfSnapshot,
                vendorModel: vendorModel
            )
        }
        .filter { $0.score > 0 }
        .sorted { $0.score > $1.score }

        guard let best = candidates.first else {
            return DeploymentAppleCatalogResolution(
                deviceId: device.id,
                matchState: .noMatch,
                confidenceScore: 0
            )
        }

        if candidates.count > 1,
           let second = candidates.dropFirst().first,
           abs(best.score - second.score) < 0.05 {
            return DeploymentAppleCatalogResolution(
                deviceId: device.id,
                matchState: .ambiguous,
                matchedEntry: best.entry,
                confidenceScore: best.score,
                matchedFields: best.matchedFields,
                conflictMessages: ["Multiple Apple Catalog entries matched with similar confidence."]
            )
        }

        let matchState = matchState(for: best)

        return DeploymentAppleCatalogResolution(
            deviceId: device.id,
            matchState: matchState,
            matchedEntry: best.entry,
            confidenceScore: best.score,
            matchedFields: best.matchedFields
        )
    }

    func catalogEntry(
        for device: DeploymentDevice,
        importedAt: Date = Date()
    ) -> DeploymentAppleHardwareCatalogEntry? {
        catalogEntry(for: device, derivedHardwareInfo: nil, importedAt: importedAt)
    }

    func catalogEntry(
        for device: DeploymentDevice,
        jamfSnapshot: JamfInventoryDeviceSnapshot?,
        importedAt: Date = Date()
    ) -> DeploymentAppleHardwareCatalogEntry? {
        let derivedHardwareInfo = jamfSnapshot.map { hardwareDerivationService.derive(from: $0.payloadSummary) }
        return catalogEntry(for: device, derivedHardwareInfo: derivedHardwareInfo, importedAt: importedAt)
    }

    private func catalogEntry(
        for device: DeploymentDevice,
        derivedHardwareInfo: DeploymentDerivedHardwareInfo?,
        importedAt: Date = Date()
    ) -> DeploymentAppleHardwareCatalogEntry? {
        guard let modelIdentifier = device.modelIdentifier ?? derivedHardwareInfo?.modelIdentifier else {
            return nil
        }
        return catalogEntry(
            fromModelIdentifier: modelIdentifier,
            capacityMb: derivedHardwareInfo?.capacityMb,
            importedAt: importedAt
        )
    }

    func catalogEntry(
        fromModelIdentifier modelIdentifier: String,
        importedAt: Date = Date()
    ) -> DeploymentAppleHardwareCatalogEntry? {
        catalogEntry(fromModelIdentifier: modelIdentifier, capacityMb: nil, importedAt: importedAt)
    }

    func catalogEntry(
        fromModelIdentifier modelIdentifier: String,
        capacityMb: Int?,
        importedAt: Date = Date()
    ) -> DeploymentAppleHardwareCatalogEntry? {
        let normalizedModelIdentifier = modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let info = DeploymentAppleDeviceModelCatalog.info(for: normalizedModelIdentifier) else {
            return nil
        }

        let memory = memoryDescription(for: info, capacityMb: capacityMb)
        let coreSummary = hardwareCoreSummary(for: info)
        let notes = [
            "Derived from the Deployment Tracker embedded Apple hardware catalog using model identifier \(normalizedModelIdentifier).",
            coreSummary.map { "Hardware: \($0)." },
            memory.map { "Memory: \($0)." }
        ]
        .compactMap { $0 }
        .joined(separator: " ")

        return DeploymentAppleHardwareCatalogEntry(
            id: embeddedCatalogEntryId(for: normalizedModelIdentifier),
            sourceName: Self.embeddedCatalogSourceName,
            sourceType: Self.embeddedCatalogSourceType,
            importedAt: importedAt,
            modelIdentifier: normalizedModelIdentifier,
            marketingName: info.marketingName,
            deviceFamily: deviceFamily(for: normalizedModelIdentifier, marketingName: info.marketingName),
            deviceType: deviceType(for: normalizedModelIdentifier),
            chipFamily: chipFamily(from: info.chipName),
            chipName: info.chipName,
            cpuCoreCount: info.cpuCoreCount,
            gpuCoreCount: info.gpuCoreCount,
            neuralCoreCount: info.neuralCoreCount,
            memory: memory,
            confidenceScore: 0.95,
            notes: notes
        )
    }

    func embeddedCatalogEntries(importedAt: Date = Date()) -> [DeploymentAppleHardwareCatalogEntry] {
        DeploymentAppleDeviceModelCatalog.entries.keys
            .sorted()
            .compactMap { catalogEntry(fromModelIdentifier: $0, importedAt: importedAt) }
    }

    func enrichLocalDevice(
        _ device: DeploymentDevice,
        with resolution: DeploymentAppleCatalogResolution,
        jamfSnapshot: JamfInventoryDeviceSnapshot? = nil
    ) -> DeploymentDevice {
        let derivedHardwareInfo = jamfSnapshot.map { hardwareDerivationService.derive(from: $0.payloadSummary) }
        guard let entry = resolution.matchedEntry else {
            return derivedHardwareInfo.map { hardwareDerivationService.enrich(device, with: $0) } ?? device
        }

        var copy = device
        if let marketingName = entry.marketingName,
           copy.model == nil || normalized(copy.model) == normalized(derivedHardwareInfo?.model) {
            copy.model = marketingName
        }
        if copy.modelIdentifier == nil {
            copy.modelIdentifier = entry.modelIdentifier ?? derivedHardwareInfo?.modelIdentifier
        }
        if copy.applePartNumber == nil {
            copy.applePartNumber = entry.applePartNumber
        }
        if copy.vendorSku == nil {
            copy.vendorSku = entry.vendorSku
        }
        if copy.deviceTypeId == nil {
            copy.deviceTypeId = entry.deviceType
        }
        if copy.model == nil {
            copy.model = derivedHardwareInfo?.model
        }
        return copy
    }

    nonisolated private func candidateEntries(
        for device: DeploymentDevice,
        entries: [DeploymentAppleHardwareCatalogEntry],
        derivedHardwareInfo: DeploymentDerivedHardwareInfo?
    ) -> [DeploymentAppleHardwareCatalogEntry] {
        var activeEntries = entries.filter { $0.lifecycleState == .active }
        guard let embeddedEntry = catalogEntry(for: device, derivedHardwareInfo: derivedHardwareInfo) else {
            return activeEntries
        }

        let embeddedIdentifier = normalized(embeddedEntry.modelIdentifier)
        let hasImportedIdentifierMatch = activeEntries.contains {
            normalized($0.modelIdentifier) == embeddedIdentifier
        }
        if hasImportedIdentifierMatch == false {
            activeEntries.append(embeddedEntry)
        }
        return activeEntries
    }

    nonisolated private func score(
        _ entry: DeploymentAppleHardwareCatalogEntry,
        device: DeploymentDevice,
        derivedHardwareInfo: DeploymentDerivedHardwareInfo?,
        abmSnapshot: AppleBusinessDeviceSnapshot?,
        jamfSnapshot: JamfInventoryDeviceSnapshot?,
        vendorModel: String?
    ) -> (entry: DeploymentAppleHardwareCatalogEntry, score: Double, matchedFields: [String]) {
        var score = 0.0
        var matchedFields: [String] = []

        addMatch(
            lhs: abmSnapshot?.abmPartNumber,
            rhs: entry.applePartNumber,
            weight: 0.36,
            field: "abmPartNumber",
            score: &score,
            matchedFields: &matchedFields
        )
        addMatch(
            lhs: device.applePartNumber,
            rhs: entry.applePartNumber,
            weight: 0.32,
            field: "applePartNumber",
            score: &score,
            matchedFields: &matchedFields
        )
        addMatch(
            lhs: device.modelIdentifier ?? derivedHardwareInfo?.modelIdentifier,
            rhs: entry.modelIdentifier,
            weight: 0.30,
            field: "modelIdentifier",
            score: &score,
            matchedFields: &matchedFields
        )
        addMatch(
            lhs: device.orderNumber,
            rhs: entry.orderPartNumber,
            weight: 0.18,
            field: "orderPartNumber",
            score: &score,
            matchedFields: &matchedFields
        )
        addMatch(
            lhs: device.vendorSku,
            rhs: entry.vendorSku,
            weight: 0.18,
            field: "vendorSku",
            score: &score,
            matchedFields: &matchedFields
        )
        addMatch(
            lhs: abmSnapshot?.abmModel,
            rhs: entry.marketingName,
            weight: 0.16,
            field: "abmModel",
            score: &score,
            matchedFields: &matchedFields
        )
        addMatch(
            lhs: jamfModelName(from: jamfSnapshot),
            rhs: entry.marketingName,
            weight: 0.12,
            field: "jamfModel",
            score: &score,
            matchedFields: &matchedFields
        )
        addMatch(
            lhs: vendorModel,
            rhs: entry.marketingName,
            weight: 0.10,
            field: "vendorModel",
            score: &score,
            matchedFields: &matchedFields
        )

        if entry.sourceType == Self.embeddedCatalogSourceType,
           normalized(device.modelIdentifier ?? derivedHardwareInfo?.modelIdentifier) == normalized(entry.modelIdentifier) {
            score += 0.50
            matchedFields.append("embeddedAppleModelCatalog")
        }

        return (entry, min(score, 1.0), matchedFields)
    }

    nonisolated private func matchState(
        for result: (entry: DeploymentAppleHardwareCatalogEntry, score: Double, matchedFields: [String])
    ) -> DeploymentAppleCatalogMatchState {
        let exactIdentifierFields = Set(["abmPartNumber", "applePartNumber", "appleModelNumber", "modelIdentifier", "orderPartNumber"])
        let hasExactIdentifierMatch = result.matchedFields.contains { exactIdentifierFields.contains($0) }
        let hasCorroboratingMatch = result.matchedFields.count > 1 || result.score >= 0.80

        if hasExactIdentifierMatch && hasCorroboratingMatch {
            return .exact
        }
        if result.score >= 0.80 {
            return .highConfidence
        }
        return .partial
    }

    nonisolated private func addMatch(
        lhs: String?,
        rhs: String?,
        weight: Double,
        field: String,
        score: inout Double,
        matchedFields: inout [String]
    ) {
        guard let lhs = normalized(lhs), let rhs = normalized(rhs) else {
            return
        }
        if lhs == rhs {
            score += weight
            matchedFields.append(field)
        } else if lhs.contains(rhs) || rhs.contains(lhs) {
            score += weight * 0.55
            matchedFields.append(field)
        }
    }

    nonisolated private func normalized(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return normalizedValue.isEmpty ? nil : normalizedValue
    }

    nonisolated private func jamfModelName(from snapshot: JamfInventoryDeviceSnapshot?) -> String? {
        guard let snapshot else {
            return nil
        }
        let hardwareInfo = hardwareDerivationService.derive(from: snapshot.payloadSummary)
        return hardwareInfo.model
    }

    nonisolated private func embeddedCatalogEntryId(for modelIdentifier: String) -> String {
        "deployment-tracker-embedded-apple-\(modelIdentifier.lowercased().replacingOccurrences(of: ",", with: "-"))"
    }

    nonisolated private func deviceFamily(for modelIdentifier: String, marketingName: String) -> String {
        if modelIdentifier.hasPrefix("iPhone") || marketingName.localizedCaseInsensitiveContains("iPhone") {
            return "iPhone"
        }
        if modelIdentifier.hasPrefix("iPad") || marketingName.localizedCaseInsensitiveContains("iPad") {
            return "iPad"
        }
        return "Apple"
    }

    nonisolated private func deviceType(for modelIdentifier: String) -> String {
        if modelIdentifier.hasPrefix("iPhone") || modelIdentifier.hasPrefix("iPad") {
            return "Mobile Device"
        }
        return "Apple Device"
    }

    nonisolated private func chipFamily(from chipName: String) -> String {
        chipName
            .replacingOccurrences(of: "Apple ", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private func memoryDescription(
        for info: DeploymentAppleDeviceModelInfo,
        capacityMb: Int?
    ) -> String? {
        if let ram = info.ramGB(capacityMb) {
            return "\(ram) GB"
        }
        return "Storage-dependent RAM tier"
    }

    nonisolated private func hardwareCoreSummary(for info: DeploymentAppleDeviceModelInfo) -> String? {
        var parts: [String] = []
        if let cpu = info.cpuCoreCount {
            parts.append("\(cpu)-core CPU")
        }
        if let gpu = info.gpuCoreCount {
            parts.append("\(gpu)-core GPU")
        }
        if let neural = info.neuralCoreCount {
            parts.append("\(neural)-core Neural Engine")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " / ")
    }
}
