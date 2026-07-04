import Foundation

// "End of Line"

/// Resolved hardware information for a Mac, derived from its `modelIdentifier`
/// (e.g. `Mac14,5`) with optional help from the inventory-reported model string
/// and processor type.
///
/// Mirrors `AppleDeviceModelInfo` (iPhone/iPad) but adds a `confidence` label and
/// a `sourceFieldsUsed` audit trail. The distinction matters for Macs because a
/// single `modelIdentifier` can cover several binned CPU/GPU configurations, so
/// the catalog deliberately leaves `cpuCoreCount` / `gpuCoreCount` `nil` whenever
/// the identifier alone can't pin the exact value. The hardware card then shows
/// the live inventory-reported core count instead of guessing — honoring the
/// rule that we never claim exact specs we can't substantiate.
nonisolated struct AppleMacModelInfo: Sendable, Hashable {
    /// How much to trust the resolved specs.
    /// - `exact`: every field verified for the unit (unused today — reserved).
    /// - `high`: matched a curated `modelIdentifier` entry; marketing name, chip
    ///   family, portability, and release year are authoritative. Core counts are
    ///   only populated where the identifier admits a single configuration.
    /// - `medium`: partial match (reserved for future heuristics).
    /// - `low`: derived from the reported model / processor strings, not a catalog
    ///   hit. Treat specs as approximate.
    /// - `unknown`: nothing usable.
    enum Confidence: String, Sendable, Hashable {
        case exact, high, medium, low, unknown
    }

    /// Marketing name (e.g. "MacBook Pro (14-inch, 2023)").
    let marketingName: String

    /// Apple chip name (e.g. "Apple M2 Max"), when known.
    let chipName: String?

    /// CPU core count where the identifier admits a single configuration, else nil.
    let cpuCoreCount: Int?

    /// GPU core count where the identifier admits a single configuration, else nil.
    let gpuCoreCount: Int?

    /// Neural Engine core count. Stable per chip family (16 on M1-M4, 32 on Ultra).
    let neuralCoreCount: Int?

    /// Static RAM hint in GB. Usually nil — installed RAM is read live from
    /// inventory (`hardware.totalRamMegabytes`); this only carries a value on the
    /// low-confidence derivation path where we convert a reported MB figure.
    let ramGB: Int?

    /// Whether the model is a portable (has a battery). Desktops are `false`,
    /// `nil` when undetermined.
    let isPortable: Bool?

    /// Apple's release year for the model, when known.
    let releaseYear: Int?

    /// How much to trust the above.
    let confidence: Confidence

    /// The inventory field keys that contributed to this resolution, for the
    /// card's "source" label and for debugging schema drift.
    let sourceFieldsUsed: [String]
}

/// Core-count facts for an Apple Silicon chip family.
///
/// Core counts are a property of the chip, not the binned SKU: every "Apple M2
/// Max" is a 12-core CPU with a 16-core Neural Engine — only the GPU is binned
/// (30 or 38 cores). Keyed on the reported `processorType`, this table lets the
/// hardware card fill CPU / GPU / Neural even when the exact `modelIdentifier`
/// isn't in `AppleMacModelCatalog.entries` (M3 Pro/Max, M4, anything newer than
/// the table), surfacing an honest range string for binned values instead of a
/// blank. All values are public Apple specifications.
nonisolated struct AppleSiliconChipSpec: Sendable, Hashable {
    /// CPU cores when fixed across the chip's SKUs, else nil (binned).
    let cpuCoreCount: Int?
    /// Range string when the CPU is binned (e.g. "10 or 12"), else nil. Shown
    /// under a "CPU Cores" caption, so it carries no "-core" suffix.
    let cpuCoreDescription: String?
    /// GPU cores when fixed, else nil (binned).
    let gpuCoreCount: Int?
    /// Range string when the GPU is binned (e.g. "30 or 38"), else nil.
    let gpuCoreDescription: String?
    /// Neural Engine cores — always known per family (16 on M1–M4, 32 on Ultra),
    /// so an Apple Silicon Mac never shows a blank Neural count.
    let neuralCoreCount: Int
}

