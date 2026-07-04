import SwiftUI

// "Klatu-barada-Nikto"

/// Field-selection sheet for the Advanced Search criterion editor.
///
/// Lists every catalog field with `isFilterable == true`, grouped by inventory
/// section, with a search bar at the top for quick filtering. Picking a row
/// returns the chosen `MobileDeviceField` to the caller via the `onSelect`
/// closure and dismisses.
struct AdvancedFieldPickerView: View {
    let availableFields: [MobileDeviceField]
    let onSelect: (MobileDeviceField) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""

    /// Filterable fields only (the picker is for query criteria, not display
    /// columns). Filtered live by `searchText` matching display name, key, or
    /// description.
    private var matchingFields: [MobileDeviceField] {
        let filterable = availableFields.filter { $0.isFilterable }
        guard searchText.isEmpty == false else {
            return filterable
        }
        let needle = searchText.lowercased()
        return filterable.filter { field in
            field.displayName.lowercased().contains(needle)
                || field.key.lowercased().contains(needle)
                || field.description.lowercased().contains(needle)
        }
    }

    /// Section -> fields, sorted by display name within each section. Used to
    /// render the grouped list.
    ///
    /// The Extension Attributes section is forced into the result even if
    /// no EA fields matched the search/filter — the picker renders an
    /// empty-state row inside it so the user can see the section exists and
    /// know whether the EA load succeeded. Other sections are skipped when
    /// they would be empty.
    private var groupedFields: [(MobileDeviceInventorySection, [MobileDeviceField])] {
        let grouped = Dictionary(grouping: matchingFields, by: \.section)
        return MobileDeviceInventorySection.allCases.compactMap { section in
            let fields = grouped[section] ?? []
            if fields.isEmpty {
                // Always show the EA section even when empty so the user has
                // a place to look for extension attributes.
                return section == .extensionAttributes ? (section, []) : nil
            }
            let sorted = fields.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            return (section, sorted)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groupedFields, id: \.0) { section, fields in
                    Section(sectionTitle(section)) {
                        if fields.isEmpty {
                            extensionAttributeEmptyState
                        } else {
                            ForEach(fields) { field in
                                Button {
                                    onSelect(field)
                                    dismiss()
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(field.displayName)
                                        Text(field.description)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search fields")
            .navigationTitle("Choose a field")
            .dashboardInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .dashboardTopBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        // macOS sheets without an explicit frame collapse to a tiny default
        // size — the system has no parent window to inherit from when a sheet
        // opens above another sheet. Mirror the FieldCatalogView and
        // AdvancedSearchView sizing so this picker is readable and scrollable.
#if os(macOS)
        .frame(minWidth: 720, idealWidth: 820, minHeight: 600, idealHeight: 720)
#endif
    }

    /// Placeholder rendered inside the Extension Attributes section when no
    /// EA fields are available. Helps the user distinguish "tenant has no
    /// EAs" from "EA load is still pending or failed" at a glance — a more
    /// detailed error is logged to Diagnostics by the view model's loader.
    @ViewBuilder
    private var extensionAttributeEmptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("No extension attributes available")
                .font(.body)
            Text("If your Jamf Pro instance has mobile-device extension attributes configured, close this picker, reopen Advanced Search, and check the Diagnostics tab if they still don't appear.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func sectionTitle(_ section: MobileDeviceInventorySection) -> String {
        switch section {
        case .general: return "General"
        case .location: return "User and Location"
        case .hardware: return "Hardware"
        case .purchasing: return "Purchasing"
        case .security: return "Security"
        case .applications: return "Applications"
        case .ebooks: return "E-Books"
        case .network: return "Network"
        case .serviceSubscriptions: return "Service Subscriptions"
        case .certificates: return "Certificates"
        case .configurationProfiles: return "Configuration Profiles"
        case .userProfiles: return "User Profiles"
        case .provisioningProfiles: return "Provisioning Profiles"
        case .sharedUsers: return "Shared Users"
        case .extensionAttributes: return "Extension Attributes"
        case .mobileDeviceGroups: return "Mobile Device Groups"
        }
    }
}

//endofline
