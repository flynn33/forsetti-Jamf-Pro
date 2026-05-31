import Foundation
import XCTest
@testable import Forsetti

final class JamfAPIGatewayUploadPaginationTests: XCTestCase {
    func test_makeMultipartBody_rendersFilePartWithBoundaryAndHeaders() throws {
        let part = JamfMultipartFormPart(
            name: "file",
            filename: "preload.csv",
            contentType: "text/csv",
            data: Data("Serial Number\nC02ABC123\n".utf8)
        )

        let body = try JamfAPIGateway.makeMultipartBody(parts: [part], boundary: "Boundary-Test")
        let rendered = try XCTUnwrap(String(data: body, encoding: .utf8))

        XCTAssertTrue(rendered.contains("--Boundary-Test\r\n"))
        XCTAssertTrue(rendered.contains("Content-Disposition: form-data; name=\"file\"; filename=\"preload.csv\"\r\n"))
        XCTAssertTrue(rendered.contains("Content-Type: text/csv\r\n\r\n"))
        XCTAssertTrue(rendered.contains("Serial Number\nC02ABC123\n\r\n"))
        XCTAssertTrue(rendered.hasSuffix("--Boundary-Test--\r\n"))
    }

    func test_makeMultipartBody_rejectsUnsafePartName() {
        let part = JamfMultipartFormPart(name: "file\r\nbad", data: Data("x".utf8))

        XCTAssertThrowsError(try JamfAPIGateway.makeMultipartBody(parts: [part], boundary: "Boundary-Test"))
    }

    func test_paginationPolicyStopsForEmptyShortTotalAndSafetyLimit() {
        XCTAssertTrue(JamfPaginationPolicy.shouldStop(pageRecordCount: 0, page: 0))
        XCTAssertTrue(JamfPaginationPolicy.shouldStop(pageRecordCount: 20, page: 0, pageSize: 200))
        XCTAssertTrue(JamfPaginationPolicy.shouldStop(pageRecordCount: 200, page: 2, pageSize: 200, totalCount: 600, accumulatedCount: 600))
        XCTAssertTrue(JamfPaginationPolicy.shouldStop(pageRecordCount: 200, page: 49, pageSize: 200, safetyPageLimit: 50))
        XCTAssertFalse(JamfPaginationPolicy.shouldStop(pageRecordCount: 200, page: 0, pageSize: 200, totalCount: 600, accumulatedCount: 200))
    }

    func test_decodePagedCollection_readsResultsEnvelopeAndTotalCount() throws {
        let data = Data("""
        {
          "totalCount": 2,
          "results": [
            { "id": 1, "name": "One" },
            { "id": 2, "name": "Two" }
          ]
        }
        """.utf8)

        let page = try JamfAPIGateway.decodePagedCollection(PagedFixture.self, from: data)

        XCTAssertEqual(page.totalCount, 2)
        XCTAssertEqual(page.items, [
            PagedFixture(id: 1, name: "One"),
            PagedFixture(id: 2, name: "Two")
        ])
    }

    func test_decodePagedCollection_acceptsTopLevelArray() throws {
        let data = Data("""
        [
          { "id": 1, "name": "One" }
        ]
        """.utf8)

        let page = try JamfAPIGateway.decodePagedCollection(PagedFixture.self, from: data)

        XCTAssertNil(page.totalCount)
        XCTAssertEqual(page.items, [PagedFixture(id: 1, name: "One")])
    }
}

private struct PagedFixture: Decodable, Equatable, Sendable {
    let id: Int
    let name: String
}
