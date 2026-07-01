import SwiftUI
import UniformTypeIdentifiers

// "Klatu-barada-Nikto"

/// Typed routing value for `MobileDeviceDetailView`.
///
/// Wrapping the record id in a dedicated `Hashable` type prevents collisions
/// with the dashboard's `.navigationDestination(for: String.self)` declaration
/// (which routes module IDs). Using a raw `String` would let the dashboard's
/// destination win as the root-most handler — tapping a result row would then
/// silently navigate to the dashboard's String handler instead of pushing the
/// detail view, and SwiftUI would also log "navigationDestination for
/// 'Swift.String' was declared earlier on the stack" warnings.
struct MobileDeviceRecordRoute: Hashable {
    let id: String
}

/// Detail screen pushed from a `MobileDeviceResultRow` when the user taps a row.
///
/// Surfaces the hardware information card (storage gauge, battery, chip, RAM)
/// alongside a fields list grouped by inventory section. The view triggers a
/// targeted refresh on appear that requests the GENERAL and HARDWARE sections,
/// guaranteeing the hardware card has the values it needs even when the active
/// search profile didn't include those fields.
struct MobileDeviceDetailView: View {
    @ObservedObject var viewModel: MobileDeviceSearchViewModel

    /// The record id selected from the search list; the view re-resolves the
    /// live record from the view model so the latest fetched values render.
    let recordID: String

    /// Set when the per-device fetch fails; surfaces a non-fatal banner.
    @State private var refreshError: String?

    /// Drives the `.fileExporter` Save panel (both platforms).
    @State private var isExporting = false

    /// Identifier fields that get an inline copy icon next to their value.
    private let copyableFieldKeys: Set<String> = ["serialNumber", "username", "emailAddress", "ipAddress"]

    /// Resolves the most up-to-date record for the selected ID.
    private var record: MobileDeviceRecord? {
        viewModel.searchResults.first(where: { $0.id == recordID })
    }

    var body: some View {
        Group {
            if let record {
                content(for: record)
            } else {
                ContentUnavailableView(
                    "Device unavailable",
                    systemImage: "iphone.gen3.slash",
                    description: Text("The selected device is no longer in the search results.")
                )
            }
        }
        .navigationTitle(record?.deviceName ?? "Device")
        .dashboardInlineNavigationTitle()
        .task(id: recordID) {
            await refreshHardwareDetails()
        }
        .toolbar {
            ToolbarItemGroup(placement: .dashboardTopBarTrailing) {
                if let record {
                    // Share the Markdown as plain text so the share sheet's Copy (and
                    // Messages/Mail/Teams) behave as normal text copy/paste. Saving the
                    // `.md` file is handled separately by the Save button below.
                    ShareLink(item: RecordMarkdown.document(for: [record])) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Button { } label: { Label("Share", systemImage: "square.and.arrow.up") }
                        .disabled(true)
                }
                Button { isExporting = true } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .disabled(record == nil)
            }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: TextFileDocument(text: RecordMarkdown.document(for: record.map { [$0] } ?? [])),
            contentType: .dashboardMarkdown,
            defaultFilename: record.map { RecordMarkdown.sanitizedFileName($0.deviceName) } ?? "Device"
        ) { _ in isExporting = false }
    }

    @ViewBuilder
    private func content(for record: MobileDeviceRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                identityHeader(record: record)

                HardwareInfoCard(record: record)

                if let refreshError {
                    Text(refreshError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 4)
                }

                fieldDetails(record: record)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .dashboardAppBackground()
    }

    @ViewBuilder
    private func identityHeader(record: MobileDeviceRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.deviceName)
                .font(.title2.weight(.semibold))
            HStack(spacing: 12) {
                if record.serialNumber.isEmpty == false {
                    HStack(spacing: 4) {
                        Text("Serial: \(record.serialNumber)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        CopyButton(value: record.serialNumber, accessibilityLabel: "Copy serial number")
                    }
                }
                if let udid = record.udid {
                    Text("UDID: \(udid)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    /// Renders every catalog field that has a non-empty value on this record,
    /// grouped by inventory section. The active profile decides which fields
    /// arrive populated; the section grouping mirrors the way Jamf organizes
    /// the inventory pane in its own UI.
    @ViewBuilder
    private func fieldDetails(record: MobileDeviceRecord) -> some View {
        let groupedFields = MobileDeviceField.catalog
            .filter { record.value(for: $0.key)?.isEmpty == false }
            .reduce(into: [MobileDeviceInventorySection: [MobileDeviceField]]()) { acc, field in
                acc[field.section, default: []].append(field)
            }

        if groupedFields.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("Inventory Details")
                    .font(.headline)

                ForEach(MobileDeviceInventorySection.allCases, id: \.self) { section in
                    if let fields = groupedFields[section], fields.isEmpty == false {
                        sectionGroup(title: sectionTitle(section), fields: fields, record: record)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sectionGroup(
        title: String,
        fields: [MobileDeviceField],
        record: MobileDeviceRecord
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                ForEach(fields) { field in
                    let fieldValue = record.value(for: field.key)
                    HStack(alignment: .top, spacing: 12) {
                        Text(field.displayName)
                            .frame(width: 180, alignment: .leading)
                            .foregroundStyle(.secondary)
                            .font(.callout)
                        Text(fieldValue ?? "—")
                            .font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let fieldValue, fieldValue.isEmpty == false, copyableFieldKeys.contains(field.key) {
                            CopyButton(value: fieldValue, accessibilityLabel: "Copy \(field.displayName)")
                        }
                    }
                    .padding(.vertical, 6)
                    Divider().opacity(0.3)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashboardCardSurface()
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

    private func refreshHardwareDetails() async {
        do {
            try await viewModel.refreshDeviceHardware(id: recordID)
            refreshError = nil
        } catch {
            // Surface the failure but keep the cached row data visible — the
            // row already had whatever the search response carried, so a
            // refresh failure doesn't leave the user with a blank screen.
            refreshError = "Live hardware refresh failed. Showing the most recent data."
        }
    }
}

//endofline
