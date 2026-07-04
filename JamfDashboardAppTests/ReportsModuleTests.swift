import XCTest
@testable import Jamf_Dashboard

@MainActor
final class ReportsModuleTests: XCTestCase {
    func test_deviceTypeClassificationUsesDomainAndModelIdentifier() {
        XCTAssertEqual(
            ReportDeviceIdentityResolver.classify(domain: .computer, model: nil, modelIdentifier: nil, platformHint: nil),
            .mac
        )
        XCTAssertEqual(
            ReportDeviceIdentityResolver.classify(domain: .mobile, model: nil, modelIdentifier: "iPad14,5", platformHint: nil),
            .ipad
        )
        XCTAssertEqual(
            ReportDeviceIdentityResolver.classify(domain: .mobile, model: nil, modelIdentifier: "iPhone17,3", platformHint: nil),
            .iphone
        )
        XCTAssertEqual(
            ReportDeviceIdentityResolver.classify(domain: .mobile, model: "Apple TV", modelIdentifier: nil, platformHint: nil),
            .other
        )
    }

    func test_identityResolverMarksCatalogResolvedValues() {
        let resolver = ReportDeviceIdentityResolver()
        let identity = resolver.resolve(
            domain: .mobile,
            model: nil,
            modelIdentifier: "iPhone17,3",
            modelNumber: nil,
            capacityMb: nil,
            platformHint: nil
        )

        XCTAssertEqual(identity.deviceType, .iphone)
        XCTAssertEqual(identity.confidence, .catalogResolved)
        XCTAssertNotNil(identity.marketingName)
        XCTAssertNotNil(identity.chipName)
    }

    func test_aggregatorCountsDeviceTypesAndInferredRecords() {
        let records = [
            sampleRecord(type: .mac, confidence: .jamfAuthoritative),
            sampleRecord(type: .ipad, confidence: .catalogResolved),
            sampleRecord(type: .iphone, confidence: .inferredHigh),
            sampleRecord(type: .unknown, confidence: .unknown)
        ]

        let aggregate = ReportsAggregator().aggregate(records: records)

        XCTAssertEqual(aggregate.totalCount, 4)
        XCTAssertEqual(aggregate.count(for: .mac), 1)
        XCTAssertEqual(aggregate.count(for: .ipad), 1)
        XCTAssertEqual(aggregate.count(for: .iphone), 1)
        XCTAssertEqual(aggregate.unknownCount, 1)
        XCTAssertEqual(aggregate.inferredCount, 1)
        XCTAssertEqual(aggregate.gaugeSegments.count, 4)
    }

    func test_queryPlannerSelectsSectionsAndServerFilter() {
        let request = ReportRequest(
            name: "Managed Macs",
            domain: .computers,
            criteria: [
                ReportCriterion(fieldKey: "managed", comparison: .equals, value: "true"),
                ReportCriterion(fieldKey: "building", comparison: .contains, value: "HQ")
            ],
            grouping: .building,
            chartPreference: .rankedBars
        )

        let plan = ReportsQueryPlanner.makePlan(for: request)

        XCTAssertTrue(plan.domains.contains(.computer))
        XCTAssertFalse(plan.domains.contains(.mobile))
        XCTAssertTrue(plan.computerSections.contains(.general))
        XCTAssertTrue(plan.computerSections.contains(.userAndLocation))
        XCTAssertTrue(plan.computerServerFilter?.contains("general.remoteManagement.managed==true") == true)
        // Building criterion runs client-side for computers because the v1
        // computers-inventory schema only exposes `buildingId`. The criterion
        // is still carried in clientCriteria for in-memory matching.
        XCTAssertFalse(plan.computerServerFilter?.contains("building") == true)
        XCTAssertTrue(plan.clientCriteria.contains(where: { $0.fieldKey == "building" }))
    }