/// Local lookup table mapping Mac `modelIdentifier` to marketing/spec metadata.
///
/// Contents are public Apple facts only — no tenant- or fleet-specific values —
/// so the catalog stays a reusable framework component. Coverage focuses on
/// Apple Silicon Macs (M1 onward), the platform the fleet is standardizing on.
/// Unknown identifiers fall back to a low-confidence derivation from the
/// reported model string, and finally to `nil` so the card shows the raw values.
///
/// Refresh cadence: add a new entry when Apple ships hardware. Where a chip has
/// binned CPU/GPU SKUs under one identifier (every Pro/Max/Ultra, and the base
/// MacBook Air GPU), leave those counts `nil` rather than guess.
enum AppleMacModelCatalog {

    // MARK: - Lookup

    /// Resolves hardware metadata for a Mac.
    ///
    /// Resolution order:
    /// 1. Exact `modelIdentifier` catalog hit → `.high` confidence.
    /// 2. No hit but a reported model string is available → `.low`-confidence
    ///    derivation using the reported model as the marketing name and the
    ///    processor type as the chip name.
    /// 3. Nothing usable → `nil`.
    ///
    /// - Parameters:
    ///   - identifier: `hardware.modelIdentifier` (e.g. "Mac14,5").
    ///   - reportedModel: `hardware.model` (e.g. "MacBook Pro").
    ///   - processorType: `hardware.processorType` (e.g. "Apple M2 Max").
    ///   - ramMB: `hardware.totalRamMegabytes`, used only to derive an approximate
    ///     GB figure on the low-confidence path.
    nonisolated static func info(
        forModelIdentifier identifier: String?,
        reportedModel: String? = nil,
        processorType: String? = nil,
        ramMB: Int? = nil
    ) -> AppleMacModelInfo? {
        if let id = identifier?.trimmingCharacters(in: .whitespacesAndNewlines),
           id.isEmpty == false,
           let entry = entries[id]
        {
            return entry
        }

        let trimmedModel = reportedModel?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedProcessor = processorType?.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let model = trimmedModel, model.isEmpty == false else {
            return nil
        }

        var sources = ["hardware.model"]
        let chip: String?
        if let processor = trimmedProcessor, processor.isEmpty == false {
            chip = processor
            sources.append("hardware.processorType")
        } else {
            chip = nil
        }

        var derivedRamGB: Int?
        if let ramMB, ramMB > 0 {
            derivedRamGB = Int((Double(ramMB) / 1024.0).rounded())
            sources.append("hardware.totalRamMegabytes")
        }

        return AppleMacModelInfo(
            marketingName: model,
            chipName: chip,
            cpuCoreCount: nil,
            gpuCoreCount: nil,
            neuralCoreCount: nil,
            ramGB: derivedRamGB,
            isPortable: inferPortable(modelIdentifier: identifier, reportedModel: model),
            releaseYear: nil,
            confidence: .low,
            sourceFieldsUsed: sources
        )
    }

    /// Best-effort portability guess from the identifier / reported model strings.
    /// Returns `nil` when the form factor can't be determined (e.g. a bare
    /// "Mac14,5" identifier with no model string) so callers don't render a
    /// misleading "Not applicable" battery state.
    nonisolated static func inferPortable(
        modelIdentifier: String? = nil,
        reportedModel: String? = nil
    ) -> Bool? {
        let haystack = [modelIdentifier, reportedModel]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")

        guard haystack.isEmpty == false else {
            return nil
        }

        if haystack.contains("macbook") {
            return true
        }
        if haystack.contains("imac")
            || haystack.contains("mac mini") || haystack.contains("macmini")
            || haystack.contains("mac studio") || haystack.contains("macstudio")
            || haystack.contains("mac pro") || haystack.contains("macpro")
        {
            return false
        }
        return nil
    }

    // MARK: - Lookup table

    /// Convenience for entries whose CPU/GPU/Neural counts are unambiguous for the
    /// identifier (the base M-series chips). Always `.high` confidence, portable.
    nonisolated private static func portable(
        _ name: String, _ chip: String, year: Int,
        cpu: Int? = nil, gpu: Int? = nil, neural: Int? = 16
    ) -> AppleMacModelInfo {
        .init(
            marketingName: name, chipName: chip,
            cpuCoreCount: cpu, gpuCoreCount: gpu, neuralCoreCount: neural,
            ramGB: nil, isPortable: true, releaseYear: year,
            confidence: .high, sourceFieldsUsed: ["hardware.modelIdentifier"]
        )
    }

