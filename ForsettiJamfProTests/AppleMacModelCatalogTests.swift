import XCTest
@testable import ForsettiJamfProApp

/// Coverage for `AppleMacModelCatalog`: exact catalog hits for known Apple
/// Silicon Macs, the low-confidence derivation path for unknown identifiers, the
/// rule that ambiguous (binned) core counts stay nil, and portability inference.
final class AppleMacModelCatalogTests: XCTestCase {

    // MARK: - Known identifier (high confidence)

    func test_info_knownProMaxIdentifier_returnsHighConfidenceWithoutGuessingCores() {
        let info = AppleMacModelCatalog.info(forModelIdentifier: "Mac14,5")

        XCTAssertEqual(info?.marketingName, "MacBook Pro (14-inch, 2023)")
        XCTAssertEqual(info?.chipName, "Apple M2 Max")
        XCTAssertEqual(info?.confidence, .high)
        XCTAssertEqual(info?.isPortable, true)
        // M2 Max ships binned CPU/GPU SKUs under one identifier — must not guess.
        XCTAssertNil(info?.cpuCoreCount)
        XCTAssertNil(info?.gpuCoreCount)
        // Neural Engine is a stable 16 cores across the M-series (non-Ultra).
        XCTAssertEqual(info?.neuralCoreCount, 16)
        XCTAssertEqual(info?.sourceFieldsUsed, ["hardware.modelIdentifier"])
    }

    func test_info_baseChipIdentifier_populatesUnambiguousCores() {
        let info = AppleMacModelCatalog.info(forModelIdentifier: "Mac14,7")

        XCTAssertEqual(info?.marketingName, "MacBook Pro (13-inch, M2, 2022)")
        XCTAssertEqual(info?.chipName, "Apple M2")
        XCTAssertEqual(info?.cpuCoreCount, 8)
        XCTAssertEqual(info?.gpuCoreCount, 10)
        XCTAssertEqual(info?.neuralCoreCount, 16)
        XCTAssertEqual(info?.confidence, .high)
    }

    func test_info_ultraIdentifier_reportsThirtyTwoCoreNeuralEngineAndDesktop() {
        let info = AppleMacModelCatalog.info(forModelIdentifier: "Mac14,14")

        XCTAssertEqual(info?.marketingName, "Mac Studio (2023)")
        XCTAssertEqual(info?.chipName, "Apple M2 Ultra")
        XCTAssertEqual(info?.neuralCoreCount, 32)
        XCTAssertEqual(info?.isPortable, false)
    }

    func test_info_desktopIdentifiers_areNotPortable() {
        XCTAssertEqual(AppleMacModelCatalog.info(forModelIdentifier: "Macmini9,1")?.isPortable, false)
        XCTAssertEqual(AppleMacModelCatalog.info(forModelIdentifier: "iMac21,1")?.isPortable, false)
    }

    func test_info_trimsWhitespaceBeforeLookup() {
        let info = AppleMacModelCatalog.info(forModelIdentifier: "  Mac14,5  ")
        XCTAssertEqual(info?.marketingName, "MacBook Pro (14-inch, 2023)")
    }

    func test_info_knownIdentifierWins_evenWithBlankReportedModel() {
        let info = AppleMacModelCatalog.info(
            forModelIdentifier: "Mac14,3",
            reportedModel: "",
            processorType: ""
        )
        XCTAssertEqual(info?.marketingName, "Mac mini (M2, 2023)")
        XCTAssertEqual(info?.confidence, .high)
    }

    // MARK: - Unknown identifier (low-confidence derivation)

    func test_info_unknownIdentifierWithReportedModel_derivesLowConfidence() {
        let info = AppleMacModelCatalog.info(
            forModelIdentifier: "Mac99,9",
            reportedModel: "MacBook Pro",
            processorType: "Apple M5",
            ramMB: 32_768
        )

        XCTAssertEqual(info?.marketingName, "MacBook Pro")
        XCTAssertEqual(info?.chipName, "Apple M5")
        XCTAssertEqual(info?.confidence, .low)
        XCTAssertEqual(info?.isPortable, true)
        XCTAssertEqual(info?.ramGB, 32)
        XCTAssertEqual(
            info?.sourceFieldsUsed,
            ["hardware.model", "hardware.processorType", "hardware.totalRamMegabytes"]
        )
    }

    func test_info_lowConfidenceDerivation_doesNotFabricateCoreCounts() {
        let info = AppleMacModelCatalog.info(
            forModelIdentifier: "Mac99,9",
            reportedModel: "Mac mini",
            processorType: "Apple M5 Pro"
        )

        XCTAssertEqual(info?.confidence, .low)
        XCTAssertNil(info?.cpuCoreCount)
        XCTAssertNil(info?.gpuCoreCount)
        XCTAssertNil(info?.neuralCoreCount)
        XCTAssertEqual(info?.isPortable, false) // "Mac mini" → desktop
    }

    func test_info_unknownIdentifierWithNoModel_returnsNil() {
        XCTAssertNil(AppleMacModelCatalog.info(forModelIdentifier: "Totally,Unknown"))
        XCTAssertNil(AppleMacModelCatalog.info(forModelIdentifier: nil))
        XCTAssertNil(AppleMacModelCatalog.info(forModelIdentifier: "   "))
    }