    func test_locationDirectoryResolvesNames() {
        let directory = ReportsLocationDirectory(
            buildings: ["1": "Headquarters", "2": "West Campus"],
            departments: ["7": "IT"]
        )
        XCTAssertEqual(directory.buildingName(for: "1"), "Headquarters")
        XCTAssertEqual(directory.departmentName(for: "7"), "IT")
        XCTAssertNil(directory.buildingName(for: "99"))
        XCTAssertNil(directory.buildingName(for: nil))
        XCTAssertNil(directory.buildingName(for: ""))
    }

    func test_paginationStopConditions() {
        XCTAssertTrue(ReportsPaginationPolicy.shouldStop(pageRecordCount: 0, page: 0))
        XCTAssertTrue(ReportsPaginationPolicy.shouldStop(pageRecordCount: 20, page: 0, pageSize: 200))
        XCTAssertTrue(ReportsPaginationPolicy.shouldStop(pageRecordCount: 200, page: 2, totalCount: 600, accumulatedCount: 600))
        XCTAssertFalse(ReportsPaginationPolicy.shouldStop(pageRecordCount: 200, page: 0, totalCount: 600, accumulatedCount: 200))
    }

    func test_csvEscaping() {
        XCTAssertEqual(ReportCSVRenderer.escape("plain"), "plain")
        XCTAssertEqual(ReportCSVRenderer.escape("a,b"), "\"a,b\"")
        XCTAssertEqual(ReportCSVRenderer.escape("a\"b"), "\"a\"\"b\"")
    }

    func test_enrollmentDateNormalization() {
        XCTAssertEqual(ReportsEnrollmentDate.normalize("2024-05-12T14:30:00.000Z"), "2024-05-12")
        XCTAssertEqual(ReportsEnrollmentDate.normalize("2024-05-12T14:30:00Z"), "2024-05-12")
        XCTAssertEqual(ReportsEnrollmentDate.normalize("2024-05-12"), "2024-05-12")
        XCTAssertEqual(ReportsEnrollmentDate.normalize("  2024-05-12T00:00:00Z  "), "2024-05-12")
        XCTAssertNil(ReportsEnrollmentDate.normalize(nil))
        XCTAssertNil(ReportsEnrollmentDate.normalize(""))
        XCTAssertNil(ReportsEnrollmentDate.normalize("   "))
        // A value that isn't an ISO date is surfaced unchanged rather than dropped.
        XCTAssertEqual(ReportsEnrollmentDate.normalize("Never"), "Never")
    }

    func test_fieldCatalogContainsEnrollmentDate() {
        let field = ReportsFieldCatalog.field(for: "enrollmentDate")
        XCTAssertEqual(field?.displayName, "Device Enrollment Date")
        XCTAssertEqual(field?.dataType, .string)
        XCTAssertEqual(field?.computerSection, .general)
        XCTAssertEqual(field?.mobileSection, .general)
        XCTAssertTrue(field?.domains.contains(.computer) == true)
        XCTAssertTrue(field?.domains.contains(.mobile) == true)
        // Selectable as a criterion field for both computer and mobile reports.
        XCTAssertTrue(ReportsFieldCatalog.fields(for: .computers).contains { $0.key == "enrollmentDate" })
        XCTAssertTrue(ReportsFieldCatalog.fields(for: .mobileDevices).contains { $0.key == "enrollmentDate" })
    }

    func test_csvIncludesEnrollmentDateColumnAndValue() throws {
        let data = try ReportCSVRenderer().render(payload: samplePayload())
        let csv = try XCTUnwrap(String(data: data, encoding: .utf8))
        let lines = csv.split(separator: "\n").map(String.init)
        let headerCols = try XCTUnwrap(lines.first).components(separatedBy: ",")
        let index = try XCTUnwrap(headerCols.firstIndex(of: "Enrollment Date"))
        let firstRow = try XCTUnwrap(lines.dropFirst().first).components(separatedBy: ",")
        XCTAssertEqual(firstRow[index], "2024-05-12")
    }

