import XCTest
@testable import Forsetti

final class SupportTechnicianPrestageParserTests: XCTestCase {

    func test_mobileEnrollmentMethodPrestageBuildsDisplayValue() {
        let payload: [String: Any] = [
            "general": [
                "enrollmentMethodPrestage": [
                    "profileName": "Retail iPad PreStage",
                    "mobileDevicePrestageId": 42,
                    "managementStatus": "managed"
                ]
            ]
        ]

        XCTAssertEqual(
            SupportTechnicianPrestageParser.displayValue(from: payload),
            "Enrolled - Retail iPad PreStage (ID: 42)"
        )
    }

    func test_mobileFlatPrestageFieldsBuildDisplayValue() {
        let payload: [String: Any] = [
            "prestageEnrollmentProfileName": "Shared Device PreStage",
            "prestageEnrollmentProfileId": "17"
        ]

        XCTAssertEqual(
            SupportTechnicianPrestageParser.displayValue(from: payload),
            "Shared Device PreStage (ID: 17)"
        )
    }

    func test_generalManagedAloneDoesNotBecomePrestageEnrollment() {
        let payload: [String: Any] = [
            "general": [
                "managed": true
            ]
        ]

        XCTAssertNil(SupportTechnicianPrestageParser.displayValue(from: payload))
    }

    func test_computerEnrollmentMethodObjectResolvesPrestageName() {
        let payload: [String: Any] = [
            "general": [
                "enrollmentMethod": [
                    "id": 7,
                    "objectName": "Retail ZT Base",
                    "objectType": "PreStage enrollment"
                ],
                "enrolledViaAutomatedDeviceEnrollment": true
            ]
        ]

        XCTAssertEqual(
            SupportTechnicianPrestageParser.displayValue(from: payload),
            "Retail ZT Base"
        )
    }

    func test_computerNonPrestageEnrollmentMethodIsNotTreatedAsPrestage() {
        let payload: [String: Any] = [
            "general": [
                "enrollmentMethod": [
                    "id": 3,
                    "objectName": "jim.daley",
                    "objectType": "User-Initiated - No Invitation"
                ]
            ]
        ]

        XCTAssertNil(SupportTechnicianPrestageParser.displayValue(from: payload))
    }

    func test_mobileEnrollmentMethodStringResolvesPrestageName() {
        let payload: [String: Any] = [
            "enrollmentMethod": "PreStage enrollment: RV Sales (11)"
        ]

        XCTAssertEqual(
            SupportTechnicianPrestageParser.displayValue(from: payload),
            "RV Sales"
        )
    }

    func test_mobileEnrollmentMethodStringToleratesPrestageInTheName() {
        let payload: [String: Any] = [
            "enrollmentMethod": "PreStage enrollment: PreStage - Digital Signage (25)"
        ]

        XCTAssertEqual(
            SupportTechnicianPrestageParser.displayValue(from: payload),
            "PreStage - Digital Signage"
        )
    }

    func test_mobileNonPrestageEnrollmentMethodStringReturnsNil() {
        let payload: [String: Any] = [
            "enrollmentMethod": "User-initiated - no invitation"
        ]

        XCTAssertNil(SupportTechnicianPrestageParser.displayValue(from: payload))
    }

    // MARK: - Mobile PreStage Scope Parsing

    func test_mobilePrestageNamesParsesResultsEnvelope() {
        let page: [String: Any] = [
            "totalCount": 2,
            "results": [
                ["id": "5", "displayName": "RV Sales"],
                ["id": 11, "displayName": "Shared Device"]
            ]
        ]

        XCTAssertEqual(
            SupportTechnicianPrestageParser.mobilePrestageNames(fromListPage: page),
            ["5": "RV Sales", "11": "Shared Device"]
        )
    }

