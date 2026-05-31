import Foundation
import Combine

@MainActor
/// Manages the lifecycle of module packages: loading, installing, removing, and persisting them.
///
/// `ModulePackageManager` is the single source of truth for which module packages are installed.
/// It publishes the current list via `@Published` so SwiftUI views automatically react to changes.
/// On bootstrap it loads persisted packages from `ModulePackageStore`, ensures all bundled defaults
/// are present, and feeds the resolved modules into the `ModuleRegistry` for the rest of the app.
final class ModulePackageManager: ObservableObject {
    /// The currently installed module packages, sorted alphabetically by display title.
    @Published private(set) var installedPackages: [ModulePackageManifest] = []

    /// The shared registry that the rest of the app queries for available modules.
    private let moduleRegistry: ModuleRegistry
    /// Reporter used to log diagnostic events for all package operations.
    private let diagnosticsReporter: any DiagnosticsReporting
    /// Persistent store that reads and writes package manifests to disk.
    private let packageStore: ModulePackageStore

    /// Creates a new manager wired to the given registry, diagnostics reporter, and store.
    ///
    /// - Parameters:
    ///   - moduleRegistry: The registry that will receive resolved module instances.
    ///   - diagnosticsReporter: The reporter for logging package lifecycle events.
    ///   - packageStore: The persistence layer for module manifests; defaults to a new instance.
    init(
        moduleRegistry: ModuleRegistry,
        diagnosticsReporter: any DiagnosticsReporting,
        packageStore: ModulePackageStore = ModulePackageStore()
    ) {
        self.moduleRegistry = moduleRegistry
        self.diagnosticsReporter = diagnosticsReporter
        self.packageStore = packageStore
    }

    /// Loads persisted packages, back-fills any missing bundled defaults, and activates modules.
    ///
    /// This is the primary startup path. If loading fails entirely, the manager falls back to
    /// bundled defaults so the app always has a usable set of modules. All outcomes (success
    /// or failure) are reported through the diagnostics subsystem.
    func bootstrap() async {
        do {
            var loadedPackages = try await packageStore.loadPackages()
            // Ensure that all bundled defaults are present even if the user's persisted list is stale
            let normalizedPackages = ensureBundledDefaultsPresent(in: loadedPackages)
            if normalizedPackages != loadedPackages {
                loadedPackages = normalizedPackages
                try await packageStore.savePackages(loadedPackages)
            }

            installedPackages = sortedPackages(loadedPackages)
            applyInstalledModules()

            await diagnosticsReporter.report(
                source: "framework.module-packages",
                category: "modules",
                severity: .info,
                message: "Module package bootstrap completed.",
                metadata: [
                    "package_count": String(installedPackages.count)
                ]
            )
        } catch {
            // Fallback: use bundled defaults so the app is never empty
            let fallbackPackages = sortedPackages(ModulePackageManifest.bundledDefaults.map { $0.withInstalledDate() })
            installedPackages = fallbackPackages
            moduleRegistry.setModules(fallbackPackages.compactMap(makeModule))

            // Persist the fallback list so subsequent launches don't re-run the
            // fallback path. If saving fails too, surface that separately —
            // silently swallowing it meant the next launch would retry
            // bootstrap from the same broken state with no diagnostic trail.
            do {
                try await packageStore.savePackages(fallbackPackages)
            } catch let saveError {
                await diagnosticsReporter.reportError(
                    source: "framework.module-packages",
                    category: "modules",
                    message: "Failed to persist fallback module packages after bootstrap failure.",
                    errorDescription: describe(saveError)
                )
            }

            await diagnosticsReporter.reportError(
                source: "framework.module-packages",
                category: "modules",
                message: "Failed to bootstrap module packages.",
                errorDescription: describe(error)
            )
        }
    }

