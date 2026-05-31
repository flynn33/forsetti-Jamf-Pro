import SwiftUI

struct ComputerRecordRoute: Hashable {
    let id: String
}

struct ComputerDetailView: View {
    @ObservedObject var viewModel: ComputerSearchViewModel
    let recordID: String

    @State private var refreshError: String?

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
                    systemImage: "desktopcomputer.trianglebadge.exclamationmark",
                    description: Text("The selected computer is no longer in the search results.")
                )
            }
        }
        .navigationTitle(record?.computerName ?? "Computer")
        .forsettiInlineNavigationTitle()
        .task(id: recordID) {
            await refreshHardwareDetails()
        }
    }

    @ViewBuilder
    private func content(for record: ComputerRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                identityHeader(record: record)

                ComputerHardwareInfoCard(record: record)

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
        .forsettiAppBackground()
    }

    @ViewBuilder
    private func identityHeader(record: ComputerRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.computerName)
                .font(.title2.weight(.semibold))
            HStack(spacing: 12) {
                Text("Serial: \(record.serialNumber)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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

    @ViewBuilder
    private func fieldDetails(record: ComputerRecord) -> some View {
        let groupedFields = ComputerField.catalog
            .filter { record.value(for: $0.key)?.isEmpty == false }
            .reduce(into: [ComputerInventorySection: [ComputerField]]()) { acc, field in
                acc[field.section, default: []].append(field)
            }

        if groupedFields.isEmpty == false {
            VStack(alignment: .leading, spacing: 12) {
                Text("Inventory Details")
                    .font(.headline)

                ForEach(ComputerInventorySection.allCases, id: \.self) { section in
                    if let fields = groupedFields[section], fields.isEmpty == false {
                        sectionGroup(title: section.rawValue.replacingOccurrences(of: "_", with: " ").capitalized, fields: fields, record: record)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sectionGroup(
        title: String,
        fields: [ComputerField],
        record: ComputerRecord
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                ForEach(fields) { field in
                    HStack(alignment: .top, spacing: 12) {
                        Text(field.displayName)
                            .frame(width: 200, alignment: .leading)
                            .foregroundStyle(.secondary)
                            .font(.callout)
                        Text(record.value(for: field.key) ?? "-")
                            .font(.callout)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 6)
                    Divider().opacity(0.3)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .forsettiCardSurface()
    }

    private func refreshHardwareDetails() async {
        do {
            try await viewModel.refreshComputerHardware(id: recordID)
            refreshError = nil
        } catch {
            refreshError = "Live hardware refresh failed. Showing the most recent data."
        }
    }
}

private struct ComputerHardwareInfoCard: View {
    let record: ComputerRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            HStack(alignment: .top, spacing: 20) {
                storageBlock
                batteryBlock
            }

            HStack(alignment: .top, spacing: 16) {
                metricBlock(title: "Memory", systemImage: "memorychip", value: memorySummary, detail: record.totalRamMegabytes.map { "\($0) MB reported" })
                metricBlock(title: "Processor", systemImage: "cpu", value: processorSummary, detail: record.appleSilicon.map { "Apple silicon: \($0)" })
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .forsettiCardSurface()
    }

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.model ?? record.modelIdentifier ?? "Unknown Mac")
                .font(.title3.weight(.semibold))
            if let modelIdentifier = record.modelIdentifier {
                Text("Model identifier: \(modelIdentifier)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let osVersion = record.osVersion {
                let build = record.osBuild.map { " (\($0))" } ?? ""
                Text("macOS \(osVersion)\(build)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var storageBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Storage", systemImage: "internaldrive")
                .font(.subheadline.weight(.semibold))

            if let usedFraction = record.storageUsedFraction {
                HardwareStorageGaugeView(usedFraction: usedFraction, style: .inline)
                    .frame(height: 10)
                    .padding(.vertical, 4)

                HStack(spacing: 12) {
                    if let total = record.storageTotalMegabytes {
                        labeledMetric(value: format(megabytes: total), caption: "Total")
                    }
                    if let available = record.storageAvailableMegabytes {
                        labeledMetric(value: format(megabytes: available), caption: "Free")
                    }
                    labeledMetric(value: "\(Int((usedFraction * 100).rounded()))%", caption: "Used")
                }
            } else {
                Text("Storage not reported")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(height: 48, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var batteryBlock: some View {
        VStack(alignment: .center, spacing: 8) {
            Label("Battery", systemImage: "battery.100")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

            if let battery = record.batteryCapacityPercentInt {
                HardwareBatteryRingView(percent: battery, diameter: 88)
            } else {
                Text("Battery not reported")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(height: 88)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var memorySummary: String {
        guard let memory = record.totalRamMegabytesInt else {
            return "Not reported"
        }
        return format(megabytes: memory)
    }

    private var processorSummary: String {
        record.processorType ?? record.modelIdentifier ?? "Not reported"
    }

    @ViewBuilder
    private func metricBlock(title: String, systemImage: String, value: String, detail: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
            Text(value)
                .font(.body.weight(.medium))
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func labeledMetric(value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.callout.weight(.semibold))
                .monospacedDigit()
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
    }

    private func format(megabytes: Int) -> String {
        if megabytes >= 1_048_576 {
            return String(format: "%.2f TB", Double(megabytes) / 1_048_576.0)
        }
        if megabytes >= 1024 {
            return String(format: "%.0f GB", Double(megabytes) / 1024.0)
        }
        return "\(megabytes) MB"
    }
}
