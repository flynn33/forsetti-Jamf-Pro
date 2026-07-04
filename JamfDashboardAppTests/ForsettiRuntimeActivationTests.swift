import ForsettiCore
import XCTest
@testable import Jamf_Dashboard

@MainActor
final class ForsettiRuntimeActivationTests: XCTestCase {
    func test_manifestsDecodeThroughForsettiCoreLoader() throws {
        let manifests = try loadManifests()
        XCTAssertEqual(manifests.count, 11)
        XCTAssertEqual(
            manifests.filter { $0.moduleType == .ui }.map(\.moduleID),
            [JamfDashboardModuleIDs.ui]
        )
    }

    func test_registryCoversEveryManifestEntryPoint() throws {
        let manifests = try loadManifests()
        let registry = ModuleRegistry()
        try JamfDashboardModuleRegistry.registerAll(into: registry)

        XCTAssertEqual(
            Set(manifests.map(\.entryPoint)),
            Set(registry.registeredEntryPoints)
        )
    }

    func test_registryFactoriesMatchManifestIdentity() throws {
        let manifests = try loadManifests()
        let registry = ModuleRegistry()
        try JamfDashboardModuleRegistry.registerAll(into: registry)

        for manifest in manifests {
            let module = try registry.makeModule(entryPoint: manifest.entryPoint)
            XCTAssertEqual(module.descriptor.moduleID, manifest.moduleID)
            XCTAssertEqual(module.descriptor.displayName, manifest.displayName)
            XCTAssertEqual(module.descriptor.moduleVersion, manifest.moduleVersion)
            XCTAssertEqual(module.descriptor.moduleType, manifest.moduleType)
            XCTAssertEqual(module.manifest, manifest)

            if manifest.moduleType == .ui {
                XCTAssertTrue(module is ForsettiUIModule)
            } else {
                XCTAssertFalse(module is ForsettiUIModule)
            }
        }
    }

    func test_productionActivationSetMatchesRequiredManifestSet() throws {
        let manifests = try loadManifests()
        XCTAssertEqual(
            JamfDashboardModuleIDs.productionModuleIDs,
            Set(manifests.map(\.moduleID))
        )
        XCTAssertEqual(JamfDashboardModuleIDs.productionActivationOrder.last, JamfDashboardModuleIDs.ui)
    }

    private func loadManifests() throws -> [ModuleManifest] {
        let manifestURLs = try FileManager.default.contentsOfDirectory(
            at: manifestsURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        .filter { $0.pathExtension == "json" }

        return try ManifestLoader()
            .loadManifests(resourceURLs: manifestURLs)
            .values
            .sorted { $0.moduleID < $1.moduleID }
    }

    private var manifestsURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "JamfDashboardApp/Resources/ForsettiManifests")
    }
}