    /// Installs a new module package from a file URL (e.g., chosen via a document picker).
    ///
    /// The method handles security-scoped resource access, validates the package JSON,
    /// checks for duplicate package IDs, persists the updated list, and activates the
    /// new module in the registry.
    ///
    /// - Parameter fileURL: A file URL pointing to a JSON module package file.
    /// - Returns: The successfully installed `ModulePackageManifest`.
    /// - Throws: `JamfFrameworkError.duplicateModulePackage` if the ID already exists,
    ///   or file I/O / decoding errors.
    func installPackage(from fileURL: URL) async throws -> ModulePackageManifest {
        // Start security-scoped access for files picked via UIDocumentPickerViewController
        let hasSecurityAccess = fileURL.startAccessingSecurityScopedResource()
        defer {
            if hasSecurityAccess {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: fileURL)
            var package = try ModulePackageManifest.fromPackageFileData(data)

            // Reject duplicate package IDs (case-insensitive comparison)
            if installedPackages.contains(where: { $0.packageID.caseInsensitiveCompare(package.packageID) == .orderedSame }) {
                throw JamfFrameworkError.duplicateModulePackage(packageID: package.packageID)
            }

            let existingPackages = installedPackages
            package = package.withInstalledDate()
            let updatedPackages = sortedPackages(existingPackages + [package])

            do {
                try await packageStore.savePackages(updatedPackages)
            } catch {
                // Roll back in-memory state if persistence fails
                installedPackages = existingPackages
                throw error
            }

            installedPackages = updatedPackages
            applyInstalledModules()

            await diagnosticsReporter.report(
                source: "framework.module-packages",
                category: "modules",
                severity: .info,
                message: "Installed module package.",
                metadata: [
                    "package_id": package.packageID,
                    "module_type": package.moduleType.rawValue
                ]
            )

            return package
        } catch {
            await diagnosticsReporter.reportError(
                source: "framework.module-packages",
                category: "modules",
                message: "Failed to install module package.",
                errorDescription: describe(error),
                metadata: [
                    "file_name": fileURL.lastPathComponent
                ]
            )
            throw error
        }
    }

    /// Removes module packages at the specified index offsets, skipping bundled defaults.
    ///
    /// Bundled default packages cannot be removed; attempts to do so are silently skipped
    /// and logged as informational events. If persistence fails, the in-memory list is
    /// rolled back to its previous state.
    ///
    /// - Parameter offsets: The index set of packages to remove from `installedPackages`.
    func removePackages(at offsets: IndexSet) async {
        let existingPackages = installedPackages
        var updatedPackages = installedPackages
        var removedPackageIDs: [String] = []
        var skippedDefaultPackageIDs: [String] = []

        // Iterate in reverse order so that removing by index does not shift later indices
        for index in offsets.sorted(by: >) {
            guard updatedPackages.indices.contains(index) else {
                continue
            }

            let package = updatedPackages[index]
            // Protect bundled defaults from removal
            if package.isBundledDefault {
                skippedDefaultPackageIDs.append(package.packageID)
                continue
            }

            removedPackageIDs.append(package.packageID)
            updatedPackages.remove(at: index)
        }

        do {
            updatedPackages = ensureBundledDefaultsPresent(in: updatedPackages)
            try await packageStore.savePackages(updatedPackages)
            installedPackages = updatedPackages
            applyInstalledModules()

            await diagnosticsReporter.report(
                source: "framework.module-packages",
                category: "modules",
                severity: .warning,
                message: "Removed module packages.",
                metadata: [
                    "removed_package_count": String(removedPackageIDs.count)
                ]
            )

            if skippedDefaultPackageIDs.isEmpty == false {
                await diagnosticsReporter.report(
                    source: "framework.module-packages",
                    category: "modules",
                    severity: .info,
                    message: "Skipped removal of bundled default module packages.",
                    metadata: [
                        "skipped_package_count": String(skippedDefaultPackageIDs.count)
                    ]
                )
            }
        } catch {
            // Roll back to previous state when persistence fails
            installedPackages = existingPackages
            await diagnosticsReporter.reportError(
                source: "framework.module-packages",
                category: "modules",
                message: "Failed to persist module package removal.",
                errorDescription: describe(error)
            )
        }
    }

