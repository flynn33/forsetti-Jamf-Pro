import XCTest
@testable import Forsetti

/// Covers `ComputerHardwareVisualizationModel`, the pure value type behind
/// `ComputerHardwareInfoCard`. Everything the card renders — storage fraction,
/// battery applicability, memory/spec resolution, and the confidence label — is
/// derived here, with no SwiftUI or Metal, so it is verifiable in isolation. The
/// model proves the card never claims a spec it can't substantiate and never
/// shows a misleading "Not applicable" battery for an undetermined form factor.
final class ComputerHardwareVisualizationModelTests: XCTestCase {

    private func makeRecord(
        modelIdentifier: String? = nil,
        model: String? = nil,
        processorType: String? = nil,
        fieldValues: [String: String] = [:]
    ) -> ComputerRecord {
        var values = fieldValues
        if let processorType { values["hardware.processorType"] = processorType }
        return ComputerRecord(
            id: "1",
            computerName: "Mac",
            serialNumber: "C02TEST",
            model: model,
            modelIdentifier: modelIdentifier,
            fieldValues: values
        )
    }

    // MARK: - Storage fraction

    func test_storageFraction_fromCapacityAndFree() {
        let viz = ComputerHardwareVisualizationModel(record: makeRecord(fieldValues: [
            "storage.totalSizeMegabytes": "994662",
            "storage.bootDriveAvailableSpaceMegabytes": "248665"
        ]))

        let fraction = try? XCTUnwrap(viz.storageUsedFraction)
        XCTAssertEqual(fraction ?? -1, 0.75, accuracy: 0.005)
    }

    func test_storageFraction_clampsWhenFreeExceedsTotal() {
        let viz = ComputerHardwareVisualizationModel(record: makeRecord(fieldValues: [
            "storage.totalSizeMegabytes": "100000",
            "storage.bootDriveAvailableSpaceMegabytes": "120000"
        ]))

        XCTAssertEqual(viz.storageUsedFraction, 0.0)
    }

    func test_storageFraction_fallsBackToReportedPercentWhenNoCapacity() {
        let viz = ComputerHardwareVisualizationModel(record: makeRecord(fieldValues: [
            "storage.percentUsed": "73"
        ]))

        XCTAssertEqual(viz.storageUsedFraction ?? -1, 0.73, accuracy: 0.0001)
    }

    func test_storageFraction_nilWhenNothingReported() {
        let viz = ComputerHardwareVisualizationModel(record: makeRecord())
        XCTAssertNil(viz.storageUsedFraction)
    }

    // MARK: - Battery applicability

    func test_battery_reportedCapacityWins() {
        let viz = ComputerHardwareVisualizationModel(record: makeRecord(fieldValues: [
            "hardware.batteryCapacityPercent": "88"
        ]))

        XCTAssertEqual(viz.batteryState, .reported(percent: 88))
        XCTAssertEqual(viz.isPortable, true)
    }

    func test_battery_desktopIsNotApplicable() {
        let viz = ComputerHardwareVisualizationModel(record: makeRecord(modelIdentifier: "Macmini9,1"))

        XCTAssertEqual(viz.isPortable, false)
        XCTAssertEqual(viz.batteryState, .notApplicable)
    }

    func test_battery_portableWithoutFigureIsNotReported() {
        let viz = ComputerHardwareVisualizationModel(record: makeRecord(modelIdentifier: "Mac14,7"))

        XCTAssertEqual(viz.isPortable, true)
        XCTAssertEqual(viz.batteryState, .notReported)
    }

    /// The important guard: an undetermined form factor must NOT render "Not
    /// applicable" — it falls through to "Battery not reported".
    func test_battery_undeterminedFormFactorIsNotReportedNotNotApplicable() {
        let viz = ComputerHardwareVisualizationModel(record: makeRecord(modelIdentifier: "Zztop,9"))

        XCTAssertNil(viz.isPortable)
        XCTAssertEqual(viz.batteryState, .notReported)
    }

    // MARK: - Memory display