    // MARK: - Portability inference

    func test_inferPortable_classifiesByFormFactor() {
        XCTAssertEqual(AppleMacModelCatalog.inferPortable(reportedModel: "MacBook Air"), true)
        XCTAssertEqual(AppleMacModelCatalog.inferPortable(reportedModel: "MacBook Pro"), true)
        XCTAssertEqual(AppleMacModelCatalog.inferPortable(reportedModel: "iMac"), false)
        XCTAssertEqual(AppleMacModelCatalog.inferPortable(reportedModel: "Mac mini"), false)
        XCTAssertEqual(AppleMacModelCatalog.inferPortable(reportedModel: "Mac Studio"), false)
        XCTAssertEqual(AppleMacModelCatalog.inferPortable(reportedModel: "Mac Pro"), false)
    }

    func test_inferPortable_returnsNilWhenUndeterminable() {
        // A bare numeric identifier carries no form-factor signal.
        XCTAssertNil(AppleMacModelCatalog.inferPortable(modelIdentifier: "Mac14,5"))
        XCTAssertNil(AppleMacModelCatalog.inferPortable())
    }

    // MARK: - Chip-family spec table

    func test_chipSpec_binnedM2Max_pinsCpuNeuralAndRangesGpu() {
        let spec = AppleMacModelCatalog.chipSpec(forChipName: "Apple M2 Max")

        XCTAssertEqual(spec?.cpuCoreCount, 12)
        XCTAssertNil(spec?.cpuCoreDescription)
        XCTAssertNil(spec?.gpuCoreCount)            // binned — range only
        XCTAssertEqual(spec?.gpuCoreDescription, "30 or 38")
        XCTAssertEqual(spec?.neuralCoreCount, 16)
    }

    func test_chipSpec_m3Pro_hasNoCatalogEntryButResolvesRanges() {
        let spec = AppleMacModelCatalog.chipSpec(forChipName: "Apple M3 Pro")

        XCTAssertNil(spec?.cpuCoreCount)
        XCTAssertEqual(spec?.cpuCoreDescription, "11 or 12")
        XCTAssertEqual(spec?.gpuCoreDescription, "14 or 18")
        XCTAssertEqual(spec?.neuralCoreCount, 16)
    }

    func test_chipSpec_ultra_reportsThirtyTwoCoreNeural() {
        XCTAssertEqual(AppleMacModelCatalog.chipSpec(forChipName: "Apple M1 Ultra")?.neuralCoreCount, 32)
        XCTAssertEqual(AppleMacModelCatalog.chipSpec(forChipName: "Apple M2 Ultra")?.neuralCoreCount, 32)
    }

    func test_chipSpec_m4_isCovered() {
        let spec = AppleMacModelCatalog.chipSpec(forChipName: "Apple M4")
        XCTAssertEqual(spec?.cpuCoreDescription, "up to 10")
        XCTAssertEqual(spec?.neuralCoreCount, 16)
    }

    /// Longest-key-first matching: the base "M2" must not swallow "M2 Max".
    func test_chipSpec_baseChipDoesNotMatchBinnedVariant() {
        let base = AppleMacModelCatalog.chipSpec(forChipName: "Apple M2")
        XCTAssertEqual(base?.cpuCoreCount, 8)
        XCTAssertEqual(base?.gpuCoreDescription, "8 or 10")
    }

    func test_chipSpec_isCaseInsensitiveAndStripsApplePrefixAndWhitespace() {
        let lower = AppleMacModelCatalog.chipSpec(forChipName: "apple m2 max")
        let padded = AppleMacModelCatalog.chipSpec(forChipName: "  Apple   M2 Max  ")
        XCTAssertEqual(lower?.gpuCoreDescription, "30 or 38")
        XCTAssertEqual(padded?.gpuCoreDescription, "30 or 38")
    }

    func test_chipSpec_intelAndUnknownReturnNil() {
        XCTAssertNil(AppleMacModelCatalog.chipSpec(forChipName: "Intel Core i7"))
        XCTAssertNil(AppleMacModelCatalog.chipSpec(forChipName: "Apple"))
        XCTAssertNil(AppleMacModelCatalog.chipSpec(forChipName: ""))
        XCTAssertNil(AppleMacModelCatalog.chipSpec(forChipName: nil))
    }

    // MARK: - Catalog integrity

    func test_entries_coverCuratedAppleSiliconRange() {
        XCTAssertGreaterThanOrEqual(AppleMacModelCatalog.entries.count, 25)
        for identifier in ["MacBookAir10,1", "MacBookPro17,1", "Mac14,5", "Mac14,10", "Mac15,3", "Mac14,8"] {
            XCTAssertNotNil(AppleMacModelCatalog.entries[identifier], "missing catalog entry for \(identifier)")
        }
    }

    func test_entries_allCarryModelIdentifierSource() {
        for (identifier, info) in AppleMacModelCatalog.entries {
            XCTAssertEqual(
                info.sourceFieldsUsed, ["hardware.modelIdentifier"],
                "entry \(identifier) should attribute its source to the model identifier"
            )
            XCTAssertEqual(info.confidence, .high, "catalog entry \(identifier) should be high confidence")
            XCTAssertFalse(info.marketingName.isEmpty)
        }
    }
}

//endofline
