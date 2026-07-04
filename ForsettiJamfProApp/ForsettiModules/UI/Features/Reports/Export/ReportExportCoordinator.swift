import Foundation

struct ReportExportCoordinator {
    func prepare(format: ReportExportFormat, payload: ReportExportPayload) throws -> ReportExportResult {
        let renderer: any ReportExportRendering
        switch format {
        case .csv:
            renderer = ReportCSVRenderer()
        case .text:
            renderer = ReportTextRenderer()
        case .markdown:
            renderer = ReportMarkdownRenderer()
        case .doc:
            renderer = ReportDocRenderer()
        case .pdf:
            renderer = ReportPDFRenderer()
        }

        let data = try renderer.render(payload: payload)
        return ReportExportResult(
            data: data,
            filename: ReportExportFilenameBuilder.filename(
                reportName: payload.request.resolvedName,
                format: format,
                date: payload.generatedAt
            ),
            contentType: format.contentType,
            description: "\(format.displayName) export"
        )
    }
}