    func test_mobilePrestageNamesFallsBackToAlternateKeysAndIDs() {
        let page: [String: Any] = [
            "results": [
                ["prestageId": "7", "name": "Digital Signage"],
                ["id": "9", "profileName": "Kiosk"],
                ["id": "12"]
            ]
        ]

        XCTAssertEqual(
            SupportTechnicianPrestageParser.mobilePrestageNames(fromListPage: page),
            ["7": "Digital Signage", "9": "Kiosk", "12": "Pre-Stage 12"]
        )
    }

    func test_mobilePrestageScopeSerialsParsesAssignmentObjects() {
        let page: [String: Any] = [
            "assignments": [
                ["serialNumber": "abc123"],
                ["serial": "def456"]
            ]
        ]

        XCTAssertEqual(
            Set(SupportTechnicianPrestageParser.mobilePrestageScopeSerials(fromScopePage: page)),
            ["ABC123", "DEF456"]
        )
    }

    func test_mobilePrestageScopeSerialsParsesNestedDeviceObjects() {
        let page: [String: Any] = [
            "results": [
                ["mobileDevice": ["serialNumber": "xyz789"]]
            ]
        ]

        XCTAssertEqual(
            SupportTechnicianPrestageParser.mobilePrestageScopeSerials(fromScopePage: page),
            ["XYZ789"]
        )
    }

    func test_mobilePrestageScopeSerialsParsesFlatSerialNumberArray() {
        let page: [String: Any] = [
            "serialNumbers": ["aaa", "bbb"]
        ]

        XCTAssertEqual(
            SupportTechnicianPrestageParser.mobilePrestageScopeSerials(fromScopePage: page),
            ["AAA", "BBB"]
        )
    }

    func test_mobilePrestageScopeSerialsParsesAssignmentsDictWithSerialNumbers() {
        // Jamf returns `assignments` as an OBJECT carrying a flat
        // `serialNumbers` array on some Pro versions — the shallow parser
        // missed this and resolved no serials.
        let page: [String: Any] = [
            "assignments": [
                "serialNumbers": ["mxfc4qmw53", "DEF456"]
            ],
            "versionLock": 3
        ]

        XCTAssertEqual(
            Set(SupportTechnicianPrestageParser.mobilePrestageScopeSerials(fromScopePage: page)),
            ["MXFC4QMW53", "DEF456"]
        )
    }

    func test_mobilePrestageScopeSerialsParsesTopLevelArrayOfAssignments() {
        let json: Any = [
            ["serialNumber": "mxfc4qmw53"],
            ["serialNumber": "ghi789"]
        ]

        XCTAssertEqual(
            Set(SupportTechnicianPrestageParser.mobilePrestageScopeSerials(fromScopeJSON: json)),
            ["MXFC4QMW53", "GHI789"]
        )
    }

    func test_mobilePrestageScopeSerialsParsesTopLevelFlatStringArray() {
        let json: Any = ["mxfc4qmw53", "jkl012"]

        XCTAssertEqual(
            Set(SupportTechnicianPrestageParser.mobilePrestageScopeSerials(fromScopeJSON: json)),
            ["MXFC4QMW53", "JKL012"]
        )
    }

    func test_mobilePrestageScopeSerialsFuzzyMatchesUnknownSerialKey() {
        let page: [String: Any] = [
            "assignments": [
                ["deviceSerialNumber": "mxfc4qmw53"]
            ]
        ]

        XCTAssertEqual(
            SupportTechnicianPrestageParser.mobilePrestageScopeSerials(fromScopePage: page),
            ["MXFC4QMW53"]
        )
    }

    func test_normalizeSerialUppercasesTrimsAndRejectsEmpty() {
        XCTAssertEqual(SupportTechnicianPrestageParser.normalizeSerial("  abc123 "), "ABC123")
        XCTAssertNil(SupportTechnicianPrestageParser.normalizeSerial("   "))
        XCTAssertNil(SupportTechnicianPrestageParser.normalizeSerial(nil))
    }

}

//endofline
