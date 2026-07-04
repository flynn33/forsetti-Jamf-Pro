import Foundation
import UniformTypeIdentifiers

enum ReportExportFormat: String, CaseIterable, Identifiable, Sendable {
    case csv
    case text
    case markdown
    case doc
    case pdf

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .csv: return "CSV"
        case .text: return "TXT"
        case .markdown: return "Markdown"
        case .doc: return "DOC"
        case .pdf: return "PDF"
        }
    }

    var fileExtension: String {
        switch self {
        case .csv: return "csv"
        case .text: return "txt"
        case .markdown: return "md"
        case .doc: return "doc"
        case .pdf: return "pdf"
        }
    }

    var systemImage: String {
        switch self {
        case .csv: return "tablecells"
        case .text: return "doc.plaintext"
        case .markdown: return "doc.richtext"
        case .doc: return "doc.text"
        case .pdf: return "doc.fill"
        }
    }

    var contentType: UTType {
        switch self {
        case .csv:
            return .commaSeparatedText
        case .text:
            return .plainText
        case .markdown:
            return UTType(filenameExtension: "md") ?? .plainText
        case .doc:
            return UTType(filenameExtension: "doc") ?? .rtf
        case .pdf:
            return .pdf
        }
    }
}

struct ReportExportPayload: Sendable {
    let request: ReportRequest
    let dataSet: ReportDataSet
    let aggregate: ReportAggregate

    var generatedAt: Date { dataSet.generatedAt }
    var serverLabel: String? { dataSet.serverLabel }
    var records: [ReportDeviceRecord] { dataSet.records }
}

struct ReportExportResult: Sendable {
    let data: Data
    let filename: String
    let contentType: UTType
    let description: String
}

protocol ReportExportRendering {
    func render(payload: ReportExportPayload) throws -> Data
}
