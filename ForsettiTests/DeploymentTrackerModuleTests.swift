import XCTest
@testable import Forsetti

@MainActor
final class DeploymentTrackerModuleTests: XCTestCase {
    func test_modulePackageTypeDefaultsMatchHandoffMetadata() {
        XCTAssertEqual(ModulePackageType.deploymentTracker.rawValue, "deployment-tracker")
        XCTAssertEqual(ModulePackageType.deploymentTracker.defaultTitle, "Deployment Tracker Demo")
        XCTAssertEqual(
            ModulePackageType.deploymentTracker.defaultSubtitle,
            "Interactive preview of the upcoming Deployment Tracker Module. Dummy data only. No live Jamf actions."
        )
        XCTAssertEqual(ModulePackageType.deploymentTracker.defaultIconSystemName, "sparkles.rectangle.stack")
    }

    func test_deploymentTrackerIsBundledByDefault() {
        let manifest = ModulePackageManifest.bundledDefaults.first {
            $0.packageID == "com.forsetti.jamfpro.feature.deployment-tracker"
        }

        XCTAssertNotNil(manifest)
        XCTAssertEqual(manifest?.moduleType, .deploymentTracker)
        XCTAssertTrue(manifest?.isBundledDefault ?? false)
    }

    func test_modulePackageTemplateCanBeImportedByFrameworkParser() throws {
        let packageData = Data("""
        {
          "package_id": "com.forsetti.jamfpro.feature.deployment-tracker",
          "module_type": "deployment-tracker",
          "package_version": "1.0.0",
          "module_display_name": "Deployment Tracker Demo",
          "module_subtitle": "Interactive preview of the upcoming Deployment Tracker Module. Dummy data only. No live Jamf actions.",
          "icon_system_name": "sparkles.rectangle.stack"
        }
        """.utf8)
        let manifest = try ModulePackageManifest.fromPackageFileData(packageData)

        XCTAssertEqual(manifest.packageID, "com.forsetti.jamfpro.feature.deployment-tracker")
        XCTAssertEqual(manifest.moduleType, .deploymentTracker)
        XCTAssertEqual(manifest.resolvedModuleTitle, "Deployment Tracker Demo")
        XCTAssertEqual(manifest.resolvedIconSystemName, "sparkles.rectangle.stack")
    }

    func test_moduleExposesAllRequiredRemediationWorkspaces() {
        XCTAssertEqual(DeploymentTrackerWorkspace.allCases.map(\.displayName), [
            "Demo Dashboard",
            "Demo Workbench",
            "Demo Projects",
            "Demo Devices",
            "Demo Intake / Imports",
            "Demo Jamf Preload",
            "Demo ABM Verification",
            "Demo SD+ Export",
            "Demo Shipments",
            "Demo Reports",
            "Demo Apple Catalog",
            "Demo Administration",
            "Demo Records Management",
            "Demo Guide"
        ])
    }

    func test_importingDeploymentTrackerManifestAddsModuleToRegistry() async throws {
        let packageStoreURL = temporaryPackageStoreURL()
        let manifestURL = try temporaryPackageFile(
            name: "deployment-tracker-imported.jamfmodule.json",
            contents: Self.importedDeploymentTrackerPackageJSON
        )
        let registry = ModuleRegistry()
        let diagnostics = RecordingDiagnosticsReporter()
        let manager = ModulePackageManager(
            moduleRegistry: registry,
            diagnosticsReporter: diagnostics,
            packageStore: ModulePackageStore(fileURL: packageStoreURL)
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: packageStoreURL.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: manifestURL.deletingLastPathComponent())
        }

        await manager.bootstrap()
        XCTAssertNotNil(registry.module(withID: "com.forsetti.jamfpro.feature.deployment-tracker"))
        XCTAssertNil(registry.module(withID: "com.forsetti.jamfpro.feature.deployment-tracker.imported"))

        let installed = try await manager.installPackage(from: manifestURL)

