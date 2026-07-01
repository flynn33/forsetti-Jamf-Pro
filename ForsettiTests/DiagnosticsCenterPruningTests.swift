import XCTest
@testable import Forsetti

/// Verifies `DiagnosticsCenter.prunedTail(of:toAtMost:)` — the pure helper that
/// keeps the persistent NDJSON log under its size cap by dropping the oldest
/// whole lines (oldest → newest) so no partial leading line survives.
final class DiagnosticsCenterPruningTests: XCTestCase {

    /// Builds `count` fixed-width 10-byte NDJSON lines: "000000000\n" … each
    /// line is 9 digits + a newline, so byte offsets are easy to reason about.
    private func makeLines(_ count: Int) -> Data {
        var text = ""
        for i in 0..<count {
            text += String(format: "%09d", i) + "\n"
        }
        return Data(text.utf8)
    }

    private func line(_ i: Int) -> String { String(format: "%09d", i) + "\n" }

    func test_withinTarget_returnsUnchanged() {
        let data = makeLines(3) // 30 bytes
        XCTAssertEqual(DiagnosticsCenter.prunedTail(of: data, toAtMost: 100), data)
    }

    func test_exactlyAtTarget_returnsUnchanged() {
        let data = makeLines(3) // 30 bytes
        XCTAssertEqual(DiagnosticsCenter.prunedTail(of: data, toAtMost: 30), data)
    }

    func test_dropsOldestWholeLines_toFitTarget() {
        let data = makeLines(10) // 100 bytes, lines 0…9
        let pruned = DiagnosticsCenter.prunedTail(of: data, toAtMost: 35)

        // Keeps the newest whole lines that fit: 7, 8, 9 (30 bytes ≤ 35).
        let expected = Data((line(7) + line(8) + line(9)).utf8)
        XCTAssertEqual(pruned, expected)
        XCTAssertLessThanOrEqual(pruned.count, 35)
    }

    func test_resultIsASuffixOfOriginalAndStartsOnLineBoundary() {
        let data = makeLines(10)
        let pruned = DiagnosticsCenter.prunedTail(of: data, toAtMost: 44)

        // Must be a suffix of the original bytes.
        XCTAssertEqual(Data(data.suffix(pruned.count)), pruned)
        // Must begin at a line start: first kept line is a full "00000000N\n".
        let text = String(decoding: pruned, as: UTF8.self)
        XCTAssertTrue(text.hasPrefix("00000000"))
        XCTAssertTrue(text.hasSuffix("\n"))
        // Every kept line is intact (no partial leading line).
        for piece in text.split(separator: "\n") {
            XCTAssertEqual(piece.count, 9)
        }
    }

    func test_singleLineWithNoUsableBoundary_returnsUnchanged() {
        // No newline anywhere and larger than target → cannot cleanly prune.
        let data = Data(String(repeating: "A", count: 50).utf8)
        XCTAssertEqual(DiagnosticsCenter.prunedTail(of: data, toAtMost: 10), data)
    }

    func test_zeroTarget_returnsUnchanged() {
        let data = makeLines(5)
        XCTAssertEqual(DiagnosticsCenter.prunedTail(of: data, toAtMost: 0), data)
    }
}

//endofline
