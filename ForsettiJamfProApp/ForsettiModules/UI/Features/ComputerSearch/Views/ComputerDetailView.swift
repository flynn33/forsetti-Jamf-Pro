import SwiftUI
import UniformTypeIdentifiers

// "End of Line"

/// Typed routing value for `ComputerDetailView`.
///
/// Wrapping the record id in a dedicated `Hashable` type prevents collisions
/// with the dashboard's `.navigationDestination(for: String.self)` declaration
/// (which routes module IDs in `DashboardView`). Using a raw `String` route
/// would let the dashboard's destination win as the root-most handler — tapping
/// a result row would then silently navigate to the dashboard's String handler
/// instead of pushing the detail view, and SwiftUI would also log
/// "navigationDestination for 'Swift.String' was declared earlier on the stack"
/// warnings.
struct ComputerRecordRoute: Hashable {
    let id: String
}

/// Detail screen pushed from a result row when the user taps a computer.
///
/// Surfaces an identity header followed by a stack of scrollable `CategoryFrame`
/// cards — a Hardware Overview, a Security & Management grid, and one frame per
/// populated inventory section — mirroring the Support Technician detail layout.
/// On appear the view triggers a targeted refresh that requests the GENERAL,
/// HARDWARE, and STORAGE sections, guaranteeing the hardware/storage values are
/// present even when the active search profile didn't include those columns.
struct ComputerDetailView: View {
    @ObservedObject var viewModel: ComputerSearchViewModel

    /// The record id selected from the search list; the view re-resolves the
    /// live record from the view model so the latest merged values render.
    let recordID: String

    /// Set when the per-computer fetch fails; surfaces a non-fatal banner.
    @State private var refreshError: String?

    /// Drives the `.fileExporter` Save panel (both platforms).
    @State private var isExporting = false

    /// Identifier fields that get an inline copy icon next to their value.
    private let copyableFieldKeys: Set<String> = [
        "hardware.serialNumber",
        "userAndLocation.username",
        "userAndLocation.email",
        "general.lastIpAddress"
    ]

    /// Resolves the most up-to-date record for the selected id.
    private var record: ComputerRecord? {
        viewModel.searchResults.first(where: { $0.id == recordID })
    }