    // MARK: - Private Helpers

    /// Converts all installed package manifests into module instances and pushes them to the registry.
    private func applyInstalledModules() {
        let modules = installedPackages.compactMap(makeModule)
        moduleRegistry.setModules(modules)
    }

    /// Creates a concrete `JamfModule` instance from a package manifest based on its `moduleType`.
    ///
    /// Returns `nil` if the module type is not recognized (future-proofing for new types).
    ///
    /// - Parameter package: The manifest describing the module to instantiate.
    /// - Returns: A fully configured module, or `nil` if instantiation is not possible.
    private func makeModule(from package: ModulePackageManifest) -> (any JamfModule)? {
        switch package.moduleType {
        case .computerSearch:
            return ComputerSearchModule(
                id: package.packageID,
                title: package.resolvedModuleTitle,
                subtitle: package.resolvedModuleSubtitle,
                iconSystemName: package.resolvedIconSystemName
            )
        case .mobileDeviceSearch:
            return MobileDeviceSearchModule(
                id: package.packageID,
                title: package.resolvedModuleTitle,
                subtitle: package.resolvedModuleSubtitle,
                iconSystemName: package.resolvedIconSystemName
            )
        case .supportTechnician:
            return SupportTechnicianModule(
                id: package.packageID,
                title: package.resolvedModuleTitle,
                subtitle: package.resolvedModuleSubtitle,
                iconSystemName: package.resolvedIconSystemName
            )
        case .prestageDirector:
            return PrestageDirectorModule(
                id: package.packageID,
                title: package.resolvedModuleTitle,
                subtitle: package.resolvedModuleSubtitle,
                iconSystemName: package.resolvedIconSystemName
            )
        case .reports:
            return ReportsModule(
                id: package.packageID,
                title: package.resolvedModuleTitle,
                subtitle: package.resolvedModuleSubtitle,
                iconSystemName: package.resolvedIconSystemName
            )
        case .deploymentTracker:
            return DeploymentTrackerModule(
                id: package.packageID,
                title: package.resolvedModuleTitle,
                subtitle: package.resolvedModuleSubtitle,
                iconSystemName: package.resolvedIconSystemName
            )
        }
    }

    /// Sorts an array of package manifests alphabetically by their resolved display title.
    ///
    /// Uses a locale-aware, case-insensitive comparison for natural sort order.
    ///
    /// - Parameter packages: The manifests to sort.
    /// - Returns: A new array sorted by display title.
    private func sortedPackages(_ packages: [ModulePackageManifest]) -> [ModulePackageManifest] {
        packages.sorted {
            $0.resolvedModuleTitle.localizedCaseInsensitiveCompare($1.resolvedModuleTitle) == .orderedAscending
        }
    }

    /// Ensures every bundled default package is present in the given list, adding any that are missing.
    ///
    /// This guarantees that the app always ships with its core modules even if the user's
    /// persisted data has been corrupted or manually edited.
    ///
    /// - Parameter packages: The current list of packages.
    /// - Returns: A sorted list with all bundled defaults guaranteed to be present.
    private func ensureBundledDefaultsPresent(in packages: [ModulePackageManifest]) -> [ModulePackageManifest] {
        var updated = packages

        for bundledDefault in ModulePackageManifest.bundledDefaults {
            // Case-insensitive check to avoid duplicates from different casing
            if updated.contains(where: { $0.packageID.caseInsensitiveCompare(bundledDefault.packageID) == .orderedSame }) {
                continue
            }

            updated.append(bundledDefault.withInstalledDate())
        }

        return sortedPackages(updated)
    }

    /// Extracts a human-readable error description, preferring `LocalizedError.errorDescription`.
    ///
    /// - Parameter error: The error to describe.
    /// - Returns: A string suitable for diagnostic metadata.
    private func describe(_ error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}

//endofline
