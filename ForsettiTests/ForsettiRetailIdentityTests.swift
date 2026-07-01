import XCTest
import ForsettiCore
@testable import Forsetti

final class ForsettiRetailIdentityTests: XCTestCase {
    func testRetailIdentityValuesAreCentralizedAndSanitized() {
        XCTAssertEqual(ForsettiAppIdentity.productName, "Forsetti")
        XCTAssertEqual(ForsettiAppIdentity.displayName, "Forsetti")
        XCTAssertEqual(ForsettiAppIdentity.bundleIdentifier, "com.ravenforge.forsetti")
        XCTAssertEqual(ForsettiAppIdentity.testBundleIdentifier, "com.ravenforge.forsetti.tests")
        XCTAssertEqual(ForsettiAppIdentity.diagnosticsSubsystem, "com.ravenforge.forsetti.diagnostics")
        XCTAssertEqual(ForsettiAppIdentity.applicationSupportFolder, "Forsetti")

        let forbiddenFragments = [
            "camp" + "ing world",
            "camp" + "ingworld",
            "cw" + "gs",
            "rv" + ".com",
            "me" + ".rv" + ".com"
        ]

        let identityValues = [
            ForsettiAppIdentity.productName,
            ForsettiAppIdentity.displayName,
            ForsettiAppIdentity.bundleIdentifier,
            ForsettiAppIdentity.testBundleIdentifier,
            ForsettiAppIdentity.diagnosticsSubsystem,
            ForsettiAppIdentity.applicationSupportFolder
        ].map { $0.lowercased() }

        for value in identityValues {
            for fragment in forbiddenFragments {
                XCTAssertFalse(value.contains(fragment), "\(value) contains forbidden fragment \(fragment)")
            }
        }
    }

    func testBundledForsettiManifestSpecsContainOneRetailUIModule() {
        let specs = ForsettiRetailBootstrap.manifestSpecs
        let moduleIDs = Set(specs.map(\.moduleID))

        XCTAssertEqual(specs.filter { $0.moduleType == .ui }.map(\.moduleID), ["com.forsetti.jamfpro.retail.ui"])
        XCTAssertTrue(moduleIDs.isSuperset(of: [
            "com.forsetti.jamfpro.service.jamf",
            "com.forsetti.jamfpro.service.diagnostics",
            "com.forsetti.jamfpro.service.scanner",
            "com.forsetti.jamfpro.feature.computer-search",
            "com.forsetti.jamfpro.feature.mobile-device-search",
            "com.forsetti.jamfpro.feature.support-technician",
            "com.forsetti.jamfpro.feature.prestage-director",
            "com.forsetti.jamfpro.feature.reports",
            "com.forsetti.jamfpro.feature.deployment-tracker",
            "com.forsetti.jamfpro.feature.permissions-matrix"
        ]))
    }

    func testBundledForsettiManifestFilesMatchBootstrapSpecs() throws {
        let manifestDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("ForsettiApp/Resources/ForsettiManifests", isDirectory: true)
        let manifestURLs = try FileManager.default
            .contentsOfDirectory(at: manifestDirectory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        let decodedManifests = try manifestURLs.map {
            try JSONDecoder().decode(ModuleManifest.self, from: Data(contentsOf: $0))
        }
        let manifestsByID = Dictionary(uniqueKeysWithValues: decodedManifests.map { ($0.moduleID, $0) })

        XCTAssertEqual(decodedManifests.count, ForsettiRetailBootstrap.manifestSpecs.count)

        for spec in ForsettiRetailBootstrap.manifestSpecs {
            let manifest = try XCTUnwrap(manifestsByID[spec.moduleID], "Missing manifest for \(spec.moduleID)")
            let expected = spec.manifest

            XCTAssertEqual(manifest.schemaVersion, expected.schemaVersion)
            XCTAssertEqual(manifest.displayName, expected.displayName)
            XCTAssertEqual(manifest.moduleVersion, expected.moduleVersion)
            XCTAssertEqual(manifest.moduleType.rawValue, expected.moduleType.rawValue)
            XCTAssertEqual(manifest.supportedPlatforms.map(\.rawValue).sorted(), expected.supportedPlatforms.map(\.rawValue).sorted())
            XCTAssertEqual(manifest.minForsettiVersion, expected.minForsettiVersion)
            XCTAssertEqual(manifest.maxForsettiVersion, expected.maxForsettiVersion)
            XCTAssertEqual(manifest.capabilitiesRequested.map(\.rawValue).sorted(), expected.capabilitiesRequested.map(\.rawValue).sorted())
            XCTAssertEqual(manifest.iapProductID, expected.iapProductID)
            XCTAssertEqual(manifest.entryPoint, expected.entryPoint)
        }
    }

    @MainActor
    func testRetailBootstrapBootsBundledManifestsWhenRequested() async {
        let bootstrap = ForsettiRetailBootstrap.makeController()

        await bootstrap.bootIfNeeded()

        XCTAssertTrue(bootstrap.isBooted)
        XCTAssertNil(bootstrap.errorMessage)
    }
}
