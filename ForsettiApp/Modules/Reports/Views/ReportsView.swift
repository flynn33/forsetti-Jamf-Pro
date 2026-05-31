import SwiftUI

struct ReportsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: ReportsViewModel
    @State private var isBuilderPresented = false
    @State private var activeReport: GeneratedReport?
    @State private var showZeroRows = false

    init(viewModel: ReportsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ForsettiTheme.Spacing.section) {
                header
                statusStrip
                content
            }
            .padding(ForsettiTheme.Spacing.section)
        }
        .forsettiAppBackground()
        .task {
            if viewModel.defaultDataSet == nil {
                // First appear of the module — the inventory service's
                // cache is empty, so there is nothing to invalidate. The
                // load itself triggers the cache build.
                await viewModel.refreshDefaultCounts(forceCacheRebuild: false)
            }
        }
        .toolbar {
            ToolbarItem(placement: .forsettiTopBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Label("Home", systemImage: "house")
                }
            }
            ToolbarItem(placement: .forsettiTopBarTrailing) {
                Button {
                    // Toolbar Refresh — discard the cache and re-fetch.
                    Task { await viewModel.refreshDefaultCounts(forceCacheRebuild: true) }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.isRefreshing)
            }
        }
        .sheet(isPresented: $isBuilderPresented) {
            // `ReportBuilderView` carries its own macOS sheet sizing
            // (matching `AdvancedSearchView` and the other field-catalog
            // sheets), so the parent does not need to override it here.
            ReportBuilderView(
                isGenerating: viewModel.isGenerating,
                onGenerate: { request in
                    if let report = await viewModel.generateReport(request: request) {
                        isBuilderPresented = false
                        activeReport = report
                    }
                }
            )
        }
        .navigationDestination(item: $activeReport) { report in
            GeneratedReportView(report: report, viewModel: viewModel)
                .navigationTitle(report.request.resolvedName)
                .forsettiInlineNavigationTitle()
        }
        .alert(
            "Reports",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { isPresented in
                    if isPresented == false {
                        viewModel.errorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error")
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Reports")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                Text("Visual Jamf Pro inventory reporting")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                isBuilderPresented = true
            } label: {
                Label("New Report", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.forsettiPrimary)
            .disabled(viewModel.isGenerating)
        }
    }

    private var statusStrip: some View {
        HStack(spacing: ForsettiTheme.Spacing.item) {
            statusItem(
                title: "Server",
                value: viewModel.serverLabel ?? (viewModel.hasCredentials ? "Configured" : "Credentials Required"),
                image: viewModel.hasCredentials ? "checkmark.seal.fill" : "lock.trianglebadge.exclamationmark"
            )
            statusItem(
                title: "Last Refresh",
                value: viewModel.lastRefreshDate.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Not Loaded",
                image: "clock"
            )
            if viewModel.isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .forsettiCardSurface()
    }

    private func statusItem(title: String, value: String, image: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.footnote.weight(.semibold))
            }
        } icon: {
            Image(systemName: image)
                .foregroundStyle(ForsettiColors.bluePrimary)
        }
        .labelStyle(.titleAndIcon)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isRefreshing && viewModel.defaultDataSet == nil {
            ProgressView("Loading report counts...")
                .frame(maxWidth: .infinity, minHeight: 280)
                .forsettiCardSurface()
        } else if viewModel.hasCredentials == false {
            ContentUnavailableView(
                "Credentials Required",
                systemImage: "lock.trianglebadge.exclamationmark",
                description: Text("Save verified Jamf Pro credentials in Settings before loading report data.")
            )
            .frame(maxWidth: .infinity, minHeight: 280)
            .forsettiCardSurface()
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: ForsettiTheme.Spacing.section) {
                    deviceTypeList
                        .frame(minWidth: 340, maxWidth: 460, alignment: .topLeading)
                    gaugePanel
                }
                VStack(alignment: .leading, spacing: ForsettiTheme.Spacing.section) {
                    deviceTypeList
                    gaugePanel
                }
            }
        }
    }

    private var deviceTypeList: some View {
        VStack(alignment: .leading, spacing: ForsettiTheme.Spacing.item) {
            HStack {
                Text("Device Types")
                    .font(.headline.weight(.semibold))
                Spacer()
                Toggle("Show Zeros", isOn: $showZeroRows)
                    .toggleStyle(.switch)
                    .font(.caption)
            }

            ForEach(rowsToShow, id: \.type) { item in
                HStack(spacing: 12) {
                    Circle()
                        .fill(ReportsChartPalette.color(for: item.type))
                        .frame(width: 12, height: 12)
                    Image(systemName: item.type.symbolName)
                        .foregroundStyle(.secondary)
                        .frame(width: 22)
                    Text(item.type.displayName)
                    Spacer()
                    Text(item.count.formatted())
                        .font(.headline.monospacedDigit())
                }
                .padding(.vertical, 6)
            }
        }
        .padding(16)
        .forsettiCardSurface()
    }

    private var gaugePanel: some View {
        VStack(spacing: ForsettiTheme.Spacing.item) {
            ReportsDeviceTypeGaugeView(aggregate: viewModel.aggregate)
                .frame(minWidth: 260, idealWidth: 340, maxWidth: 420)

            colorKey
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .forsettiCardSurface()
    }

    private var colorKey: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 94), spacing: 8)], spacing: 8) {
            ForEach(ReportDeviceType.displayOrder, id: \.self) { type in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(ReportsChartPalette.color(for: type))
                        .frame(width: 14, height: 10)
                    Text(type.displayName)
                        .font(.caption)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var rowsToShow: [(type: ReportDeviceType, count: Int)] {
        showZeroRows ? viewModel.aggregate.orderedTypeCounts : viewModel.aggregate.nonZeroTypeCounts
    }
}