    func test_memoryDisplay_fromInventoryMegabytes() {
        let viz = ComputerHardwareVisualizationModel(record: makeRecord(fieldValues: [
            "hardware.totalRamMegabytes": "32768"
        ]))

        XCTAssertEqual(viz.memoryDisplay, "32.0 GB")
    }

    func test_memoryDisplay_nilWhenInventoryAbsentAndCatalogHasNoHint() {
        // A curated catalog entry carries no ramGB, and no RAM is in inventory.
        let viz = ComputerHardwareVisualizationModel(record: makeRecord(modelIdentifier: "Mac14,7"))
        XCTAssertNil(viz.memoryDisplay)
    }

    // MARK: - Cores & identity resolution

    func test_cpuCoreCount_inventoryWinsOverCatalog() {
        let viz = ComputerHardwareVisualizationModel(record: makeRecord(
            modelIdentifier: "Mac14,7",
            fieldValues: ["hardware.coreCount": "12"]
        ))

        XCTAssertEqual(viz.cpuCoreCount, 12)
    }

    func test_coresFromCatalogWhenInventoryAbsent() {
        let viz = ComputerHardwareVisualizationModel(record: makeRecord(modelIdentifier: "Mac14,7"))

        XCTAssertEqual(viz.cpuCoreCount, 8)
        XCTAssertEqual(viz.gpuCoreCount, 10)
        XCTAssertEqual(viz.neuralCoreCount, 16)
    }

    func test_coreDisplayStrings_exactCatalogEntryShowsPlainNumbers() {
        let viz = ComputerHardwareVisualizationModel(record: makeRecord(modelIdentifier: "Mac14,7"))

        XCTAssertEqual(viz.cpuCoresDisplay, "8")
        XCTAssertEqual(viz.gpuCoresDisplay, "10")
        XCTAssertEqual(viz.neuralCoresDisplay, "16")
    }

    /// A binned identifier (M2 Max) leaves GPU `nil` in the model catalog, but the
    /// chip-family table fills the CPU/Neural exacts and an honest GPU range, so
    /// the card never shows a blank core count.
    func test_chipFallback_fillsBinnedM2MaxFromChipTable() {
        let viz = ComputerHardwareVisualizationModel(record: makeRecord(modelIdentifier: "Mac14,5"))

        XCTAssertEqual(viz.cpuCoreCount, 12)
        XCTAssertNil(viz.gpuCoreCount)            // binned — no single exact
        XCTAssertEqual(viz.neuralCoreCount, 16)
        XCTAssertEqual(viz.cpuCoresDisplay, "12")
        XCTAssertEqual(viz.gpuCoresDisplay, "30 or 38")
        XCTAssertEqual(viz.neuralCoresDisplay, "16")
    }

    /// The headline fix: an M3 Pro has no catalog entry, so CPU/GPU/Neural used to
    /// render blank. The chip table now fills them (CPU/GPU as honest ranges,
    /// Neural exact) while confidence correctly stays LOW.
    func test_chipFallback_fillsLowConfidenceM3Pro() {
        let viz = ComputerHardwareVisualizationModel(record: makeRecord(
            modelIdentifier: "Mac15,9",
            model: "MacBook Pro",
            processorType: "Apple M3 Pro"
        ))

        XCTAssertEqual(viz.modelInfo?.confidence, .low)
        XCTAssertNil(viz.cpuCoreCount)
        XCTAssertNil(viz.gpuCoreCount)
        XCTAssertEqual(viz.neuralCoreCount, 16)
        XCTAssertEqual(viz.cpuCoresDisplay, "11 or 12")
        XCTAssertEqual(viz.gpuCoresDisplay, "14 or 18")
        XCTAssertEqual(viz.neuralCoresDisplay, "16")
    }

