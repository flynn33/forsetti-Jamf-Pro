import Foundation

// "Klatu-barada-Nikto"

/// Pure, Metal-free derivation of everything `ComputerHardwareInfoCard` renders.
///
/// The card is presentation only; its business logic — storage fraction, battery
/// applicability, memory/spec resolution, and the catalog confidence label —
/// lives here so it can be unit-tested without SwiftUI or Metal, satisfying the
/// "specs must work without Metal" contract. Numbers always come from inventory
/// (`ComputerRecord`); the catalog only fills gaps and adds a confidence label,
/// so the card never claims a spec it can't substantiate.
nonisolated struct ComputerHardwareVisualizationModel: Equatable, Sendable {

    /// Battery panel state. Desktops are `.notApplicable`; portables (or Macs of
    /// undetermined form factor) with no reported figure are `.notReported`.
    enum BatteryState: Equatable, Sendable {
        case reported(percent: Int)
        case notApplicable
        case notReported
    }

    /// Catalog match (high confidence) or low-confidence derivation, nil when the
    /// model can't be identified at all.
    let modelInfo: AppleMacModelInfo?

    let marketingName: String
    let chipName: String?

    /// Exact core counts where a single configuration is known (inventory-reported
    /// CPU, or a pinned catalog/chip value). Left `nil` for binned SKUs so numeric
    /// consumers never receive a guessed exact — the card reads the `*Display`
    /// strings below, which carry the honest range instead.
    let cpuCoreCount: Int?
    let gpuCoreCount: Int?
    let neuralCoreCount: Int?

    /// Display strings for the card's spec row: an exact count when known, else the
    /// chip family's range (e.g. "30 or 38"), else `nil`. These keep CPU / GPU /
    /// Neural from showing blank on any Apple Silicon Mac.
    let cpuCoresDisplay: String?
    let gpuCoresDisplay: String?
    let neuralCoresDisplay: String?

    /// Installed RAM formatted as "16.0 GB" / "512 MB", inventory first then the
    /// catalog hint, nil when neither is known.
    let memoryDisplay: String?

    /// Boot-volume used fraction 0...1 (capacity/free first, then the reported
    /// percentage), nil when storage isn't reported.
    let storageUsedFraction: Double?

    /// Whether this Mac is treated as a portable for battery applicability. nil
    /// when the form factor can't be determined.
    let isPortable: Bool?

    let batteryState: BatteryState

    /// Confidence sentence for the card footer, nil when there's no catalog match.
    let confidenceText: String?

    init(record: ComputerRecord) {
        let info = AppleMacModelCatalog.info(
            forModelIdentifier: record.modelIdentifier,
            reportedModel: record.model,
            processorType: record.processorType,
            ramMB: record.totalRamMb
        )
        self.modelInfo = info

        self.marketingName = info?.marketingName
            ?? record.model
            ?? record.modelIdentifier
            ?? "Unknown Mac"
        let resolvedChipName = info?.chipName ?? record.processorType
        self.chipName = resolvedChipName

        // Fill gaps from the chip-family table so Apple Silicon Macs never show a
        // blank core count, even when the exact model identifier isn't catalogued.
        // Inventory-reported CPU wins; a reported 0 is treated as "not reported".
        let chipSpec = AppleMacModelCatalog.chipSpec(forChipName: resolvedChipName)
        let reportedCPU: Int? = (record.coreCount ?? 0) > 0 ? record.coreCount : nil
        let resolvedCPU = reportedCPU ?? info?.cpuCoreCount ?? chipSpec?.cpuCoreCount
        let resolvedGPU = info?.gpuCoreCount ?? chipSpec?.gpuCoreCount
        let resolvedNeural = info?.neuralCoreCount ?? chipSpec?.neuralCoreCount
        self.cpuCoreCount = resolvedCPU
        self.gpuCoreCount = resolvedGPU
        self.neuralCoreCount = resolvedNeural
        self.cpuCoresDisplay = resolvedCPU.map { "\($0)" } ?? chipSpec?.cpuCoreDescription
        self.gpuCoresDisplay = resolvedGPU.map { "\($0)" } ?? chipSpec?.gpuCoreDescription
        self.neuralCoresDisplay = resolvedNeural.map { "\($0)" }

        self.memoryDisplay = {
            if let ramMb = record.totalRamMb, ramMb > 0 {
                return Self.format(megabytes: ramMb)
            }
            if let ramGB = info?.ramGB {
                return "\(ramGB) GB"
            }
            return nil
        }()

        self.storageUsedFraction = {
            if let total = record.totalStorageMb, total > 0,
               let free = record.bootDriveAvailableMb
            {
                let used = max(0, total - free)
                return min(1.0, max(0.0, Double(used) / Double(total)))
            }
            if let percent = record.storageUsedPercentage {
                return Double(min(100, max(0, percent))) / 100.0
            }
            return nil
        }()

        let resolvedPortable: Bool? = {
            if record.batteryCapacityPercent != nil { return true }
            if let known = info?.isPortable { return known }
            return AppleMacModelCatalog.inferPortable(
                modelIdentifier: record.modelIdentifier,
                reportedModel: record.model
            )
        }()
        self.isPortable = resolvedPortable

        self.batteryState = {
            if let capacity = record.batteryCapacityPercent {
                return .reported(percent: capacity)
            }
            if resolvedPortable == false {
                return .notApplicable
            }
            return .notReported
        }()

        self.confidenceText = info.map { Self.confidenceText(for: $0) }
    }

    /// Confidence sentence shown in the card footer. Low confidence is phrased so
    /// the card never presents a derived spec as verified fact.
    nonisolated static func confidenceText(for info: AppleMacModelInfo) -> String {
        let sources = info.sourceFieldsUsed.joined(separator: ", ")
        switch info.confidence {
        case .exact:
            return "Verified specs (source: \(sources))."
        case .high:
            return "High confidence — matched model identifier."
        case .medium:
            return "Medium confidence — partial match (source: \(sources))."
        case .low:
            return "Low confidence — derived from reported model; specs may be approximate."
        case .unknown:
            return "Hardware details unavailable."
        }
    }

    /// Formats megabyte values as "47 GB" (≥ 1 GB) or "512 MB" (smaller),
    /// dividing by 1024. Matches the mobile hardware card.
    nonisolated static func format(megabytes: Int) -> String {
        if megabytes >= 1024 {
            let gb = Double(megabytes) / 1024.0
            return gb >= 100
                ? "\(Int(gb.rounded())) GB"
                : String(format: "%.1f GB", gb)
        } else {
            return "\(megabytes) MB"
        }
    }
}
