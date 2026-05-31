import SwiftUI

/// A full-screen modal view that displays the complete catalog of Jamf Pro computer inventory fields
/// and lets the user toggle which fields to include in their search.
///
/// The view presents a searchable, scrollable list of all fields from `ComputerField.catalog`.
/// Each field can be individually toggled on or off, and a "Select All" toggle is provided
/// for bulk operations. A "Save Profile" toolbar button allows the user to persist the current
/// selection as a named `ComputerSearchProfile` for later reuse.
struct ComputerFieldCatalogView: View {
    /// Dismisses this modal when the user taps "Done".
    @Environment(\.dismiss) private var dismiss

    /// A two-way binding to the set of currently selected field keys, shared with the parent view model.
    @Binding var selectedFieldKeys: Set<String>

    /// A callback invoked when the user taps the "Save Profile" toolbar button.
    let onSaveProfileRequested: () -> Void

    /// The text entered into the search bar, used to filter the visible field list.
    @State private var filterText = ""

    /// Returns the filtered list of fields based on the current search text.
    ///
    /// When the filter is empty, all catalog fields are shown. Otherwise, fields are matched
    /// case-insensitively against their display name, API key, or description.
    private var visibleFields: [ComputerField] {
        guard filterText.isEmpty == false else {
            return ComputerField.catalog
        }

        let query = filterText.localizedLowercase
        return ComputerField.catalog.filter {
            $0.displayName.localizedLowercase.contains(query) ||
            $0.key.localizedLowercase.contains(query) ||
            $0.description.localizedLowercase.contains(query)
        }
    }

    /// The complete set of all field keys in the catalog, used for "Select All" logic.
    private var allCatalogFieldKeys: Set<String> {
        Set(ComputerField.catalog.map(\.key))
    }

    var body: some View {
        NavigationStack {
            List {
                // Master toggle that selects or deselects every field at once
                Section {
                    Toggle("Select All Fields", isOn: selectAllFieldsBinding)
                }

                // Individual field toggles with name and API key displayed
                Section("Fields") {
                    ForEach(visibleFields) { field in
                        Toggle(isOn: toggleBinding(for: field.key)) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(field.displayName)
                                    .font(.body)
                                Text(field.key)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .forsettiInsetGroupedListStyle()
            .tint(ForsettiColors.bluePrimary)
            .searchable(text: $filterText, prompt: "Find field")
            .navigationTitle("Field Catalog")
            .forsettiInlineNavigationTitle()
            .toolbar {
                // Apple HIG sheet dismiss: .confirmationAction. Save Profile
                // stays in the bottom bar.
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                // Sticky footer showing selection count and the primary
                // Save Profile action.
                HStack(spacing: 12) {
                    Text("\(selectedFieldKeys.count) selected")
                        .font(.caption)
                        .foregroundStyle(ForsettiColors.bluePrimary)
                    Spacer()
                    Button("Save Profile") {
                        onSaveProfileRequested()
                    }
                    .buttonStyle(.forsettiPrimary)
                    .disabled(selectedFieldKeys.isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .forsettiBottomBarSurface()
            }
        }
    }

    /// Creates a `Binding<Bool>` for a single field key that inserts or removes the key
    /// from the shared `selectedFieldKeys` set when toggled.
    ///
    /// - Parameter key: The inventory field key to bind (e.g. `"hardware.serialNumber"`).
    /// - Returns: A binding that reflects and mutates the selection state for this field.
    private func toggleBinding(for key: String) -> Binding<Bool> {
        Binding(
            get: { selectedFieldKeys.contains(key) },
            set: { isSelected in
                if isSelected {
                    selectedFieldKeys.insert(key)
                } else {
                    selectedFieldKeys.remove(key)
                }
            }
        )
    }

    /// A computed binding for the "Select All" toggle.
    ///
    /// The getter returns `true` only when every catalog field is currently selected.
    /// The setter unions or subtracts the full catalog key set from the selection.
    private var selectAllFieldsBinding: Binding<Bool> {
        Binding(
            get: {
                allCatalogFieldKeys.isEmpty == false &&
                allCatalogFieldKeys.isSubset(of: selectedFieldKeys)
            },
            set: { isSelected in
                if isSelected {
                    selectedFieldKeys.formUnion(allCatalogFieldKeys)
                } else {
                    selectedFieldKeys.subtract(allCatalogFieldKeys)
                }
            }
        )
    }
}

//endofline