    var body: some View {
        Group {
            if let record {
                content(for: record)
            } else {
                ContentUnavailableView(
                    "Computer unavailable",
                    systemImage: "laptopcomputer.slash",
                    description: Text("The selected computer is no longer in the search results.")
                )
            }
        }
        .navigationTitle(record?.computerName ?? "Computer")
        .dashboardInlineNavigationTitle()
        .task(id: recordID) {
            await refreshHardwareDetails()
        }
        .toolbar {
            ToolbarItemGroup(placement: .dashboardTopBarTrailing) {
                if let record {
                    // Share the Markdown as plain text so the share sheet's Copy
                    // behaves as normal text copy/paste; Save (below) writes the file.
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
            defaultFilename: record.map { RecordMarkdown.sanitizedFileName($0.computerName) } ?? "Computer"
        ) { _ in isExporting = false }
    }

    @ViewBuilder
    private func content(for record: ComputerRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                identityHeader(record: record)

                if let refreshError {
                    Text(refreshError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 4)
                }

                CategoryFrame(
                    iconSystemName: "cpu",
                    title: "Hardware Overview",
                    bodyMaxHeight: 600
                ) {
                    ComputerHardwareInfoCard(record: record, embedded: true)
                }

                if ComputerSecurityIndicatorGrid.hasIndicators(for: record) {
                    CategoryFrame(
                        iconSystemName: "lock.shield",
                        title: "Security & Management",
                        bodyMaxHeight: 520
                    ) {
                        ComputerSecurityIndicatorGrid(record: record, embedded: true)
                    }
                }

                inventoryFrames(record: record)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .dashboardAppBackground()
    }

    @ViewBuilder
    private func identityHeader(record: ComputerRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.computerName)
                .font(.title2.weight(.semibold))

            HStack(spacing: 12) {
                if record.serialNumber.isEmpty == false {
                    Text("Serial: \(record.serialNumber)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    CopyButton(value: record.serialNumber, accessibilityLabel: "Copy serial number")
                }
                if let udid = record.udid, udid.isEmpty == false {
                    Text("UDID: \(udid)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            if let prestage = record.prestageDisplayValue, prestage.isEmpty == false {
                Text("Pre-Stage Enrollment: \(prestage)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Renders every populated catalog field grouped by inventory section, one
    /// scrollable `CategoryFrame` per section — mirroring the Support Technician
    /// detail layout. Fields already surfaced by `ComputerSecurityIndicatorGrid`
    /// are excluded so no value appears twice. The active profile decides which
    /// fields arrive populated; the section grouping/order mirrors the way Jamf
    /// organizes the inventory pane in its own UI.
    @ViewBuilder
    private func inventoryFrames(record: ComputerRecord) -> some View {
        let groupedFields = viewModel.allCatalogFields
            .filter { ComputerSecurityIndicatorGrid.configuredKeys.contains($0.key) == false }
            .filter { record.value(for: $0.key)?.isEmpty == false }
            .reduce(into: [ComputerInventorySection: [ComputerField]]()) { acc, field in
                acc[field.section, default: []].append(field)
            }

        ForEach(ComputerInventorySection.allCases, id: \.self) { section in
            if let fields = groupedFields[section], fields.isEmpty == false {
                CategoryFrame(
                    iconSystemName: sectionIcon(section),
                    title: sectionTitle(section)
                ) {
                    ForEach(fields) { field in
                        fieldRow(field, record: record)
                    }
                }
            }
        }
    }

    /// A single inventory row. Copyable identifier fields (serial / username / email / IP)
    /// get an inline copy icon beside the value; everything else renders as a plain field
    /// row. The shared `CategoryFieldRow` is wrapped, not modified, to keep modules decoupled.
    @ViewBuilder
    private func fieldRow(_ field: ComputerField, record: ComputerRecord) -> some View {
        let displayValue = ComputerFieldValueFormatter.displayString(record.value(for: field.key) ?? "")
        if copyableFieldKeys.contains(field.key), displayValue.isEmpty == false, displayValue != "—" {
            HStack(alignment: .top, spacing: 8) {
                CategoryFieldRow(label: field.displayName, value: displayValue)
                CopyButton(value: displayValue, accessibilityLabel: "Copy \(field.displayName)")
            }
        } else {
            CategoryFieldRow(label: field.displayName, value: displayValue)
        }
    }

    private func sectionTitle(_ section: ComputerInventorySection) -> String {
        switch section {
        case .general: return "General"
        case .diskEncryption: return "Disk Encryption"
        case .purchasing: return "Purchasing"
        case .userAndLocation: return "User and Location"
        case .configurationProfiles: return "Configuration Profiles"
        case .printers: return "Printers"
        case .services: return "Services"
        case .hardware: return "Hardware"
        case .storage: return "Storage"
        case .localUserAccounts: return "Local User Accounts"
        case .certificates: return "Certificates"
        case .attachments: return "Attachments"
        case .plugins: return "Plug-Ins"
        case .packageReceipts: return "Package Receipts"
        case .fonts: return "Fonts"
        case .security: return "Security"
        case .operatingSystem: return "Operating System"
        case .licensedSoftware: return "Licensed Software"
        case .ibeacons: return "iBeacons"
        case .softwareUpdates: return "Software Updates"
        case .extensionAttributes: return "Extension Attributes"
        case .contentCaching: return "Content Caching"
        case .groupMemberships: return "Group Memberships"
        }
    }

    /// SF Symbol shown in each section frame's header, matching the Support
    /// Technician category icons where the concepts line up.
    private func sectionIcon(_ section: ComputerInventorySection) -> String {
        switch section {
        case .general: return "info.bubble"
        case .diskEncryption: return "lock.rectangle.stack"
        case .purchasing: return "cart"
        case .userAndLocation: return "person.crop.circle"
        case .configurationProfiles: return "doc.badge.gearshape"
        case .printers: return "printer"
        case .services: return "gearshape.2"
        case .hardware: return "cpu"
        case .storage: return "internaldrive"
        case .localUserAccounts: return "person.2"
        case .certificates: return "checkmark.seal"
        case .attachments: return "paperclip"
        case .plugins: return "puzzlepiece.extension"
        case .packageReceipts: return "shippingbox"
        case .fonts: return "textformat"
        case .security: return "lock.shield"
        case .operatingSystem: return "macwindow"
        case .licensedSoftware: return "doc.text"
        case .ibeacons: return "dot.radiowaves.left.and.right"
        case .softwareUpdates: return "arrow.down.circle"
        case .extensionAttributes: return "tag"
        case .contentCaching: return "tray.and.arrow.down"
        case .groupMemberships: return "person.3.fill"
        }
    }

    private func refreshHardwareDetails() async {
        do {
            try await viewModel.refreshComputerHardware(id: recordID)
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