    /// Desktop counterpart of `portable(...)`.
    nonisolated private static func desktop(
        _ name: String, _ chip: String, year: Int,
        cpu: Int? = nil, gpu: Int? = nil, neural: Int? = 16
    ) -> AppleMacModelInfo {
        .init(
            marketingName: name, chipName: chip,
            cpuCoreCount: cpu, gpuCoreCount: gpu, neuralCoreCount: neural,
            ramGB: nil, isPortable: false, releaseYear: year,
            confidence: .high, sourceFieldsUsed: ["hardware.modelIdentifier"]
        )
    }

    nonisolated static let entries: [String: AppleMacModelInfo] = [

        // MARK: MacBook Air (Apple Silicon)
        // Base M-series: CPU is a fixed 8 cores, but the GPU is binned (7 vs 8 on
        // M1; 8 vs 10 on the 13-inch M2/M3) so GPU stays nil for 13-inch models.
        // The 15-inch M2/M3 Air ships a single 10-core GPU, so it's pinned.
        "MacBookAir10,1": portable("MacBook Air (M1, 2020)", "Apple M1", year: 2020, cpu: 8),
        "Mac14,2": portable("MacBook Air (13-inch, M2, 2022)", "Apple M2", year: 2022, cpu: 8),
        "Mac14,15": portable("MacBook Air (15-inch, M2, 2023)", "Apple M2", year: 2023, cpu: 8, gpu: 10),
        "Mac15,12": portable("MacBook Air (13-inch, M3, 2024)", "Apple M3", year: 2024, cpu: 8),
        "Mac15,13": portable("MacBook Air (15-inch, M3, 2024)", "Apple M3", year: 2024, cpu: 8, gpu: 10),

        // MARK: MacBook Pro 13-inch (Apple Silicon)
        "MacBookPro17,1": portable("MacBook Pro (13-inch, M1, 2020)", "Apple M1", year: 2020, cpu: 8, gpu: 8),
        "Mac14,7": portable("MacBook Pro (13-inch, M2, 2022)", "Apple M2", year: 2022, cpu: 8, gpu: 10),

        // MARK: MacBook Pro 14-inch / 16-inch (Pro / Max — binned CPU+GPU → nil)
        "MacBookPro18,3": portable("MacBook Pro (14-inch, 2021)", "Apple M1 Pro", year: 2021),
        "MacBookPro18,4": portable("MacBook Pro (14-inch, 2021)", "Apple M1 Max", year: 2021),
        "MacBookPro18,1": portable("MacBook Pro (16-inch, 2021)", "Apple M1 Pro", year: 2021),
        "MacBookPro18,2": portable("MacBook Pro (16-inch, 2021)", "Apple M1 Max", year: 2021),
        "Mac14,9": portable("MacBook Pro (14-inch, 2023)", "Apple M2 Pro", year: 2023),
        "Mac14,5": portable("MacBook Pro (14-inch, 2023)", "Apple M2 Max", year: 2023),
        "Mac14,10": portable("MacBook Pro (16-inch, 2023)", "Apple M2 Pro", year: 2023),
        "Mac14,6": portable("MacBook Pro (16-inch, 2023)", "Apple M2 Max", year: 2023),
        // Base M3 14-inch ships a single 8-core CPU / 10-core GPU configuration.
        "Mac15,3": portable("MacBook Pro (14-inch, Nov 2023)", "Apple M3", year: 2023, cpu: 8, gpu: 10),

        // MARK: Mac mini (Apple Silicon)
        "Macmini9,1": desktop("Mac mini (M1, 2020)", "Apple M1", year: 2020, cpu: 8, gpu: 8),
        "Mac14,3": desktop("Mac mini (M2, 2023)", "Apple M2", year: 2023, cpu: 8, gpu: 10),
        "Mac14,12": desktop("Mac mini (M2 Pro, 2023)", "Apple M2 Pro", year: 2023),

        // MARK: iMac 24-inch (Apple Silicon — GPU binned → nil)
        "iMac21,1": desktop("iMac (24-inch, M1, 2021)", "Apple M1", year: 2021, cpu: 8),
        "iMac21,2": desktop("iMac (24-inch, M1, 2021)", "Apple M1", year: 2021, cpu: 8),
        "Mac15,4": desktop("iMac (24-inch, M3, 2023)", "Apple M3", year: 2023, cpu: 8),
        "Mac15,5": desktop("iMac (24-inch, M3, 2023)", "Apple M3", year: 2023, cpu: 8),

        // MARK: Mac Studio / Mac Pro (Max / Ultra — binned → nil; Ultra Neural = 32)
        "Mac13,1": desktop("Mac Studio (2022)", "Apple M1 Max", year: 2022),
        "Mac13,2": desktop("Mac Studio (2022)", "Apple M1 Ultra", year: 2022, neural: 32),
        "Mac14,13": desktop("Mac Studio (2023)", "Apple M2 Max", year: 2023),
        "Mac14,14": desktop("Mac Studio (2023)", "Apple M2 Ultra", year: 2023, neural: 32),
        "Mac14,8": desktop("Mac Pro (2023)", "Apple M2 Ultra", year: 2023, neural: 32)
    ]

