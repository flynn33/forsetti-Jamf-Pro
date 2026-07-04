import XCTest
@testable import ForsettiJamfProApp

// "Klatu-barada-Nikto"

/// Sanity tests for the static `AppleDeviceModelCatalog` lookup table.
///
/// These tests guard against three failure modes:
/// 1. Accidental key duplication during catalog edits.
/// 2. The M4 iPad Pro RAM-tier disambiguation regressing into a fixed value.
/// 3. The lookup throwing or crashing on unknown identifiers.
final class AppleDeviceModelCatalogTests: XCTestCase {

    func test_knownIdentifierResolves() {
        let info = AppleDeviceModelCatalog.info(for: "iPhone16,1")
        XCTAssertNotNil(info)
        XCTAssertEqual(info?.marketingName, "iPhone 15 Pro")
        XCTAssertEqual(info?.chipName, "Apple A17 Pro")
    }

    func test_unknownIdentifierReturnsNil() {
        XCTAssertNil(AppleDeviceModelCatalog.info(for: "iPad99,99"))
    }

    func test_emptyIdentifierReturnsNil() {
        XCTAssertNil(AppleDeviceModelCatalog.info(for: ""))
        XCTAssertNil(AppleDeviceModelCatalog.info(for: "   "))
    }

    func test_identifierIsTrimmedBeforeLookup() {
        XCTAssertNotNil(AppleDeviceModelCatalog.info(for: "  iPhone16,1  "))
    }

    /// M4 iPad Pro 11-inch ships 8 GB RAM on 256/512 GB SKUs and 16 GB on
    /// 1 TB / 2 TB. The lookup must select the right tier from `capacityMb`.
    func test_m4IPadPro11Has8GBOnSubTerabyte() {
        let info = AppleDeviceModelCatalog.info(for: "iPad16,3")
        XCTAssertEqual(info?.ramGB(256_000), 8)
        XCTAssertEqual(info?.ramGB(512_000), 8)
    }

    func test_m4IPadPro11Has16GBOnTerabytePlus() {
        let info = AppleDeviceModelCatalog.info(for: "iPad16,3")
        XCTAssertEqual(info?.ramGB(1_000_000), 16)
        XCTAssertEqual(info?.ramGB(2_000_000), 16)
    }

    func test_m4IPadPro13Has8GBOnSubTerabyte() {
        let info = AppleDeviceModelCatalog.info(for: "iPad16,5")
        XCTAssertEqual(info?.ramGB(256_000), 8)
    }

    func test_m4IPadPro13Has16GBOnTerabytePlus() {
        let info = AppleDeviceModelCatalog.info(for: "iPad16,5")
        XCTAssertEqual(info?.ramGB(1_500_000), 16)
    }

    func test_fixedRamModelsIgnoreCapacity() {
        let info = AppleDeviceModelCatalog.info(for: "iPhone16,1")
        XCTAssertEqual(info?.ramGB(64_000), 8)
        XCTAssertEqual(info?.ramGB(1_000_000), 8)
        XCTAssertEqual(info?.ramGB(nil), 8)
    }

    func test_splitTierWithoutCapacityReturnsNil() {
        let info = AppleDeviceModelCatalog.info(for: "iPad16,3")
        XCTAssertNil(info?.ramGB(nil))
    }

    /// All entries should have non-empty marketing names and chip names.
    /// Catches typos where someone leaves an empty string by accident.
    func test_everyEntryHasNonEmptyMarketingAndChipNames() {
        for (identifier, info) in AppleDeviceModelCatalog.entries {
            XCTAssertFalse(info.marketingName.isEmpty, "empty marketingName for \(identifier)")
            XCTAssertFalse(info.chipName.isEmpty, "empty chipName for \(identifier)")
        }
    }
}

//endofline
