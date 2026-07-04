import SwiftUI


/// The composed hardware information card used in `MobileDeviceDetailView`.
///
/// Pulls storage capacity, battery level, model identifier, and OS version
/// from a `MobileDeviceRecord`, looks up the marketing name + chip + RAM in
/// `AppleDeviceModelCatalog`, and lays them out in a single `dashboardCardSurface`
/// with the large animated Metal storage gauge on the leading edge.
///
/// Live RAM usage on iOS/iPadOS is not exposed by Apple's MDM protocol, so
/// the RAM block shows the static spec (e.g. "8 GB") with a footnote noting
/// that live usage is not available. See plan v3.19.0 — that footnote is the
/// hook for a future companion-app workflow.
struct HardwareInfoCard: View {
    let record: MobileDeviceRecord

    private var modelInfo: AppleDeviceModelInfo? {
        guard let identifier = record.modelIdentifier else { return nil }
        return AppleDeviceModelCatalog.info(for: identifier)
    }

    private var capacityMb: Int? { record.capacityMb }
    private var availableSpaceMb: Int? { record.availableSpaceMb }
    private var batteryLevel: Int? { record.batteryLevel }

    /// Used fraction 0-1 derived from capacity and available space.
    /// Falls back to the server-reported `usedSpacePercentage` when one of
    /// the megabyte values is missing — Jamf returns the percent independently
    /// for some firmware combos, so honoring it keeps coverage broad.
    private var usedFraction: Double? {
        if let capacity = capacityMb, capacity > 0,
           let available = availableSpaceMb
        {
            let used = max(0, capacity - available)
            return min(1.0, max(0.0, Double(used) / Double(capacity)))
        }

        if let percent = record.usedSpacePercentage {
            return Double(min(100, max(0, percent))) / 100.0
        }

        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            modelHeader

            HStack(alignment: .top, spacing: 20) {
                storageBlock
                batteryBlock
            }

            ramBlock
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashboardCardSurface()
    }

    // MARK: - Header (model + chip)

    @ViewBuilder
    private var modelHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(modelInfo?.marketingName ?? record.model ?? record.modelIdentifier ?? "Unknown Device")
                .font(.title3.weight(.semibold))

            if let chip = modelInfo?.chipName {
                Text(chip + chipDetailSuffix)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if let identifier = record.modelIdentifier {
                Text("Model identifier: \(identifier)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let osVersion = record.osVersion {
                Text("iOS / iPadOS \(osVersion)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Renders core/Neural specs in parentheses if any of them are known.
    /// Examples: ", 9-core CPU / 10-core GPU / 16-core Neural Engine".
    private var chipDetailSuffix: String {
        var parts: [String] = []
        if let cpu = modelInfo?.cpuCoreCount {
            parts.append("\(cpu)-core CPU")
        }
        if let gpu = modelInfo?.gpuCoreCount {
            parts.append("\(gpu)-core GPU")
        }
        if let neural = modelInfo?.neuralCoreCount {
            parts.append("\(neural)-core Neural Engine")
        }
        return parts.isEmpty ? "" : " — " + parts.joined(separator: " / ")
    }

    // MARK: - Storage block

    @ViewBuilder
    private var storageBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Storage", systemImage: "internaldrive")
                .font(.subheadline.weight(.semibold))

            if let usedFraction {
                // Slim progress-bar look. 10pt is comparable to a SwiftUI
                // ProgressView's track height; the shader's pill ends and
                // fwidth-based antialiasing keep edges crisp at this size.
                // `.inline` keeps the renderer paused / event-driven so the
                // bar costs near-zero idle GPU at this size.
                HardwareStorageGaugeView(usedFraction: usedFraction, style: .inline)
                    .frame(height: 10)
                    .padding(.vertical, 4)

                HStack(spacing: 12) {
                    if let capacity = capacityMb {
                        labeledMetric(
                            value: format(megabytes: capacity),
                            caption: "Total"
                        )
                    }
                    if let available = availableSpaceMb {
                        labeledMetric(
                            value: format(megabytes: available),
                            caption: "Free"
                        )
                    }
                    labeledMetric(
                        value: "\(Int((usedFraction * 100).rounded()))%",
                        caption: "Used"
                    )
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Storage not reported")
                        .font(.body)
                    Text("This device hasn't sent its storage figures to Jamf yet. The Jamf admin can ask the device to update its inventory.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Battery block

    @ViewBuilder
    private var batteryBlock: some View {
        VStack(alignment: .center, spacing: 8) {
            Label("Battery", systemImage: "battery.100")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

            if let battery = batteryLevel {
                HardwareBatteryRingView(percent: battery, diameter: 88)
                if let health = record.batteryHealth {
                    Text("Health: \(health)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else if let health = record.batteryHealth {
                // Battery level isn't reported but iOS 17+ DDM is sending
                // categorical health. Render a styled card showing the
                // health classification so the user still gets meaningful
                // battery information.
                VStack(spacing: 4) {
                    Image(systemName: "battery.100bolt")
                        .font(.title)
                        .foregroundStyle(batteryHealthColor(for: health))
                    Text(health)
                        .font(.callout.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Text("Health classification")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 110, height: 88)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(batteryHealthColor(for: health).opacity(0.08))
                )
            } else {
                Text("Battery not reported")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(height: 88)
            }
        }
    }

    /// Apple uses a small set of categorical strings for battery health on
    /// iOS 17+ DDM ("Normal", "Service Recommended", "Unknown", etc.). Map
    /// them to the same green/yellow/red palette used in the ring view.
    private func batteryHealthColor(for health: String) -> Color {
        let lowered = health.lowercased()
        if lowered.contains("service") || lowered.contains("non-genuine") || lowered.contains("warning") {
            return Color(red: 0.92, green: 0.30, blue: 0.30)
        }
        if lowered.contains("unknown") {
            return Color(red: 0.95, green: 0.78, blue: 0.20)
        }
        return Color(red: 0.18, green: 0.72, blue: 0.40)
    }

    // MARK: - RAM block

    @ViewBuilder
    private var ramBlock: some View {
        let resolvedRam = modelInfo?.ramGB(capacityMb)
        VStack(alignment: .leading, spacing: 4) {
            Label("Memory", systemImage: "memorychip")
                .font(.subheadline.weight(.semibold))

            if let ram = resolvedRam {
                Text("\(ram) GB total")
                    .font(.body.weight(.medium))
            } else if let modelNumber = record.modelNumber {
                Text("Model number: \(modelNumber)")
                    .font(.body.weight(.medium))
                Text("Total memory will appear once the device reports its full hardware identifier.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if record.modelIdentifier != nil {
                Text("Memory not yet available for this model.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Memory not reported.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Text("Live memory usage isn't available from iOS or iPadOS over MDM today. A companion app will provide it in a future release.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Formatting helpers

    /// Renders a metric in vertically-stacked label/caption form for the
    /// storage block's numeric callouts.
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

    /// Formats megabyte values as either "47 GB" (≥ 1 GB) or "512 MB" (smaller).
    /// Uses base-10 GB for closer alignment with how Apple advertises capacity
    /// in marketing materials, which is what users compare the value against.
    private func format(megabytes: Int) -> String {
        if megabytes >= 1024 {
            let gb = Double(megabytes) / 1024.0
            return gb >= 100
                ? "\(Int(gb.rounded())) GB"
                : String(format: "%.1f GB", gb)
        } else {
            return "\(megabytes) MB"
        }
    }
}

//endofline