    // MARK: - Chip-family spec table

    /// Convenience constructor for a `chipSpecs` row.
    nonisolated private static func chip(
        cpu: Int? = nil, cpuDesc: String? = nil,
        gpu: Int? = nil, gpuDesc: String? = nil,
        neural: Int
    ) -> AppleSiliconChipSpec {
        .init(
            cpuCoreCount: cpu, cpuCoreDescription: cpuDesc,
            gpuCoreCount: gpu, gpuCoreDescription: gpuDesc,
            neuralCoreCount: neural
        )
    }

    /// Core counts keyed on a normalized chip name (lowercased, "apple" dropped).
    ///
    /// Public Apple specs. CPU/GPU are pinned where the chip ships a single
    /// configuration and given as an "x or y" range where the chip is binned; the
    /// Neural Engine is always known (16 on M1–M4, 32 on the Ultra parts). This is
    /// the fallback that keeps the hardware card from showing blank cores for any
    /// Apple Silicon Mac — including chips with no `entries` row (M3 Pro/Max, M4).
    nonisolated static let chipSpecs: [String: AppleSiliconChipSpec] = [
        "m1":        chip(cpu: 8,             gpuDesc: "7 or 8",   neural: 16),
        "m1 pro":    chip(cpuDesc: "8 or 10", gpuDesc: "14 or 16", neural: 16),
        "m1 max":    chip(cpu: 10,            gpuDesc: "24 or 32", neural: 16),
        "m1 ultra":  chip(cpu: 20,            gpuDesc: "48 or 64", neural: 32),

        "m2":        chip(cpu: 8,              gpuDesc: "8 or 10",  neural: 16),
        "m2 pro":    chip(cpuDesc: "10 or 12", gpuDesc: "16 or 19", neural: 16),
        "m2 max":    chip(cpu: 12,             gpuDesc: "30 or 38", neural: 16),
        "m2 ultra":  chip(cpu: 24,             gpuDesc: "60 or 76", neural: 32),

        "m3":        chip(cpu: 8,              gpuDesc: "8 or 10",  neural: 16),
        "m3 pro":    chip(cpuDesc: "11 or 12", gpuDesc: "14 or 18", neural: 16),
        "m3 max":    chip(cpuDesc: "14 or 16", gpuDesc: "30 or 40", neural: 16),
        "m3 ultra":  chip(cpuDesc: "28 or 32", gpuDesc: "60 or 80", neural: 32),

        "m4":        chip(cpuDesc: "up to 10", gpuDesc: "up to 10", neural: 16),
        "m4 pro":    chip(cpuDesc: "12 or 14", gpuDesc: "16 or 20", neural: 16),
        "m4 max":    chip(cpuDesc: "14 or 16", gpuDesc: "32 or 40", neural: 16)
    ]

    /// Looks up chip-family core counts from a reported processor type.
    ///
    /// Normalizes the input (lowercase, strip a leading "Apple "), tries an exact
    /// key match, then falls back to a contains-scan over the keys ordered
    /// longest-first so "m2 max" wins over "m2". Returns `nil` for Intel or any
    /// unrecognized string, leaving the existing low-confidence path untouched.
    nonisolated static func chipSpec(forChipName chipName: String?) -> AppleSiliconChipSpec? {
        guard let raw = chipName?.trimmingCharacters(in: .whitespacesAndNewlines),
              raw.isEmpty == false
        else {
            return nil
        }

        let normalized = raw
            .lowercased()
            .split(separator: " ")
            .map(String.init)
            .filter { $0 != "apple" }
            .joined(separator: " ")

        guard normalized.isEmpty == false else {
            return nil
        }

        if let exact = chipSpecs[normalized] {
            return exact
        }

        for key in chipSpecs.keys.sorted(by: { $0.count > $1.count }) {
            if normalized.contains(key) {
                return chipSpecs[key]
            }
        }

        return nil
    }
}

//endofline
