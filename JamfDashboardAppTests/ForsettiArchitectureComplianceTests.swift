import XCTest

@MainActor
final class ForsettiArchitectureComplianceTests: XCTestCase {
    func test_appDoesNotDefineLocalForsettiRuntimeTypes() throws {
        let forbiddenPattern = #"(?m)(^|[^A-Za-z])(struct|enum|class)\s+(SemVer|ModuleManifest|ModuleDescriptor|ManifestLoader|Capability|ModuleType|ModuleRegistry|ForsettiRuntime|ForsettiContext)([^A-Za-z]|$)"#
        let regex = try NSRegularExpression(pattern: forbiddenPattern)

        for fileURL in try sourceFiles(under: repoRoot.appending(path: "JamfDashboardApp")) {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            let range = NSRange(source.startIndex..<source.endIndex, in: source)
            XCTAssertNil(
                regex.firstMatch(in: source, range: range),
                "Local Forsetti runtime/model type definition found in \(fileURL.path)"
            )
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

        for fileURL in try sourceFiles(under: repoRoot.appending(path: "JamfDashboardApp")) {
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
        let servicesURL = repoRoot.appending(path: "JamfDashboardApp/ForsettiModules/Services")
        for fileURL in try sourceFiles(under: servicesURL) {
            let source = try String(contentsOf: fileURL, encoding: .utf8)
            XCTAssertFalse(source.contains("import SwiftUI"), "Service module imports SwiftUI: \(fileURL.path)")
        }
    }

    func test_projectLinksRequiredForsettiProductsAndNotExampleProduct() throws {
        let project = try String(
            contentsOf: repoRoot.appending(path: "Jamf Dashboard.xcodeproj/project.pbxproj"),
            encoding: .utf8
        )
        XCTAssertTrue(project.contains("ForsettiCore"))
        XCTAssertTrue(project.contains("ForsettiPlatform"))
        XCTAssertTrue(project.contains("ForsettiHostTemplate"))
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
