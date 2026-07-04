import SwiftUI

struct ReportMetricCardView: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 112, maxHeight: 112, alignment: .topLeading)
        .padding(14)
        .dashboardCardSurface()
    }
}

struct ReportSegmentedGaugePanel: View {
    let aggregate: ReportAggregate

    var body: some View {
        // VStack is centered so the title, the (square) gauge, and the
        // color-key grid all share the same horizontal axis inside the
        // card — the composition panel reads as a single centered hero
        // unit instead of mixing leading-aligned text with a centered
        // gauge.
        VStack(alignment: .center, spacing: DashboardTheme.Spacing.item) {
            Text("Composition")
                .font(.headline.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .center)

            ReportsDeviceTypeGaugeView(aggregate: aggregate)
                .frame(maxWidth: 360)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
                ForEach(aggregate.orderedTypeCounts, id: \.type) { item in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(ReportsChartPalette.color(for: item.type))
                            .frame(width: 10, height: 10)
                        Text(item.type.displayName)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Text(item.count.formatted())
                            .font(.caption.monospacedDigit())
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .dashboardCardSurface()
    }
}

struct ReportRankedBarChartView: View {
    let title: String
    let values: [String: Int]
    /// Maximum height the scrollable content area is allowed to grow to.
    /// Anything beyond this height scrolls within the card so the page
    /// stays compact while still showing every ranked entry.
    var maxContentHeight: CGFloat = 360

    private var ranked: [(String, Int)] {
        values.sorted {
            if $0.value == $1.value {
                return $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending
            }
            return $0.value > $1.value
        }
        .map { ($0.key, $0.value) }
    }

    private var maxValue: Int {
        max(ranked.map(\.1).max() ?? 1, 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DashboardTheme.Spacing.item) {
            HStack {
                Text(title)
                    .font(.headline.weight(.semibold))
                Spacer()
                if ranked.isEmpty == false {
                    Text("\(ranked.count.formatted()) entr\(ranked.count == 1 ? "y" : "ies")")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if ranked.isEmpty {
                Text("No values available.")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(ranked, id: \.0) { label, count in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(label)
                                        .font(.caption)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer()
                                    Text(count.formatted())
                                        .font(.caption.monospacedDigit())
                                        .lineLimit(1)
                                }
                                GeometryReader { proxy in
                                    let fraction = CGFloat(count) / CGFloat(maxValue)
                                    ZStack(alignment: .leading) {
                                        Capsule()
                                            .fill(.secondary.opacity(0.16))
                                        Capsule()
                                            .fill(DashboardColors.bluePrimary)
                                            .frame(width: max(6, proxy.size.width * fraction))
                                    }
                                }
                                .frame(height: 8)
                            }
                        }
                    }
                }
                .frame(maxHeight: maxContentHeight)
            }
        }
        .padding(16)
        .dashboardCardSurface()
    }
}

struct ReportDistributionMeterView: View {
    let title: String
    let values: [String: Int]

    private var total: Int {
        max(values.values.reduce(0, +), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DashboardTheme.Spacing.item) {
            Text(title)
                .font(.headline.weight(.semibold))
            ForEach(values.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                HStack {
                    Text(key)
                    Spacer()
                    Text(value.formatted())
                        .monospacedDigit()
                }
                .font(.caption)
                ProgressView(value: Double(value), total: Double(total))
                    .tint(DashboardColors.greenPrimary)
            }
        }
        .padding(16)
        .dashboardCardSurface()
    }
}

struct ReportDataTableView: View {
    enum SortKey: String, CaseIterable, Identifiable {
        case type
        case name
        case model
        case os
        case enrolled
        case confidence

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .type: return "Type"
            case .name: return "Name"
            case .model: return "Model"
            case .os: return "OS"
            case .enrolled: return "Enrolled"
            case .confidence: return "Confidence"
            }
        }
    }

    let records: [ReportDeviceRecord]
    @State private var sortKey: SortKey = .name

    private var sortedRecords: [ReportDeviceRecord] {
        records.sorted {
            value(for: $0, key: sortKey).localizedCaseInsensitiveCompare(value(for: $1, key: sortKey)) == .orderedAscending
        }
    }

    /// Maximum height the scrolling rows area is allowed to reach inside
    /// the details card. The sort picker and column header stay pinned
    /// above the scroll region, so the user can sort and scan an arbitrary
    /// number of rows without the card pushing other panels off-screen.
    var maxRowsHeight: CGFloat = 520

    var body: some View {
        VStack(alignment: .leading, spacing: DashboardTheme.Spacing.item) {
            HStack {
                Text("Details")
                    .font(.headline.weight(.semibold))
                Spacer()
                Text("\(records.count.formatted()) record\(records.count == 1 ? "" : "s")")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Picker("Sort", selection: $sortKey) {
                    ForEach(SortKey.allCases) { key in
                        Text(key.displayName).tag(key)
                    }
                }
                .pickerStyle(.menu)
            }

            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    reportHeader

                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(sortedRecords) { record in
                                ReportDataRow(record: record)
                                Divider()
                            }
                        }
                    }
                    .frame(maxHeight: maxRowsHeight)
                }
                .frame(minWidth: 760)
            }
        }
        .padding(16)
        .dashboardCardSurface()
    }

    private var reportHeader: some View {
        HStack {
            Text("Type").frame(width: 78, alignment: .leading)
            Text("Name").frame(maxWidth: .infinity, alignment: .leading)
            Text("Model").frame(maxWidth: .infinity, alignment: .leading)
            Text("OS").frame(width: 82, alignment: .leading)
            Text("Enrolled").frame(width: 104, alignment: .leading)
            Text("Confidence").frame(width: 136, alignment: .leading)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.vertical, 6)
    }

    private func value(for record: ReportDeviceRecord, key: SortKey) -> String {
        switch key {
        case .type: return record.deviceType.displayName
        case .name: return record.displayName ?? ""
        case .model: return record.identity.marketingName ?? record.model ?? ""
        case .os: return record.osVersion ?? ""
        case .enrolled: return record.value(for: "enrollmentDate") ?? ""
        case .confidence: return record.identity.confidence.displayName
        }
    }
}

private struct ReportDataRow: View {
    let record: ReportDeviceRecord

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(record.deviceType.displayName)
                .lineLimit(1)
                .frame(width: 78, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.displayName ?? "Unnamed")
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(record.serialNumber ?? "No serial")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(record.identity.marketingName ?? record.model ?? "Unknown")
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(record.osVersion ?? "")
                .frame(width: 82, alignment: .leading)
                .lineLimit(1)
            Text(record.value(for: "enrollmentDate") ?? "—")
                .frame(width: 104, alignment: .leading)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(record.identity.confidence.displayName)
                .frame(width: 136, alignment: .leading)
                .foregroundStyle(record.identity.confidence.isInferred ? .orange : .secondary)
                .lineLimit(1)
        }
        .font(.caption)
        .padding(.vertical, 8)
    }
}
