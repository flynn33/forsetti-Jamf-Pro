import XCTest
@testable import ForsettiJamfProApp


/// Catalog-shape regression tests.
///
/// These don't pin specific field names (the catalog grows over time) but
/// they catch structural mistakes that have shipped before:
/// - duplicate keys (silently override one entry with another)
/// - empty `responsePaths` (would prevent any value from ever extracting)
/// - prestage staying server-filterable (it never works against Jamf's RSQL,
///   but a copy-paste of an entry could flip the flag back to true).
final class MobileDeviceFieldCatalogTests: XCTestCase {

    func test_catalogContainsAllCuratedKeys() {
        let curatedKeys = Set(MobileDeviceField.curatedCatalog.map(\.key))
        let catalogKeys = Set(MobileDeviceField.catalog.map(\.key))
        XCTAssertTrue(curatedKeys.isSubset(of: catalogKeys))
    }

    func test_catalogHasNoDuplicateKeys() {
        let keys = MobileDeviceField.catalog.map(\.key)
        XCTAssertEqual(keys.count, Set(keys).count, "Duplicate field keys in catalog")
    }

    func test_everyEntryHasNonEmptyResponsePaths() {
        for field in MobileDeviceField.catalog {
            XCTAssertFalse(field.responsePaths.isEmpty, "Empty responsePaths for \(field.key)")
        }
    }

    func test_prestageProfileFieldIsClientOnly() {
        let prestageField = MobileDeviceField.keyLookup["prestageEnrollmentProfile"]
        XCTAssertNotNil(prestageField)
        // Pre-Stage profile is now exposed in the Advanced Search picker
        // (isFilterable=true) but routed to the in-memory matcher
        // (isServerFilterable=false) because Jamf doesn't accept it as
        // an RSQL filter target.
        XCTAssertEqual(prestageField?.isFilterable, true)
        XCTAssertEqual(prestageField?.isServerFilterable, false)
    }

    func test_supervisedFieldIsBooleanType() {
        XCTAssertEqual(MobileDeviceField.keyLookup["supervised"]?.dataType, .bool)
    }

    func test_capacityMbFieldIsIntegerType() {
        XCTAssertEqual(MobileDeviceField.keyLookup["capacityMb"]?.dataType, .integer)
    }

    func test_lastInventoryUpdateFieldIsDateType() {
        XCTAssertEqual(MobileDeviceField.keyLookup["lastInventoryUpdate"]?.dataType, .date)
    }

    func test_catalogIncludesHardwareFieldsForVisualization() {
        let needed = ["capacityMb", "availableSpaceMb", "usedSpacePercentage", "batteryLevel"]
        for key in needed {
            XCTAssertNotNil(
                MobileDeviceField.keyLookup[key],
                "Hardware field \(key) missing from catalog — visualization card will show '—'"
            )
        }
    }
}

//endofline
