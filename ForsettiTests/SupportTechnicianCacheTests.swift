import Foundation
import XCTest
@testable import Forsetti

final class SupportTechnicianCacheTests: XCTestCase {
    func testPoliciesCacheEncryptsBytesOnDiskAndReturnsOriginalData() async throws {
        let folderURL = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folderURL) }
        let cache = SupportTechnicianCache(secureStore: InMemorySecureDataStore(), folderURL: folderURL)
        let payload = Data(#"{"policy":"restart"}"#.utf8)

        await cache.storePolicies(payload)

        let cached = await cache.cachedPolicies()
        XCTAssertEqual(cached, payload)

        let rawFile = try XCTUnwrap(try FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil).first)
        let rawBytes = try Data(contentsOf: rawFile)
        XCTAssertNotEqual(rawBytes, payload)
        XCTAssertFalse(String(data: rawBytes, encoding: .utf8)?.contains("restart") ?? false)
    }

    func testExtensionAttributeCatalogCacheEncryptsBytesOnDiskAndReturnsOriginalData() async throws {
        let folderURL = try makeTemporaryFolder()
        defer { try? FileManager.default.removeItem(at: folderURL) }
        let cache = SupportTechnicianCache(secureStore: InMemorySecureDataStore(), folderURL: folderURL)
        let payload = Data(#"{"attribute":"building"}"#.utf8)

        await cache.storeExtensionAttributeCatalog(payload, key: "computer")

        let cached = await cache.cachedExtensionAttributeCatalog(key: "computer")
        XCTAssertEqual(cached, payload)

        let rawFile = try XCTUnwrap(try FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil).first)
        let rawBytes = try Data(contentsOf: rawFile)
        XCTAssertNotEqual(rawBytes, payload)
        XCTAssertFalse(String(data: rawBytes, encoding: .utf8)?.contains("building") ?? false)
    }

    private func makeTemporaryFolder() throws -> URL {
        let folderURL = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("forsetti-cache-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        return folderURL
    }
}

private final class InMemorySecureDataStore: SecureDataStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data] = [:]

    func save(data: Data, for key: String) throws {
        lock.withLock {
            storage[key] = data
        }
    }

    func loadData(for key: String) throws -> Data? {
        lock.withLock {
            storage[key]
        }
    }

    func deleteData(for key: String) throws {
        lock.withLock {
            storage.removeValue(forKey: key)
        }
    }
}
