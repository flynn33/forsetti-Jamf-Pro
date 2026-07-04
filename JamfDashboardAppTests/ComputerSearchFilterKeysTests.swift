import XCTest
@testable import Jamf_Dashboard

/// Guards the basic-search filter key ordering that `buildFilterExpression`
/// delegates to. The filter loop itself needs a live `JamfAPIGateway`, so the
/// ordering/cap/de-dup contract was extracted into `prioritizedFilterFieldKeys`
/// — a `nonisolated static` seam (mirrors `shouldStopPaginating`).
///
/// The regression these tests pin: searching by username must work under *any*
/// field profile. Previously the basic-search filter was scoped to the selected
/// display columns, so a profile that omitted `userAndLocation.username` could
/// not be searched by username. The fix always searches the core identity
/// fields first; these tests prove identity keys are present and survive the cap.
final class ComputerSearchFilterKeysTests: XCTestCase {

    /// Mirrors the production identity set (`privilegeFallbackFilterFieldKeys`).
    private let identity = [
        "general.name",
        "hardware.serialNumber",
        "udid",
        "general.assetTag",
        "general.barcode1",
        "general.barcode2",
        "general.lastIpAddress",
        "userAndLocation.username",
        "userAndLocation.email",
        "userAndLocation.realname"
    ]

    // MARK: - Username survives any profile

    /// A profile selecting only non-identity columns must still search username.
    func test_usernameAlwaysSearched_whenProfileExcludesIt() {
        let candidate = ["hardware.model", "operatingSystem.version", "general.platform"]
        let keys = ComputerSearchViewModel.prioritizedFilterFieldKeys(
            identityKeys: identity,
            candidateKeys: candidate,
            fallbackKeys: identity,
            cap: 12
        )
        XCTAssertTrue(keys.contains("userAndLocation.username"))
        XCTAssertTrue(keys.contains("userAndLocation.email"))
        XCTAssertTrue(keys.contains("general.name"))
        XCTAssertTrue(keys.contains("hardware.serialNumber"))
    }

    // MARK: - Identity-first ordering

    func test_identityKeysComeFirst() {
        let candidate = ["hardware.model"]
        let keys = ComputerSearchViewModel.prioritizedFilterFieldKeys(
            identityKeys: identity,
            candidateKeys: candidate,
            fallbackKeys: identity,
            cap: 12
        )
        XCTAssertEqual(Array(keys.prefix(identity.count)), identity)
        XCTAssertEqual(keys.last, "hardware.model")
    }

    // MARK: - Cap never drops identity keys

    /// Even when the candidate list alone would fill the cap, every identity key
    /// must survive because identity keys are ordered first.
    func test_capNeverDropsIdentityKeys() {
        let candidate = (0..<20).map { "extra.field\($0)" }
        let keys = ComputerSearchViewModel.prioritizedFilterFieldKeys(
            identityKeys: identity,
            candidateKeys: candidate,
            fallbackKeys: identity,
            cap: 12
        )
        XCTAssertEqual(keys.count, 12)
        for identityKey in identity {
            XCTAssertTrue(keys.contains(identityKey), "Cap dropped identity key \(identityKey)")
        }
    }

    // MARK: - De-duplication

    func test_keyPresentInBothGroupsAppearsOnce() {
        let candidate = ["userAndLocation.username", "hardware.model"]
        let keys = ComputerSearchViewModel.prioritizedFilterFieldKeys(
            identityKeys: identity,
            candidateKeys: candidate,
            fallbackKeys: identity,
            cap: 12
        )
        XCTAssertEqual(keys.filter { $0 == "userAndLocation.username" }.count, 1)
    }

    // MARK: - Fallback

    func test_fallbackUsedOnlyWhenBothInputsEmpty() {
        let keys = ComputerSearchViewModel.prioritizedFilterFieldKeys(
            identityKeys: [],
            candidateKeys: [],
            fallbackKeys: ["general.name"],
            cap: 12
        )
        XCTAssertEqual(keys, ["general.name"])
    }

    func test_fallbackNotUsedWhenCandidatesPresent() {
        let keys = ComputerSearchViewModel.prioritizedFilterFieldKeys(
            identityKeys: [],
            candidateKeys: ["hardware.model"],
            fallbackKeys: ["general.name"],
            cap: 12
        )
        XCTAssertEqual(keys, ["hardware.model"])
    }
}
