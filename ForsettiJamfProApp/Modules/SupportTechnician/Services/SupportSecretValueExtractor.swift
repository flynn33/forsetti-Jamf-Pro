import Foundation

/// Pure resolution of a sensitive value (password, recovery key, device PIN)
/// from a Jamf Pro JSON response.
///
/// Factored out of `SupportTechnicianAPIService` so the matching rules are
/// synchronously unit-testable and live in one place.
///
/// ## Why the rules matter
/// A naïve "first key that contains the fragment" walk is wrong for FileVault.
/// Jamf's `…/filevault` response carries **two** keys that both contain the
/// `recoveryKey` fragment:
///
/// ```json
/// { "personalRecoveryKey": "ABCD-…", "individualRecoveryKeyValidityStatus": "VALID" }
/// ```
///
/// `individualRecoveryKeyValidityStatus` is *metadata* (its value is "VALID"),
/// not the secret. Because Swift dictionary iteration order is not stable, a
/// substring-only matcher could surface "VALID" instead of the key. This type
/// therefore:
///
/// 1. honours the caller's fragment **priority order**,
/// 2. prefers an **exact** (case-insensitive) key match over a substring match, and
/// 3. never returns a value whose key looks like status/validity metadata.
nonisolated enum SupportSecretValueExtractor {

    /// Key-name fragments that mark a value as non-secret metadata. Matched as
    /// case-insensitive substrings, so `individualRecoveryKeyValidityStatus` is
    /// rejected even though it contains the `recoveryKey` fragment.
    static let metadataKeyFragments = [
        "validitystatus", "validity", "status",
        "expiration", "expires", "expiry",
        "timestamp", "date"
    ]

    enum ExtractionError: Error {
        /// No usable secret string was found in the response.
        case noSecretValue
    }

    /// Resolves the secret from raw response `data`.
    static func extract(from data: Data, preferredKeyFragments: [String]) throws -> String {
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        guard let value = resolve(in: object, preferredKeyFragments: preferredKeyFragments) else {
            throw ExtractionError.noSecretValue
        }
        return value
    }

    /// Resolves the secret from an already-parsed JSON object. Exposed for tests.
    static func resolve(in object: Any, preferredKeyFragments: [String]) -> String? {
        // Pass 1 — exact key match, in fragment-priority order. Exact matches are
        // unique within a dictionary, so this is deterministic regardless of walk
        // order, and it lets `personalRecoveryKey` win over any superstring key
        // such as `individualRecoveryKeyValidityStatus`.
        for fragment in preferredKeyFragments {
            if let value = firstString(in: object, where: {
                $0.compare(fragment, options: .caseInsensitive) == .orderedSame
            }) {
                return value
            }
        }

        // Pass 2 — substring match, in fragment-priority order, excluding any
        // metadata key.
        for fragment in preferredKeyFragments {
            if let value = firstString(in: object, where: { key in
                key.localizedCaseInsensitiveContains(fragment) && !isMetadataKey(key)
            }) {
                return value
            }
        }

        // Pass 3 — last resort: the first non-metadata scalar string anywhere.
        return firstString(in: object, where: { !isMetadataKey($0) })
    }

    /// Whether `key` names a non-secret metadata field (status, validity, etc.).
    static func isMetadataKey(_ key: String) -> Bool {
        metadataKeyFragments.contains { key.localizedCaseInsensitiveContains($0) }
    }

    /// First scalar string in the structure whose **key** satisfies `keyMatches`,
    /// recursing into nested objects and arrays.
    private static func firstString(
        in value: Any,
        where keyMatches: (String) -> Bool
    ) -> String? {
        if let dictionary = value as? [String: Any] {
            for (key, nested) in dictionary {
                if keyMatches(key), let scalar = scalarString(from: nested) {
                    return scalar
                }
                if let found = firstString(in: nested, where: keyMatches) {
                    return found
                }
            }
        } else if let array = value as? [Any] {
            for element in array {
                if let found = firstString(in: element, where: keyMatches) {
                    return found
                }
            }
        }
        return nil
    }

    /// Stringifies a *scalar* leaf (string / bool / number). Returns nil for
    /// empty-or-whitespace strings and for containers — a secret is always a
    /// scalar, so a dictionary is never flattened into a pseudo-secret.
    private static func scalarString(from value: Any?) -> String? {
        switch value {
        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let bool as Bool:
            return bool ? "true" : "false"
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }
}
