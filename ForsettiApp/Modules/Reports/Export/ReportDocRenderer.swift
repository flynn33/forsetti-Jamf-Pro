import Foundation

struct ReportDocRenderer: ReportExportRendering {
    private let snapshotRenderer = ReportsVisualizationSnapshotRenderer()

    func render(payload: ReportExportPayload) throws -> Data {
        let png = try snapshotRenderer.pngData(for: payload.aggregate)
        let image = png.base64EncodedString()
        let html = """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <title>\(escape(payload.request.resolvedName))</title>
        <style>
        body { font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", Arial, sans-serif; color: #1f2933; margin: 32px; }
        h1 { color: #123b70; margin-bottom: 4px; }
        .meta { color: #52606d; margin-bottom: 20px; }
        .metrics { display: table; width: 100%; margin: 20px 0; }
        .metric { display: table-cell; padding: 10px; border: 1px solid #ccd6e0; }
        table { border-collapse: collapse; width: 100%; margin-top: 16px; font-size: 12px; }
        th { background: #edf4ff; text-align: left; }
        th, td { border: 1px solid #d8e1ea; padding: 6px 8px; }
        .note { margin-top: 18px; color: #5f6b7a; font-size: 12px; }
        </style>
        </head>
        <body>
        <h1>\(escape(payload.request.resolvedName))</h1>
        <div class="meta">Generated \(escape(dateFormatter.string(from: payload.generatedAt)))\(payload.serverLabel.map { " for " + escape($0) } ?? "")</div>
        <div class="metrics">
          <div class="metric"><strong>Total</strong><br>\(payload.aggregate.totalCount)</div>
          <div class="metric"><strong>Mac</strong><br>\(payload.aggregate.count(for: .mac))</div>
          <div class="metric"><strong>iPad</strong><br>\(payload.aggregate.count(for: .ipad))</div>
          <div class="metric"><strong>iPhone</strong><br>\(payload.aggregate.count(for: .iphone))</div>
          <div class="metric"><strong>Unknown</strong><br>\(payload.aggregate.count(for: .unknown))</div>
        </div>
        <img alt="Device composition chart" src="data:image/png;base64,\(image)" style="max-width: 680px; width: 100%; height: auto;">
        \(deviceTypeTable(payload.aggregate))
        \(detailTable(payload.records))
        <p class="note">Identity disclosure: \(payload.aggregate.inferredCount) records include inferred values and \(payload.aggregate.unknownCount) records include unknown type or identity values.</p>
        </body>
        </html>
        """
        return Data(html.utf8)
    }

    private func deviceTypeTable(_ aggregate: ReportAggregate) -> String {
        let rows = aggregate.orderedTypeCounts.map {
            "<tr><td>\(escape($0.type.displayName))</td><td>\($0.count)</td></tr>"
        }.joined()
        return "<h2>Device Types</h2><table><thead><tr><th>Type</th><th>Count</th></tr></thead><tbody>\(rows)</tbody></table>"
    }

    private func detailTable(_ records: [ReportDeviceRecord]) -> String {
        let rows = records.prefix(300).map { record in
            """
            <tr><td>\(escape(record.deviceType.displayName))</td><td>\(escape(record.displayName ?? ""))</td><td>\(escape(record.serialNumber ?? ""))</td><td>\(escape(record.identity.marketingName ?? record.model ?? ""))</td><td>\(escape(record.osVersion ?? ""))</td><td>\(escape(record.identity.confidence.displayName))</td></tr>
            """
        }.joined()
        let suffix = records.count > 300 ? "<p class=\"note\">Details truncated to first 300 records.</p>" : ""
        return "<h2>Details</h2><table><thead><tr><th>Type</th><th>Name</th><th>Serial</th><th>Model</th><th>OS</th><th>Confidence</th></tr></thead><tbody>\(rows)</tbody></table>\(suffix)"
    }

    private func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