        XCTAssertEqual(installed.moduleType, ModulePackageType.deploymentTracker)
        XCTAssertNotNil(registry.module(withID: "com.forsetti.jamfpro.feature.deployment-tracker.imported"))
        XCTAssertEqual(registry.module(withID: "com.forsetti.jamfpro.feature.deployment-tracker.imported")?.title, "Deployment Tracker Import Test")
    }

    func test_duplicateDeploymentTrackerPackageIDsAreRejected() async throws {
        let packageStoreURL = temporaryPackageStoreURL()
        let manifestURL = try temporaryPackageFile(
            name: "deployment-tracker-imported.jamfmodule.json",
            contents: Self.importedDeploymentTrackerPackageJSON
        )
        let manager = ModulePackageManager(
            moduleRegistry: ModuleRegistry(),
            diagnosticsReporter: RecordingDiagnosticsReporter(),
            packageStore: ModulePackageStore(fileURL: packageStoreURL)
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: packageStoreURL.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: manifestURL.deletingLastPathComponent())
        }

        await manager.bootstrap()
        _ = try await manager.installPackage(from: manifestURL)

        do {
            _ = try await manager.installPackage(from: manifestURL)
            XCTFail("Expected duplicate package installation to fail.")
        } catch JamfFrameworkError.duplicateModulePackage(let packageID) {
            XCTAssertEqual(packageID, "com.forsetti.jamfpro.feature.deployment-tracker.imported")
        }
    }

    func test_unsupportedModuleTypesFailGracefully() {
        let packageData = Data("""
        {
          "package_id": "com.example.modules.unknown",
          "module_type": "unknown-module",
          "package_version": "1.0.0"
        }
        """.utf8)

        XCTAssertThrowsError(try ModulePackageManifest.fromPackageFileData(packageData)) { error in
            guard case JamfFrameworkError.unsupportedModulePackageType(let type) = error else {
                XCTFail("Expected unsupportedModulePackageType, got \(error).")
                return
            }
            XCTAssertEqual(type, "unknown-module")
        }
    }

    func test_importFailureRecordsDiagnostics() async throws {
        let packageStoreURL = temporaryPackageStoreURL()
        let invalidManifestURL = try temporaryPackageFile(
            name: "invalid.jamfmodule",
            contents: """
            {
              "package_id": "com.example.modules.invalid"
            }
            """
        )
        let diagnostics = RecordingDiagnosticsReporter()
        let manager = ModulePackageManager(
            moduleRegistry: ModuleRegistry(),
            diagnosticsReporter: diagnostics,
            packageStore: ModulePackageStore(fileURL: packageStoreURL)
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: packageStoreURL.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: invalidManifestURL.deletingLastPathComponent())
        }

        await manager.bootstrap()

        do {
            _ = try await manager.installPackage(from: invalidManifestURL)
            XCTFail("Expected invalid package import to fail.")
        } catch {
            let events = await diagnostics.recordedEvents()
            XCTAssertTrue(events.contains { $0.message == "Failed to install module package." })
            XCTAssertTrue(events.contains { $0.metadata["file_name"] == "invalid.jamfmodule" })
        }
    }

    func test_demoSeedMatchesHandoffCountsAndSafePatterns() {
        let seed = DeploymentTrackerDemoDataFactory.makeSeed()

        XCTAssertEqual(seed.devices.count, 120)
        XCTAssertEqual(seed.projects.count, 6)
        XCTAssertGreaterThanOrEqual(seed.referenceValues.count, 40)
        XCTAssertGreaterThanOrEqual(seed.workflowStatuses.count, 20)
        XCTAssertEqual(seed.workbenchLayouts.count, 4)
        XCTAssertEqual(seed.appleBusinessSnapshots.count, 30)
        XCTAssertEqual(seed.jamfPreloadSnapshots.count, 30)
        XCTAssertEqual(seed.jamfPreloadSubmissions.count, 8)
        XCTAssertEqual(seed.sdPlusExportJobs.count, 6)
        XCTAssertEqual(seed.exceptions.count, 12)
        XCTAssertGreaterThanOrEqual(seed.auditEvents.count + seed.workflowEvents.count, 40)
        XCTAssertEqual(seed.appleCatalogEntries.count, 20)
        XCTAssertTrue(seed.devices.contains { $0.serialNumber == "DEMO-MAC-0001" })
        XCTAssertTrue(seed.devices.contains { $0.serialNumber == "DEMO-IPAD-0001" })
        XCTAssertTrue(seed.devices.contains { $0.serialNumber == "DEMO-IPHONE-0001" })
        XCTAssertTrue(seed.devices.allSatisfy { $0.assignedUserEmail?.hasSuffix("@example.invalid") ?? true })
        XCTAssertTrue(seed.devices.allSatisfy { $0.ticketNumber?.hasPrefix("DEMO-SD-") ?? true })
    }

    func test_demoPreloadClientIsDeterministicAndNonNetworked() async throws {
        let seed = DeploymentTrackerDemoDataFactory.makeSeed()
        let client = DeploymentDemoJamfInventoryPreloadClient(records: seed.jamfPreloadRecords)

        let records = try await client.fetchPreloadRecords(filter: "serialNumber=='DEMO-MAC-0001'")
        let response = try await client.submitMultipart(path: "demo-path", parts: [])
        let responseText = String(data: response, encoding: .utf8) ?? ""
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: response) as? [String: String])

        XCTAssertEqual(records.map(\.serialNumber), ["DEMO-MAC-0001"])
        XCTAssertEqual(payload["mode"], "demo")
        XCTAssertEqual(payload["status"], "simulated")
        XCTAssertEqual(payload["externalDataChanged"], "false")
        XCTAssertEqual(payload["liveAction"], "false")
        XCTAssertTrue(responseText.contains("simulated"))
        XCTAssertTrue(responseText.contains("No live Jamf actions"))
    }

    func test_demoGuideIncludesRequiredTopics() {
        let topicIDs = Set(DeploymentTrackerGuideContent.topics.map(\.id))
        for topicID in DeploymentTrackerGuideContent.requiredTopicIDs {
            XCTAssertTrue(topicIDs.contains(topicID), "Missing guide topic \(topicID)")
        }
    }

    private static let deploymentTrackerPackageJSON = """
    {
      "package_id": "com.forsetti.jamfpro.feature.deployment-tracker",
      "module_type": "deployment-tracker",
      "package_version": "1.0.0",
      "module_display_name": "Deployment Tracker Demo",
      "module_subtitle": "Interactive preview of the upcoming Deployment Tracker Module. Dummy data only. No live Jamf actions.",
      "icon_system_name": "sparkles.rectangle.stack"
    }
    """

    private static let importedDeploymentTrackerPackageJSON = """
    {
      "package_id": "com.forsetti.jamfpro.feature.deployment-tracker.imported",
      "module_type": "deployment-tracker",
      "package_version": "1.0.0",
      "module_display_name": "Deployment Tracker Import Test",
      "module_subtitle": "Interactive preview of the upcoming Deployment Tracker Module. Dummy data only. No live Jamf actions.",
      "icon_system_name": "sparkles.rectangle.stack"
    }
    """

    private func temporaryPackageStoreURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ModulePackageManagerTests-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("installed-module-packages.json")
    }

    private func temporaryPackageFile(name: String, contents: String) throws -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModulePackageImportTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let fileURL = directoryURL.appendingPathComponent(name)
        try Data(contents.utf8).write(to: fileURL)
        return fileURL
    }
}

private actor RecordingDiagnosticsReporter: DiagnosticsReporting {
    private var events: [DiagnosticEvent] = []

    func report(
        source: String,
        category: String,
        severity: DiagnosticSeverity,
        message: String,
        metadata: [String: String]
    ) async {
        events.append(
            DiagnosticEvent(
                source: source,
                category: category,
                severity: severity,
                message: message,
                metadata: metadata
            )
        )
    }

    func currentEvents() async -> [DiagnosticEvent] {
        events
    }

    func renderJSONReportData() async throws -> Data {
        try JSONEncoder().encode(events)
    }

    func renderMarkdownReportData() async throws -> Data {
        let snapshot = events
        let rendered = await MainActor.run {
            snapshot.map { $0.message }.joined(separator: "\n")
        }
        return Data(rendered.utf8)
    }

    func suggestedExportFileName(extension ext: String) async -> String {
        "diagnostics.\(ext)"
    }

    func clear() async {
        events.removeAll()
    }

    func persistentLogFileURL() async -> URL? {
        nil
    }

    func recordedEvents() async -> [DiagnosticEvent] {
        events
    }
}
