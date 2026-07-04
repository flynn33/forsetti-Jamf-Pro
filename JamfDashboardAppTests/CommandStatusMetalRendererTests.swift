import XCTest
#if canImport(MetalKit)
import MetalKit
#endif
@testable import Jamf_Dashboard

final class CommandStatusMetalRendererTests: XCTestCase {

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
}

//endofline
