import Foundation

enum ReportExportFilenameBuilder {
    static func filename(reportName: String, format: ReportExportFormat, date: Date = Date()) -> String {
        let slug = sanitizedSlug(from: reportName)
        let timestamp = timestampFormatter.string(from: date)
        let namePart = slug.isEmpty ? "" : "-\(slug)"
        return "forsetti-report\(namePart)-\(timestamp).\(format.fileExtension)"
    }

    static func sanitizedSlug(from value: String) -> String {
        let folded = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        let scalars = folded.unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(scalars)
            .split(separator: "-")
            .filter { $0.isEmpty == false }
            .joined(separator: "-")
        return collapsed.lowercased()
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        // UTC keeps filenames reproducible regardless of the host time zone.
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
}