    func test_textMarkdownDocAndPDFRenderersProduceSmokeOutput() throws {
        let payload = samplePayload()

        let text = try ReportTextRenderer().render(payload: payload)
        XCTAssertTrue(String(data: text, encoding: .utf8)?.contains("Total Devices") == true)

        let markdown = try ReportMarkdownRenderer().render(payload: payload)
        XCTAssertTrue(String(data: markdown, encoding: .utf8)?.contains("| Type | Count |") == true)

        let doc = try ReportDocRenderer().render(payload: payload)
        let docString = String(data: doc, encoding: .utf8)
        XCTAssertTrue(docString?.contains("<html>") == true)
        XCTAssertTrue(docString?.contains("data:image/png;base64") == true)

        let pdf = try ReportPDFRenderer().render(payload: payload)
        XCTAssertTrue(pdf.starts(with: Data("%PDF".utf8)))
    }

    func test_filenameSanitation() {
        let date = Date(timeIntervalSince1970: 0)
        let filename = ReportExportFilenameBuilder.filename(reportName: "Device Counts / HQ", format: .pdf, date: date)
        XCTAssertEqual(filename, "jamf-dashboard-report-device-counts-hq-19700101-000000.pdf")
    }

    func test_exportTemplatesContainNoForbiddenAuthorshipWording() throws {
        let payload = samplePayload()
        let outputs = [
            try ReportCSVRenderer().render(payload: payload),
            try ReportTextRenderer().render(payload: payload),
            try ReportMarkdownRenderer().render(payload: payload),
            try ReportDocRenderer().render(payload: payload)
        ]
        let forbidden = ["generated " + "by", "assist" + "ant", "open" + "ai", "request" + "er"]

        for output in outputs {
            let text = String(data: output, encoding: .utf8)?.lowercased() ?? ""
            for term in forbidden {
                XCTAssertFalse(text.contains(term), "Export contains forbidden term: \(term)")
            }
        }
    }

    private func samplePayload() -> ReportExportPayload {
        let records = [
            sampleRecord(type: .mac, confidence: .jamfAuthoritative),
            sampleRecord(type: .ipad, confidence: .catalogResolved),
            sampleRecord(type: .iphone, confidence: .inferredHigh)
        ]
        let aggregate = ReportsAggregator().aggregate(records: records)
        let dataSet = ReportDataSet(
            records: records,
            aggregate: aggregate,
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            serverLabel: "example.jamfcloud.com"
        )
        return ReportExportPayload(
            request: ReportRequest.defaultCounts,
            dataSet: dataSet,
            aggregate: aggregate
        )
    }

    private func sampleRecord(type: ReportDeviceType, confidence: ReportEnrichmentConfidence) -> ReportDeviceRecord {
        let identity = ReportDeviceIdentity(
            deviceType: type,
            marketingName: type.displayName,
            generation: nil,
            chipName: type == .mac ? "Apple M3" : "Apple A17",
            ramGB: nil,
            confidence: confidence,
            sourceDescription: "Test fixture"
        )
        let location = ReportDeviceLocation(
            building: "HQ",
            department: "IT",
            room: "100",
            assignedName: "User",
            email: "user@example.com"
        )
        let management = ReportDeviceManagement(managed: true, supervised: type != .mac, ownership: "Institutional")
        let metrics = ReportHardwareMetrics(
            capacityMb: 128_000,
            availableSpaceMb: 64_000,
            usedSpacePercentage: 50,
            batteryLevel: 85,
            batteryHealth: "Normal"
        )

        return ReportDeviceRecord(
            id: UUID().uuidString,
            domain: type == .mac ? .computer : .mobile,
            deviceType: type,
            displayName: "\(type.displayName) Device",
            serialNumber: "SERIAL-\(type.rawValue)",
            model: type.displayName,
            modelIdentifier: nil,
            modelNumber: nil,
            osVersion: "17.0",
            osBuild: "21A000",
            location: location,
            management: management,
            hardwareMetrics: metrics,
            identity: identity,
            fieldValues: [
                "deviceType": type.displayName,
                "model": type.displayName,
                "building": "HQ",
                "managed": "true",
                "enrollmentDate": "2024-05-12",
                "sourceConfidence": confidence.displayName
            ]
        )
    }
}
