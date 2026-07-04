import SwiftUI
import UniformTypeIdentifiers

struct ReportExportDocument: FileDocument {
    var data: Data
    var contentType: UTType

    static var readableContentTypes: [UTType] {
        [.commaSeparatedText, .plainText, .text, .pdf, UTType(filenameExtension: "doc") ?? .rtf]
    }

    static var writableContentTypes: [UTType] {
        readableContentTypes
    }

    init(data: Data, contentType: UTType) {
        self.data = data
        self.contentType = contentType
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
        self.contentType = configuration.contentType
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
