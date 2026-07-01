import SwiftUI

struct GeneratedReportView: View {
    let report: GeneratedReport
    @ObservedObject var viewModel: ReportsViewModel

    @State private var isFormatPickerPresented = false
    @State private var exportDocument: ReportExportDocument?
    @State private var exportFilename = "forsetti-report"
    @State private var exportContentType = ReportExportFormat.pdf.contentType
    @State private var exportDescription = "report export"
    @State private var isExporterPresented = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DashboardTheme.Spacing.section) {
                header
                metricGrid

                if anyOfRow1 {
                    visualRow1
                }

                if anyOfRow2 {
                    visualRow2
                }

                if report.aggregate.inferredCount > 0 || report.aggregate.unknownCount > 0 {
                    disclosurePanel
                }

                if frames.contains(.detailsTable) {
                    ReportDataTableView(records: report.dataSet.records)
                }
            }
            .padding(DashboardTheme.Spacing.section)
        }
        .dashboardAppBackground()
        .toolbar {
            ToolbarItem(placement: .dashboardTopBarTrailing) {
                Button {
                    isFormatPickerPresented = true
                } label: {
                    Label("Export", systemImage: "square.and.arrow.down")
                }
                .disabled(report.dataSet.records.isEmpty)
            }
        }
        .sheet(isPresented: $isFormatPickerPresented) {
            ReportFormatPickerView { format in
                isFormatPickerPresented = false
                prepareExport(format)
            }
#if os(macOS)
            .frame(minWidth: 560, idealWidth: 620, minHeight: 360, idealHeight: 420)
#endif
        }
        .fileExporter(
            isPresented: $isExporterPresented,
            document: exportDocument,
            contentType: exportContentType,
            defaultFilename: exportFilename
        ) { result in
            let description = exportDescription
            exportDocument = nil
            viewModel.recordExportCompletion(result: result, description: description)
        }
    }

    /// Convenience accessor — the frame selection lives on the report's
    /// originating request and is the source of truth for which visual
    /// panels render.
    private var frames: Set<ReportFrame> {
        report.request.frames
    }

    private var anyOfRow1: Bool {
        frames.contains(.compositionGauge)
            || frames.contains(.topModels)
            || frames.contains(.locations)
    }

    private var anyOfRow2: Bool {
        frames.contains(.osVersions)
            || frames.contains(.storage)
            || frames.contains(.battery)
    }

    /// Row 1 — composition gauge alongside the model and location ranked-bars.
    /// `ViewThatFits` chooses the side-by-side HStack when the window can
    /// host both columns and falls back to a stacked VStack otherwise. Each
    /// child is conditionally included so the row collapses gracefully when
    /// the user opts out of one or more frames.
    @ViewBuilder
    private var visualRow1: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: DashboardTheme.Spacing.section) {
                if frames.contains(.compositionGauge) {
                    ReportSegmentedGaugePanel(aggregate: report.aggregate)
                        .frame(maxWidth: 430)
                }
                VStack(spacing: DashboardTheme.Spacing.section) {
                    if frames.contains(.topModels) {
                        ReportRankedBarChartView(title: "Top Models", values: report.aggregate.countsByModel)
                    }
                    if frames.contains(.locations) {
                        ReportRankedBarChartView(title: "Locations", values: report.aggregate.countsByLocation)
                    }
                }
            }

            VStack(spacing: DashboardTheme.Spacing.section) {
                if frames.contains(.compositionGauge) {
                    ReportSegmentedGaugePanel(aggregate: report.aggregate)
                }
                if frames.contains(.topModels) {
                    ReportRankedBarChartView(title: "Top Models", values: report.aggregate.countsByModel)
                }
                if frames.contains(.locations) {
                    ReportRankedBarChartView(title: "Locations", values: report.aggregate.countsByLocation)
                }
            }
        }
    }

    /// Row 2 — OS Versions ranked-bar plus the optional Storage and Battery
    /// distribution meters. Same `ViewThatFits` + conditional-child pattern
    /// as row 1.
    @ViewBuilder
    private var visualRow2: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: DashboardTheme.Spacing.section) {
                if frames.contains(.storage) {
                    ReportDistributionMeterView(title: "Storage", values: report.aggregate.storageBuckets)
                }
                if frames.contains(.battery) {
                    ReportDistributionMeterView(title: "Battery", values: report.aggregate.batteryBuckets)
                }
                if frames.contains(.osVersions) {
                    ReportRankedBarChartView(title: "OS Versions", values: report.aggregate.countsByOSVersion)
                }
            }
            VStack(spacing: DashboardTheme.Spacing.section) {
                if frames.contains(.storage) {
                    ReportDistributionMeterView(title: "Storage", values: report.aggregate.storageBuckets)
                }
                if frames.contains(.battery) {
                    ReportDistributionMeterView(title: "Battery", values: report.aggregate.batteryBuckets)
                }
                if frames.contains(.osVersions) {
                    ReportRankedBarChartView(title: "OS Versions", values: report.aggregate.countsByOSVersion)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(report.request.resolvedName)
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                Text(criteriaSummary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Generated \(report.dataSet.generatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var metricGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: DashboardTheme.Spacing.item)], spacing: DashboardTheme.Spacing.item) {
            ReportMetricCardView(title: "Total", value: report.aggregate.totalCount.formatted(), systemImage: "number", tint: DashboardColors.bluePrimary)
            ReportMetricCardView(title: "Mac", value: report.aggregate.count(for: .mac).formatted(), systemImage: ReportDeviceType.mac.symbolName, tint: ReportsChartPalette.color(for: .mac))
            ReportMetricCardView(title: "iPad", value: report.aggregate.count(for: .ipad).formatted(), systemImage: ReportDeviceType.ipad.symbolName, tint: ReportsChartPalette.color(for: .ipad))
            ReportMetricCardView(title: "iPhone", value: report.aggregate.count(for: .iphone).formatted(), systemImage: ReportDeviceType.iphone.symbolName, tint: ReportsChartPalette.color(for: .iphone))
            ReportMetricCardView(title: "Unknown", value: report.aggregate.count(for: .unknown).formatted(), systemImage: ReportDeviceType.unknown.symbolName, tint: ReportsChartPalette.color(for: .unknown))
        }
    }

    private var disclosurePanel: some View {
        Label {
            Text("\(report.aggregate.inferredCount) records include inferred identity values. \(report.aggregate.unknownCount) records include unknown type or identity values.")
                .font(.footnote)
        } icon: {
            Image(systemName: "info.circle")
        }
        .foregroundStyle(.secondary)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .dashboardCardSurface()
    }

    private var criteriaSummary: String {
        guard report.request.criteria.isEmpty == false else {
            return "Domain: \(report.request.domain.displayName). No criteria."
        }
        let criteria = report.request.criteria.compactMap { criterion -> String? in
            guard let field = ReportsFieldCatalog.field(for: criterion.fieldKey) else { return nil }
            return "\(field.displayName) \(criterion.comparison.displayName.lowercased()) \(criterion.value)"
        }.joined(separator: "; ")
        return "Domain: \(report.request.domain.displayName). \(criteria)"
    }

    private func prepareExport(_ format: ReportExportFormat) {
        Task { @MainActor in
            guard let result = await viewModel.prepareExport(format: format, report: report) else {
                return
            }
            exportDocument = ReportExportDocument(data: result.data, contentType: result.contentType)
            exportFilename = result.filename
            exportContentType = result.contentType
            exportDescription = result.description
            isExporterPresented = true
        }
    }
}

private struct ReportFormatPickerView: View {
    @Environment(\.dismiss) private var dismiss
    let onSelect: (ReportExportFormat) -> Void

    var body: some View {
        NavigationStack {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 14)], spacing: 14) {
                ForEach(ReportExportFormat.allCases) { format in
                    Button {
                        onSelect(format)
                    } label: {
                        // Symmetric centered chip: icon on top, format name
                        // mid-card, extension label at the bottom. Reads as
                        // a clean file-type tile instead of a left-aligned
                        // text block.
                        VStack(alignment: .center, spacing: 10) {
                            Image(systemName: format.systemImage)
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(DashboardColors.bluePrimary)
                            Text(format.displayName)
                                .font(.headline)
                            Text(".\(format.fileExtension)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 110, alignment: .center)
                        .padding(14)
                        .dashboardCardSurface()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(DashboardTheme.Spacing.section)
            .navigationTitle("Export")
            .dashboardInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
