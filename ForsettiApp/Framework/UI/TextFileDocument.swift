import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// Markdown text. Falls back to plain text if the system type is unavailable, so the
    /// export still succeeds (as a `.txt`) on an OS that doesn't declare a `.md` type.
    /// `nonisolated` so it satisfies `FileDocument`'s content-type requirements from any context.
    nonisolated static var dashboardMarkdown: UTType { UTType(filenameExtension: "md") ?? .plainText }
}

/// A minimal UTF-8 text `FileDocument` for exporting generated text (e.g. Markdown) through
/// SwiftUI's native `.fileExporter`. Read support exists for round-trip conformance; the
/// export path uses only the write side.
struct TextFileDocument: FileDocument {

    static var readableContentTypes: [UTType] { [.dashboardMarkdown, .plainText] }
    static var writableContentTypes: [UTType] { [.dashboardMarkdown] }

    /// The text payload to write.
    var text: String

    /// Creates a document wrapping `text`.
    init(text: String) { self.text = text }

    /// Reads a document's text from its file contents.
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let string = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        text = string
    }

    /// Serializes `text` as UTF-8 into a new file wrapper.
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

//endofline