    /// A reported CPU core count still wins over the chip-family range.
    func test_chipFallback_reportedCPUOverridesChipRange() {
        let viz = ComputerHardwareVisualizationModel(record: makeRecord(
            modelIdentifier: "Mac15,9",
            model: "MacBook Pro",
            processorType: "Apple M3 Pro",
            fieldValues: ["hardware.coreCount": "12"]
        ))

        XCTAssertEqual(viz.cpuCoreCount, 12)
        XCTAssertEqual(viz.cpuCoresDisplay, "12")
        XCTAssertEqual(viz.gpuCoresDisplay, "14 or 18")
    }

    func test_marketingNameAndChipFromCatalog() {
        let viz = ComputerHardwareVisualizationModel(record: makeRecord(modelIdentifier: "Mac14,7"))

        XCTAssertEqual(viz.marketingName, "MacBook Pro (13-inch, M2, 2022)")
        XCTAssertEqual(viz.chipName, "Apple M2")
    }

    func test_marketingNameFallsBackToUnknownMacWhenNothingKnown() {
        let viz = ComputerHardwareVisualizationModel(record: makeRecord())

        XCTAssertEqual(viz.marketingName, "Unknown Mac")
        XCTAssertNil(viz.chipName)
        XCTAssertNil(viz.modelInfo)
    }

    // MARK: - Confidence labelling

    func test_confidence_highForKnownIdentifier() {
        let viz = ComputerHardwareVisualizationModel(record: makeRecord(modelIdentifier: "Mac14,7"))

        XCTAssertEqual(viz.modelInfo?.confidence, .high)
        XCTAssertEqual(viz.confidenceText, "High confidence — matched model identifier.")
    }

    /// An unknown identifier with a reported model must surface a LOW-confidence
    /// label so derived specs are never presented as verified fact.
    func test_confidence_lowForUnknownIdentifierWithReportedModel() {
        let viz = ComputerHardwareVisualizationModel(record: makeRecord(
            modelIdentifier: "Future,9",
            model: "MacBook Pro"
        ))

        XCTAssertEqual(viz.modelInfo?.confidence, .low)
        XCTAssertEqual(
            viz.confidenceText,
            "Low confidence — derived from reported model; specs may be approximate."
        )
    }

    func test_confidenceText_nilWhenNoModelInfo() {
        let viz = ComputerHardwareVisualizationModel(record: makeRecord())
        XCTAssertNil(viz.confidenceText)
    }

    // MARK: - Static helpers

    func test_format_megabytesToGigabytes() {
        XCTAssertEqual(ComputerHardwareVisualizationModel.format(megabytes: 512), "512 MB")
        XCTAssertEqual(ComputerHardwareVisualizationModel.format(megabytes: 1024), "1.0 GB")
        XCTAssertEqual(ComputerHardwareVisualizationModel.format(megabytes: 1536), "1.5 GB")
        XCTAssertEqual(ComputerHardwareVisualizationModel.format(megabytes: 32768), "32.0 GB")
        // ≥ 100 GB drops the decimal: 994662 / 1024 ≈ 971.3 → "971 GB".
        XCTAssertEqual(ComputerHardwareVisualizationModel.format(megabytes: 994662), "971 GB")
    }

    func test_confidenceText_coversEachConfidenceLevel() {
        func info(_ confidence: AppleMacModelInfo.Confidence) -> AppleMacModelInfo {
            AppleMacModelInfo(
                marketingName: "Mac",
                chipName: nil,
                cpuCoreCount: nil,
                gpuCoreCount: nil,
                neuralCoreCount: nil,
                ramGB: nil,
                isPortable: nil,
                releaseYear: nil,
                confidence: confidence,
                sourceFieldsUsed: ["hardware.model"]
            )
        }

        XCTAssertEqual(
            ComputerHardwareVisualizationModel.confidenceText(for: info(.exact)),
            "Verified specs (source: hardware.model)."
        )
        XCTAssertEqual(
            ComputerHardwareVisualizationModel.confidenceText(for: info(.medium)),
            "Medium confidence — partial match (source: hardware.model)."
        )
        XCTAssertEqual(
            ComputerHardwareVisualizationModel.confidenceText(for: info(.unknown)),
            "Hardware details unavailable."
        )
    }
}
