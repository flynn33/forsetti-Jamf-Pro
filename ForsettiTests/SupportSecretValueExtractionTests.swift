import XCTest
@testable import Forsetti

/// Verifies secret resolution from Jamf JSON responses.
///
/// The headline regression: Jamf's FileVault response carries both
/// `personalRecoveryKey` (the secret) and `individualRecoveryKeyValidityStatus`
/// (= "VALID"). The status key *contains* the `recoveryKey` fragment, so a
/// substring-only matcher could surface "VALID" instead of the key under
/// non-deterministic dictionary iteration. These tests pin the correct
/// behaviour: the actual key is returned, never the validity status.
final class SupportSecretValueExtractionTests: XCTestCase {

    private let fileVaultFragments = [
        "personalRecoveryKey",
        "recoveryKey",
        "individualRecoveryKey"
    ]

    // MARK: - FileVault

    func test_fileVault_returnsKeyNotValidityStatus() {
        let response: [String: Any] = [
            "personalRecoveryKey": "ABCD-1234-EFGH-5678-IJKL-90MN",
            "individualRecoveryKeyValidityStatus": "VALID"
        ]

        let value = SupportSecretValueExtractor.resolve(
            in: response,
            preferredKeyFragments: fileVaultFragments
        )

        XCTAssertEqual(value, "ABCD-1234-EFGH-5678-IJKL-90MN")
        XCTAssertNotEqual(value?.lowercased(), "valid")
    }

    /// Exact-match priority is order-independent, so the key is returned no
    /// matter how the dictionary happens to be walked. Rebuild and re-resolve
    /// many times to make the point even with hash-seed variation.
    func test_fileVault_isStableAcrossDictionaryOrdering() {
        for index in 0..<100 {
            let response: [String: Any] = [
                "individualRecoveryKeyValidityStatus": "VALID",
                "personalRecoveryKey": "KEY-\(index)",
                "diskEncryptionConfigurationName": "Escrow Config"
            ]

            let value = SupportSecretValueExtractor.resolve(
                in: response,
                preferredKeyFragments: fileVaultFragments
            )

            XCTAssertEqual(value, "KEY-\(index)")
        }
    }

    func test_fileVault_throughDataDecoding() throws {
        let json = """
        { "individualRecoveryKeyValidityStatus": "VALID", "personalRecoveryKey": "ZZZZ-0000" }
        """
        let data = Data(json.utf8)

        let value = try SupportSecretValueExtractor.extract(
            from: data,
            preferredKeyFragments: fileVaultFragments
        )

        XCTAssertEqual(value, "ZZZZ-0000")
    }

    /// When the key is genuinely absent (only the status is present), we must
    /// NOT leak the status as a secret — surface "no secret" instead.
    func test_fileVault_statusOnly_throwsRatherThanLeakingStatus() {
        let response: [String: Any] = [
            "individualRecoveryKeyValidityStatus": "VALID"
        ]

        let value = SupportSecretValueExtractor.resolve(
            in: response,
            preferredKeyFragments: fileVaultFragments
        )

        XCTAssertNil(value)
    }

    /// An empty/whitespace key value is treated as absent (not surfaced, and
    /// not silently replaced by the status field).
    func test_fileVault_emptyKeyValue_isNotSurfaced() {
        let response: [String: Any] = [
            "personalRecoveryKey": "   ",
            "individualRecoveryKeyValidityStatus": "VALID"
        ]

        let value = SupportSecretValueExtractor.resolve(
            in: response,
            preferredKeyFragments: fileVaultFragments
        )

        XCTAssertNil(value)
    }

    // MARK: - Exactness / priority

    func test_exactMatchWinsOverSubstringSuperstring() {
        let response: [String: Any] = [
            "recoveryKeyHint": "do-not-return-me",
            "recoveryKey": "THE-REAL-KEY"
        ]

        let value = SupportSecretValueExtractor.resolve(
            in: response,
            preferredKeyFragments: ["recoveryKey"]
        )

        XCTAssertEqual(value, "THE-REAL-KEY")
    }

    func test_fragmentPriorityOrderIsHonoured() {
        let response: [String: Any] = [
            "password": "fallback",
            "personalRecoveryKey": "preferred"
        ]

        let value = SupportSecretValueExtractor.resolve(
            in: response,
            preferredKeyFragments: ["personalRecoveryKey", "password"]
        )

        XCTAssertEqual(value, "preferred")
    }

    // MARK: - Other credential shapes

    func test_recoveryLockPassword() {
        let response: [String: Any] = ["recoveryLockPassword": "lock-pass-1"]
        XCTAssertEqual(
            SupportSecretValueExtractor.resolve(
                in: response,
                preferredKeyFragments: ["recoveryLockPassword", "password"]
            ),
            "lock-pass-1"
        )
    }

    func test_deviceLockPIN_numericValue() {
        let response: [String: Any] = ["pin": 123456]
        XCTAssertEqual(
            SupportSecretValueExtractor.resolve(
                in: response,
                preferredKeyFragments: ["pin", "deviceLockPin"]
            ),
            "123456"
        )
    }

    func test_lapsPassword() {
        let response: [String: Any] = ["password": "L@ps-Secret"]
        XCTAssertEqual(
            SupportSecretValueExtractor.resolve(
                in: response,
                preferredKeyFragments: ["password", "plainTextPassword"]
            ),
            "L@ps-Secret"
        )
    }

    func test_nestedSecretIsFound() {
        let response: [String: Any] = [
            "results": [
                "personalRecoveryKey": "NESTED-KEY"
            ]
        ]
        XCTAssertEqual(
            SupportSecretValueExtractor.resolve(
                in: response,
                preferredKeyFragments: fileVaultFragments
            ),
            "NESTED-KEY"
        )
    }
}
