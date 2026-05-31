import SwiftUI

/// The primary view for the Computer Search module, providing a search interface,
/// profile management, and a results list for Jamf Pro computer inventory queries.
///
/// This view is organized into three sections:
/// 1. **Search** -- A text field for the query, a profile picker, field catalog access, and a search button.
/// 2. **Search Profiles** -- A list of saved profiles that can be tapped to apply or swiped to delete.
/// 3. **Results** -- The list of `ComputerRecord` rows returned by the most recent search.
///
/// The view also presents a sheet for the field catalog and an alert for saving new profiles.
struct ComputerSearchView: View {
    /// The view model that drives search execution, profile management, and state.
    @StateObject private var viewModel: ComputerSearchViewModel

    /// Creates the search view with an injected view model.
    ///
    /// - Parameter viewModel: The `ComputerSearchViewModel` that manages all search logic and state.
    init(viewModel: ComputerSearchViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        List {
            // MARK: - Search Input Section
            Section("Search") {
                HStack(spacing: 8) {
                    TextField("Computer name, serial, username, email", text: $viewModel.query.strippingControlCharacters())
                        .forsettiNoAutoCorrectionTextInput()

                    // Barcode/QR scanner button for quick serial or asset tag entry
                    ScanIntoTextFieldButton(text: $viewModel.query.strippingControlCharacters())
                }

                Picker("Search Profile", selection: $viewModel.selectedProfileID) {
                    Text("None").tag(nil as UUID?)
                    ForEach(viewModel.profiles) { profile in
                        Text(profile.name).tag(profile.id as UUID?)
                    }
                }
                .pickerStyle(.menu)

                HStack {
                    Button("Fields") {
                        viewModel.isFieldCatalogPresented = true
                    }
                    .buttonStyle(.forsettiSecondary)

                    Spacer()

                    Button {
                        Task {
                            await viewModel.executeSearch()
                        }
                    } label: {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    .buttonStyle(.forsettiPrimary)
                }
            }

            // MARK: - Error Display
            if let errorMessage = viewModel.errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            // MARK: - Decoding Notice (non-fatal degraded response)
            if let notice = viewModel.decodingNoticeMessage {
                Section {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }

            // MARK: - Saved Profiles Section
            if viewModel.profiles.isEmpty == false {
                Section("Search Profiles") {
                    ForEach(viewModel.profiles) { profile in
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(profile.name)
                                Text("\(profile.fieldKeys.count) fields")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            // Checkmark badge indicates the currently active profile
                            if viewModel.selectedProfileID == profile.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(ForsettiColors.greenPrimary)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            viewModel.selectedProfileID = profile.id
                            viewModel.applySelectedProfileFields()
                        }
                    }
                    .onDelete(perform: viewModel.deleteProfiles)
                }
            }

            // MARK: - Results Section
            Section("Results") {
                if viewModel.isSearching {
                    ProgressView("Searching Jamf Pro...")
                } else if viewModel.searchResults.isEmpty {
                    Text("No results yet. Run a search to view computers.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(viewModel.searchResults) { record in
                        ComputerResultRow(record: record)
                    }
                }
            }
        }
        .forsettiInsetGroupedListStyle()
        .task {
            // Load saved profiles from disk when the view first appears
            await viewModel.loadProfiles()
        }
        .onChange(of: viewModel.selectedProfileID) { _, _ in
            viewModel.applySelectedProfileFields()
        }
        .sheet(isPresented: $viewModel.isFieldCatalogPresented) {
            ComputerFieldCatalogView(
                selectedFieldKeys: $viewModel.selectedFieldKeys,
                onSaveProfileRequested: {
                    viewModel.isFieldCatalogPresented = false

                    // Brief delay to let the sheet dismissal animation complete before showing the alert
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 200_000_000)
                        viewModel.presentSaveProfilePrompt()
                    }
                }
            )
            #if os(macOS)
            .frame(minWidth: 720, idealWidth: 820, minHeight: 600, idealHeight: 720)
            #endif
        }
        .alert("Save Search Profile", isPresented: $viewModel.isSaveProfilePromptPresented) {
            TextField("Profile name", text: $viewModel.pendingProfileName)

            Button("Cancel", role: .cancel) { }
            Button("Save") {
                Task {
                    await viewModel.saveProfileFromPrompt()
                }
            }
        } message: {
            Text("This profile stores the currently selected field toggles.")
        }
    }
}

/// A row view that displays a single computer record in the search results list.
///
/// Shows the computer name and serial number prominently, then conditionally renders
/// additional details (model, OS, user, email, IP, asset tag, prestage, UDID) only
/// when those fields contain non-empty values.
private struct ComputerResultRow: View {
    /// The computer record to display.
    let record: ComputerRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Primary identifier: the computer's display name
            Text(record.computerName)
                .font(ForsettiSearchResultTypography.headline())

            // Always show the serial number as the secondary identifier
            Text("Serial: \(record.serialNumber)")
                .font(ForsettiSearchResultTypography.subheadline())

            // Conditional detail rows -- only shown when the data is present and non-empty
            if let model = record.model {
                Text("Model: \(model)")
                    .font(ForsettiSearchResultTypography.caption())
                    .foregroundStyle(.secondary)
            }

            if let osVersion = record.osVersion {
                // Append the build number in parentheses if available
                let osBuildSuffix = record.osBuild.map { " (\($0))" } ?? ""
                Text("OS: \(osVersion)\(osBuildSuffix)")
                    .font(ForsettiSearchResultTypography.caption())
                    .foregroundStyle(.secondary)
            }

            if let username = record.username, username.isEmpty == false {
                Text("User: \(username)")
                    .font(ForsettiSearchResultTypography.caption())
                    .foregroundStyle(.secondary)
            }

            if let email = record.email, email.isEmpty == false {
                Text("Email: \(email)")
                    .font(ForsettiSearchResultTypography.caption())
                    .foregroundStyle(.secondary)
            }

            if let ipAddress = record.lastIpAddress, ipAddress.isEmpty == false {
                Text("Last IP: \(ipAddress)")
                    .font(ForsettiSearchResultTypography.caption())
                    .foregroundStyle(.secondary)
            }

            if let assetTag = record.assetTag, assetTag.isEmpty == false {
                Text("Asset Tag: \(assetTag)")
                    .font(ForsettiSearchResultTypography.caption())
                    .foregroundStyle(.secondary)
            }

            if let prestageDisplay = record.prestageDisplayValue, prestageDisplay.isEmpty == false {
                Text("Pre-Stage Enrollment: \(prestageDisplay)")
                    .font(ForsettiSearchResultTypography.caption())
                    .foregroundStyle(.secondary)
            }

            if let udid = record.udid {
                Text("UDID: \(udid)")
                    .font(ForsettiSearchResultTypography.caption2())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 4)
    }
}

//endofline
