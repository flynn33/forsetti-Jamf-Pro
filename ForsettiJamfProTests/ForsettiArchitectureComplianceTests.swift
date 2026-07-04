import XCTest

@MainActor
final class ForsettiArchitectureComplianceTests: XCTestCase {
    func test_appDefinesRequiredLocalRuntimeTypes() throws {
        let source = try String(
            contentsOf: repoRoot.appending(path: "ForsettiJamfProApp/ForsettiRuntime/ForsettiRuntimeCore.swift"),
            encoding: .utf8
        )
        let requiredSnippets = [
            "struct SemVer",
            "struct ModuleManifest",
            "struct ModuleDescriptor",
            "final class ManifestLoader",
            "enum Capability",
            "enum ModuleType",
            "final class ModuleRegistry",
            "final class RuntimeController",
            "final class ServiceContainer",
            "final class EventBus",
            "struct CompatibilityChecker",
            "final class CapabilityPolicy",
            "protocol ActivationStore"
        ]

        for snippet in requiredSnippets {
            XCTAssertTrue(source.contains(snippet), "Missing local runtime component: \(snippet)")
        }
    }

    func test_legacyModuleRuntimeSymbolsAreNotInProductionSource() throws {
        let forbidden = [
            "DashboardFeature" + "Workspace",
            "Feature" + "WorkspaceContext",
            "DashboardFeature" + "Catalog",
            "Feature" + "Package",
            "Module" + "Package",
            "Module" + "PackageTemplates"
        ]

        for fileURL in try sourceFiles(under: repoRoot.appending(path: "ForsettiJamfProApp")) {
            guard !fileURL.path.contains("/Resources/") else {
                continue
            }
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            for symbol in forbidden {
                XCTAssertFalse(source.contains(symbol), "\(symbol) remains in \(fileURL.path)")
            }
        }
    }

    func test_serviceModulesDoNotImportSwiftUI() throws {
        let servicesURL = repoRoot.appending(path: "ForsettiJamfProApp/ForsettiModules/Services")
        for fileURL in try sourceFiles(under: servicesURL) {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            XCTAssertFalse(source.contains("import SwiftUI"), "Service module imports SwiftUI: \(fileURL.path)")
        }
    }

    func test_projectUsesAppOwnedRuntimeAndNoFrameworkPackageProducts() throws {
        let project = try String(
            contentsOf: repoRoot.appending(path: "Forsetti Jamf Pro.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )
        XCTAssertFalse(project.contains("XCLocal" + "SwiftPackageReference"))
        XCTAssertFalse(project.contains("XCRemote" + "SwiftPackageReference"))
        XCTAssertFalse(project.contains("Forsetti-Framework" + "-Mac-iOS-main"))
        XCTAssertFalse(project.contains("productName = Forsetti" + "Core"))
        XCTAssertFalse(project.contains("productName = Forsetti" + "Platform"))
        XCTAssertFalse(project.contains("productName = Forsetti" + "HostTemplate"))
        XCTAssertFalse(project.contains("ForsettiModules" + "Example"))
    }

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func sourceFiles(under rootURL: URL) throws -> [URL] {
        let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey]
        guard let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        return try enumerator.compactMap { item in
            guard let url = item as? URL else {
                return nil
            }
            let values = try url.resourceValues(forKeys: resourceKeys)
            guard values.isRegularFile == true else {
                return nil
            }
            return ["swift", "md"].contains(url.pathExtension) ? url : nil
        }
    }
}
