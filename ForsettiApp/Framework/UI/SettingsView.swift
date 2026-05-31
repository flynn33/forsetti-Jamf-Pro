import SwiftUI
import UniformTypeIdentifiers

/// The main settings screen providing access to Jamf credential configuration,
/// module package management (import, view, and remove), and the About page.
/// Presented as a modal sheet from the dashboard.
struct SettingsView: View {
    /// Dismiss action to close the settings sheet.
    @Environment(\.dismiss) private var dismiss

    /// The shared credentials store, observed to display current credential status.
    @ObservedObject var credentialsStore: JamfCredentialsStore
    /// Optional diagnostics reporter passed through to sub-views for event logging.
    let diagnosticsReporter: (any DiagnosticsReporting)?
    /// The module package manager that handles installation, listing, and removal of module packages.
    @ObservedObject var modulePackageManager: ModulePackageManager

    /// Controls whether the JSON file importer dialog is shown for adding module packages.
    @State private var isModuleImporterPresented = false
    /// A success/status message displayed after module package operations.
    @State private var modulePackageStatusMessage: String?
    /// An error message displayed in an alert when a module package operation fails.
    @State private var modulePackageErrorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Top bar with a Home button to dismiss the settings sheet
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Label("Home", systemImage: "house.fill")
                            .font(.headline)
                    }
                    .buttonStyle(.forsettiSecondary)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, ForsettiTheme.Spacing.section)
                .padding(.top, ForsettiTheme.Spacing.compact)
                .padding(.bottom, 4)

                List {
                    Section("Configuration") {
                        NavigationLink {
                            ServerCredentialsView(
                                credentialsStore: credentialsStore,
                                diagnosticsReporter: diagnosticsReporter
                            )
                        } label: {
                            Label("Jamf Credentials", systemImage: "key.fill")
                        }
                    }

                    Section("Module Packages") {
                        Button {
                            isModuleImporterPresented = true
                        } label: {
                            Label("Add Module Package", systemImage: "plus.square.on.square")
                        }

                        if modulePackageManager.installedPackages.isEmpty {
                            Text("No module packages installed.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(modulePackageManager.installedPackages) { package in
                                ModulePackageRow(package: package)
                            }
                            .onDelete(perform: removePackages)
                        }

                        Text("Import a JSON module package manifest. Computer Search, Mobile Device Search, and Prestage Director are bundled with the framework and remain preinstalled by default.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let modulePackageStatusMessage {
                        Section {
                            Text(modulePackageStatusMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Section("About") {
                        NavigationLink {
                            AboutView()
                        } label: {
                            Label("About Forsetti", systemImage: "info.circle")
                        }
                    }
                }
                .forsettiInsetGroupedListStyle()
            }
            .fileImporter(
                isPresented: $isModuleImporterPresented,
                allowedContentTypes: [.json],
                allowsMultipleSelection: false
            ) { result in
                handleModulePackageImport(result: result)
            }
            .navigationTitle("Settings")
            .forsettiInlineNavigationTitle()
            // Sheet root: no back button needed — the single Close button below
            // dismisses the sheet. Adding .forsettiBackButtonToolbar() here created a
            // second leading chevron with ambiguous behavior.
            .toolbar {
                // Apple HIG sheet dismiss: .confirmationAction renders as the
                // bold trailing button on iOS and the blue primary button on
                // macOS. Matches Mail/Calendar/Settings conventions.
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert(
                "Module Package Error",
                isPresented: Binding(
                    get: { modulePackageErrorMessage != nil },
                    set: { isPresented in
                        if isPresented == false {
                            modulePackageErrorMessage = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(modulePackageErrorMessage ?? "Unknown error.")
            }
        }
    }

    /// Processes the result from the file importer dialog. Extracts the first selected URL
    /// and kicks off an async module package installation.
    /// - Parameter result: The file importer result containing selected URLs or an error.
    private func handleModulePackageImport(result: Result<[URL], Error>) {
        switch result {
        case let .success(urls):
            guard let url = urls.first else {
                return
            }

            Task {
                await installModulePackage(from: url)
            }
        case let .failure(error):
            modulePackageStatusMessage = nil
            modulePackageErrorMessage = error.localizedDescription
        }
    }

    /// Reads and installs a module package manifest from the given file URL.
    /// On success, shows the installed module title and version. On failure, shows an error alert.
    /// - Parameter fileURL: The local file URL of the JSON module package manifest.
    private func installModulePackage(from fileURL: URL) async {
        do {
            let installedPackage = try await modulePackageManager.installPackage(from: fileURL)
            modulePackageStatusMessage = "Installed \(installedPackage.resolvedModuleTitle) (\(installedPackage.packageVersion))."
            modulePackageErrorMessage = nil
        } catch {
            modulePackageStatusMessage = nil
            modulePackageErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Removes module packages at the given index set from the installed list via swipe-to-delete.
    /// - Parameter offsets: The index offsets of packages to remove.
    private func removePackages(at offsets: IndexSet) {
        Task {
            await modulePackageManager.removePackages(at: offsets)
            modulePackageStatusMessage = "Updated installed module packages."
            modulePackageErrorMessage = nil
        }
    }
}

/// A row displaying details about an installed module package, including its title,
/// type, package ID, version, and whether it is a bundled default module.
private struct ModulePackageRow: View {
    /// The module package manifest to display.
    let package: ModulePackageManifest

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(package.resolvedModuleTitle)
                .font(.subheadline.weight(.semibold))

            Text("Type: \(package.moduleType.rawValue)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Package ID: \(package.packageID)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Text("Version: \(package.packageVersion)")
                .font(.caption2)
                .foregroundStyle(.secondary)

            // Highlight bundled modules so the user knows they cannot be removed
            if package.isBundledDefault {
                Text("Bundled default module")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(ForsettiColors.bluePrimary)
            }
        }
        .padding(.vertical, 2)
    }
}

//endofline
