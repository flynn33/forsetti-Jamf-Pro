import Foundation

/// Builds Markdown documents from `ShareableRecord` values and writes them to
/// temporary files for sharing.
///
/// Output: one `## <title>` heading per record followed by a `| Field | Value |` table of
/// that record's `shareFields`. Records are separated by a blank line, in supplied order.
enum RecordMarkdown {

    /// Returns a Markdown document describing `records`.
    static func document(for records: [any ShareableRecord]) -> String {
        var sections: [String] = []
        sections.reserveCapacity(records.count)
        for record in records {
            sections.append(section(for: record))
        }
        return sections.joined(separator: "\n\n")
    }

    /// Writes `document(for:)` to a `.md` file in the temporary directory and returns its URL.
    ///
    /// - Parameters:
    ///   - records: The records to serialize.
    ///   - fileName: Base file name without extension (e.g. "Devices"); sanitized.
    /// - Returns: The URL of the written file.
    /// - Throws: Any error thrown while writing the file.
    static func temporaryFile(for records: [any ShareableRecord], fileName: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(sanitizedFileName(fileName))
            .appendingPathExtension("md")
        try document(for: records).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Helpers

    /// Builds the Markdown section for a single record.
    private static func section(for record: any ShareableRecord) -> String {
        var lines = ["## \(escape(record.shareTitle))"]
        let fields = record.shareFields
        if fields.isEmpty == false {
            lines.append("")
            lines.append("| Field | Value |")
            lines.append("| --- | --- |")
            for field in fields {
                lines.append("| \(escape(field.label)) | \(escape(field.value)) |")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Escapes characters that would break a Markdown table cell.
    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\r\n", with: "<br>")
            .replacingOccurrences(of: "\n", with: "<br>")
            .replacingOccurrences(of: "\r", with: "<br>")
            .trimmingCharacters(in: .whitespaces)
    }

    /// Reduces an arbitrary string to a filesystem-safe base file name.
    ///
    /// Exposed (not `private`) so views can reuse it for a save panel's default filename,
    /// keeping the file name sanitized — a raw Jamf device name can contain `/` or `:`, which a
    /// save panel would otherwise mangle. `nonisolated` as a pure helper usable from any context.
    nonisolated static func sanitizedFileName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ "))
        let cleaned = String(name.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars
            .filter { allowed.contains($0) })
        return cleaned.isEmpty ? "Export" : cleaned
    }
}

//endofline
