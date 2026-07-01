import SwiftUI

/// A modal view that displays the full catalog of available mobile device fields
/// and lets the user toggle which fields to include in search results.
///
/// `FieldCatalogView` presents a searchable, scrollable list of all fields defined
/// in `MobileDeviceField.catalog`. Each field can be individually toggled on or off,
/// and a "Select All" toggle is provided for bulk operations. The view also includes
/// a "Save Profile" toolbar button that triggers the parent to present the profile
/// naming prompt.
///
/// The selected field keys are communicated back to the parent view via a `@Binding`,
/// so changes take effect immediately without requiring an explicit save action.
struct FieldCatalogView: View {
    /// Dismisses this modal when the user taps "Done".
    @Environment(\.dismiss) private var dismiss

    /// Two-way binding to the set of currently selected field keys,
    /// shared with the parent view model.
    @Binding var selectedFieldKeys: Set<String>

    /// Closure invoked when the user taps the "Save Profile" toolbar button.
    /// The parent is responsible for presenting the profile naming UI.
    let onSaveProfileRequested: () -> Void

    /// The current text in the search bar, used to filter the visible field list.
    @State private var filterText = ""

    // "Klatu-barada-Nikto"

    /// The subset of catalog fields matching the current search filter.
    /// Returns the full catalog when the filter is empty. Matches against
    /// the field's display name, programmatic key, and description using
    /// case-insensitive, locale-aware comparison.
    private var visibleFields: [MobileDeviceField] {
        guard filterText.isEmpty == false else {
            return MobileDeviceField.catalog
        }

        let query = filterText.localizedLowercase
        return MobileDeviceField.catalog.filter {
            $0.displayName.localizedLowercase.contains(query) ||
            $0.key.localizedLowercase.contains(query) ||
            $0.description.localizedLowercase.contains(query)
        }
    }

    /// The complete set of all field keys in the catalog, used by the
    /// "Select All" toggle to determine whether every field is selected.
    private var allCatalogFieldKeys: Set<String> {
        Set(MobileDeviceField.catalog.map(\.key))
    }

    var body: some View {
        NavigationStack {
            List {
                // Bulk selection toggle at the top of the list
                Section {
                    Toggle("Select All Fields", isOn: selectAllFieldsBinding)
                }

                // Individual field toggles with name and key displayed
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
            .dashboardInsetGroupedListStyle()
            .tint(DashboardColors.bluePrimary)
            .searchable(text: $filterText, prompt: "Find field")
            .navigationTitle("Field Catalog")
            .dashboardInlineNavigationTitle()
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
                        .foregroundStyle(DashboardColors.bluePrimary)
                    Spacer()
                    Button("Save Profile") {
                        onSaveProfileRequested()
                    }
                    .buttonStyle(.dashboardPrimary)
                    .disabled(selectedFieldKeys.isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .dashboardBottomBarSurface()
            }
        }
    }

    /// Creates a `Binding<Bool>` that reflects whether a specific field key
    /// is currently in the `selectedFieldKeys` set, and inserts or removes
    /// the key when the toggle value changes.
    ///
    /// - Parameter key: The `MobileDeviceField.key` to bind.
    /// - Returns: A binding suitable for use with a `Toggle` control.
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
    /// The getter returns `true` only when every catalog field key is present
    /// in the selection. The setter performs a union (select all) or subtraction
    /// (deselect all) on the entire catalog key set.
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
