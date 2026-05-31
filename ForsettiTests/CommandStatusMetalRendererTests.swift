import XCTest
#if canImport(MetalKit)
import MetalKit
#endif
@testable import Forsetti

final class CommandStatusMetalRendererTests: XCTestCase {
    func test_commandStatusRenderPayloadUsesObsidianDataStreamStatusVectors() {
        let action = SupportManagementAction.scheduleOSUpdate
        let date = Date(timeIntervalSinceReferenceDate: 0)

        assertVector(CommandStatusIndicatorView.renderPayload(for: .idle).accent, equalsHex: 0x63879A)
        assertVector(CommandStatusIndicatorView.renderPayload(for: .sending(action: action, startedAt: date)).accent, equalsHex: 0x00E5FF)
        assertVector(CommandStatusIndicatorView.renderPayload(for: .queued(action: action, queuedAt: date)).accent, equalsHex: 0x2F7FFF)
        assertVector(CommandStatusIndicatorView.renderPayload(for: .verifying(action: action, startedAt: date, attempt: 1)).accent, equalsHex: 0xFFD166)
        assertVector(CommandStatusIndicatorView.renderPayload(for: .succeeded(action: action, completedAt: date)).accent, equalsHex: 0x37FFB0)
        assertVector(CommandStatusIndicatorView.renderPayload(for: .failed(action: action, errorDescription: "Denied")).accent, equalsHex: 0xFF5C8A)
        assertVector(CommandStatusIndicatorView.renderPayload(for: .timedOut(action: action)).accent, equalsHex: 0xFFD166)
    }

    #if canImport(MetalKit)
    func test_commandStatusMetalRendererPipelineCompiles() throws {
        guard CommandStatusRenderer.sharedDevice != nil else {
            throw XCTSkip("Metal is unavailable on this test host.")
        }

        XCTAssertTrue(
            CommandStatusRenderer.isAvailable,
            CommandStatusRenderer.lastInitError ?? "Command status Metal pipeline did not initialize."
        )
    }
    #endif

    private func assertVector(
        _ vector: SIMD3<Float>,
        equalsHex value: UInt32,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(vector.x, Float((value >> 16) & 0xFF) / 255, accuracy: 0.004, file: file, line: line)
        XCTAssertEqual(vector.y, Float((value >> 8) & 0xFF) / 255, accuracy: 0.004, file: file, line: line)
        XCTAssertEqual(vector.z, Float(value & 0xFF) / 255, accuracy: 0.004, file: file, line: line)
    }
}

//endofline
