import SwiftUI

// "Klatu-barada-Nikto"

/// Composed Mac hardware card shown at the top of `ComputerDetailView`.
///
/// All numbers and derivations come from `ComputerHardwareVisualizationModel`, a
/// pure Metal-free value type built from the `ComputerRecord` (populated by the
/// detail-open hardware refresh) plus the `AppleMacModelCatalog` lookup. This
/// view is presentation only — it never decides a spec, so the card can't claim
/// a value the model can't substantiate.
///
/// The storage gauge is the shared `HardwareStorageGaugeView`, which renders with
/// Metal when available and falls back to a pure-SwiftUI bar otherwise — Metal is
/// presentation only and never required for correctness.
struct ComputerHardwareInfoCard: View {
    let record: ComputerRecord

    /// When embedded inside a `CategoryFrame`, the card drops its own padding and
    /// `dashboardCardSurface()` so the surrounding frame supplies the chrome — avoiding a
    /// card-within-a-card. Standalone callers keep the original surfaced look.
    var embedded: Bool = false

    var body: some View {
        let viz = ComputerHardwareVisualizationModel(record: record)
        let core = VStack(alignment: .leading, spacing: 16) {
            modelHeader(viz)
            specsRow(viz)

            HStack(alignment: .top, spacing: 20) {
                storagePanel(viz)
                    .frame(maxWidth: .infinity, alignment: .leading)
                batteryPanel(viz)
                    .frame(width: 150, alignment: .top)
            }

            sourceFooter(viz)
        }
        .padding(embedded ? 0 : 20)
        .frame(maxWidth: .infinity, alignment: .leading)

        if embedded {
            core
        } else {
            core.dashboardCardSurface()
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func modelHeader(_ viz: ComputerHardwareVisualizationModel) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(viz.marketingName)
                .font(.title3.weight(.semibold))

            if let chip = viz.chipName {
                Text(chip)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let identifier = record.modelIdentifier, identifier.isEmpty == false {
                Text(identifier)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let osVersion = record.osVersion, osVersion.isEmpty == false {
                Text("macOS \(osVersion)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Specs row (CPU / GPU / Neural / Memory)

    @ViewBuilder
    private func specsRow(_ viz: ComputerHardwareVisualizationModel) -> some View {
        HStack(alignment: .top, spacing: 18) {
            labeledMetric(value: viz.cpuCoresDisplay ?? "—", caption: "CPU Cores")
                .frame(maxWidth: .infinity, alignment: .leading)
            labeledMetric(value: viz.gpuCoresDisplay ?? "—", caption: "GPU Cores")
                .frame(maxWidth: .infinity, alignment: .leading)
            labeledMetric(value: viz.neuralCoresDisplay ?? "—", caption: "Neural")
                .frame(maxWidth: .infinity, alignment: .leading)
            labeledMetric(value: viz.memoryDisplay ?? "—", caption: "Memory")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Storage panel

    @ViewBuilder
    private func storagePanel(_ viz: ComputerHardwareVisualizationModel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Storage", systemImage: "internaldrive")
                .font(.subheadline.weight(.semibold))

            if let usedFraction = viz.storageUsedFraction {
                HardwareStorageGaugeView(usedFraction: usedFraction, style: .inline)
                    .frame(height: 10)
                    .padding(.vertical, 4)

                HStack(spacing: 12) {
                    if let total = record.totalStorageMb {
                        labeledMetric(value: ComputerHardwareVisualizationModel.format(megabytes: total), caption: "Total")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let free = record.bootDriveAvailableMb {
                        labeledMetric(value: ComputerHardwareVisualizationModel.format(megabytes: free), caption: "Free")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    labeledMetric(
                        value: "\(Int((usedFraction * 100).rounded()))%",
                        caption: "Used"
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Storage not reported")
                        .font(.body)
                    Text("This Mac hasn't sent its storage figures to Jamf yet. Ask it to update inventory to populate the gauge.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Battery panel

    @ViewBuilder
    private func batteryPanel(_ viz: ComputerHardwareVisualizationModel) -> some View {
        VStack(alignment: .center, spacing: 8) {
            Label("Battery", systemImage: "battery.100")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

            switch viz.batteryState {
            case let .reported(capacity):
                HardwareBatteryRingView(percent: capacity, diameter: 88)
                Text("Max capacity")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            case .notApplicable:
                VStack(spacing: 4) {
                    Image(systemName: "desktopcomputer")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text("Not applicable")
                        .font(.callout.weight(.semibold))
                    Text("Desktop Mac")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(width: 110, height: 88)
            case .notReported:
                Text("Battery not reported")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(height: 88)
            }
        }
    }

    // MARK: - Confidence / source footer

    @ViewBuilder
    private func sourceFooter(_ viz: ComputerHardwareVisualizationModel) -> some View {
        if let info = viz.modelInfo {
            HStack(spacing: 6) {
                Image(systemName: confidenceSymbol(info.confidence))
                    .font(.caption)
                    .foregroundStyle(confidenceColor(info.confidence))
                Text(viz.confidenceText ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func confidenceSymbol(_ confidence: AppleMacModelInfo.Confidence) -> String {
        switch confidence {
        case .exact, .high: return "checkmark.seal"
        case .medium: return "info.circle"
        case .low: return "exclamationmark.triangle"
        case .unknown: return "questionmark.circle"
        }
    }

    private func confidenceColor(_ confidence: AppleMacModelInfo.Confidence) -> Color {
        switch confidence {
        case .exact, .high: return Color(red: 0.18, green: 0.72, blue: 0.40)
        case .medium: return .secondary
        case .low: return Color(red: 0.95, green: 0.78, blue: 0.20)
        case .unknown: return .secondary
        }
    }

    // MARK: - Formatting helpers

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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(caption): \(value)")
    }
}

//endofline
