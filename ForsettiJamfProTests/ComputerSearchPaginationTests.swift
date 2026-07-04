import XCTest
@testable import ForsettiJamfProApp

/// Exercises the pure pagination stop predicate that both Computer Search
/// inventory loops (`requestAllInventoryPages` and
/// `requestAllInventoryPagesWithRawFilter`) delegate to. The loops themselves
/// require a live `JamfAPIGateway` actor and cannot be unit-tested directly, so
/// the stop decision was extracted into `shouldStopPaginating` — a
/// `nonisolated static` seam that binds this module's page size (200) and the
/// shared safety cap (50) to `JamfPaginationPolicy.shouldStop`.
final class ComputerSearchPaginationTests: XCTestCase {

    // MARK: - End-of-results (short / empty page)

    func test_emptyPageStops() {
        XCTAssertTrue(ComputerSearchViewModel.shouldStopPaginating(pageRecordCount: 0, page: 0))
    }

    func test_shortPageStops() {
        XCTAssertTrue(ComputerSearchViewModel.shouldStopPaginating(pageRecordCount: 20, page: 0))
    }

    /// A page of 199 is one short of the 200 page size, so it is the last page.
    /// Together with `test_fullPageContinues` this pins the wired page size to
    /// exactly 200 — a regression here would mean the seam stopped using
    /// `computerInventoryPageSize`.
    func test_justUnderPageSizeStops() {
        XCTAssertTrue(ComputerSearchViewModel.shouldStopPaginating(pageRecordCount: 199, page: 0))
    }

    // MARK: - Continue (full page, below safety cap)

    func test_fullPageContinues() {
        XCTAssertFalse(ComputerSearchViewModel.shouldStopPaginating(pageRecordCount: 200, page: 0))
    }

    func test_fullPageMidRangeContinues() {
        XCTAssertFalse(ComputerSearchViewModel.shouldStopPaginating(pageRecordCount: 200, page: 10))
    }

    /// page 48 → next page index 49, still below the cap of 50, so keep going.
    func test_fullPageOneBeforeSafetyCapContinues() {
        XCTAssertFalse(ComputerSearchViewModel.shouldStopPaginating(pageRecordCount: 200, page: 48))
    }

    // MARK: - Safety cap

    /// page 49 → next page index 50, which reaches the 50-page cap, so stop even
    /// on a full page. Paired with the page-48 case this pins the cap to 50.
    func test_fullPageAtSafetyCapStops() {
        XCTAssertTrue(ComputerSearchViewModel.shouldStopPaginating(pageRecordCount: 200, page: 49))
    }

    /// A short page at the cap still stops via the end-of-results branch.
    func test_shortPageAtSafetyCapStops() {
        XCTAssertTrue(ComputerSearchViewModel.shouldStopPaginating(pageRecordCount: 5, page: 49))
    }
}
