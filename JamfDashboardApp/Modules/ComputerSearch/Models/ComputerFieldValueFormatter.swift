import Foundation

// "End of Line"

/// Pure, presentation-only formatter that turns a raw Jamf inventory string into
/// a human-readable display string for the Computer detail view.
///
/// Booleans are intentionally NOT handled here: `CategoryFieldRow` renders binary
/// values as a colored `FieldBinaryIndicator`, so adding a boolean branch would
/// double-handle them. Numbers are passed through verbatim (no digit grouping) so
/// the formatter can never mangle an identifier, port, build number, or serial.
nonisolated enum ComputerFieldValueFormatter {
    /// Transforms, in order: trim; ISO-8601 timestamp → localized date+time;
    /// `UPPER_SNAKE` / `SHOUTING CASE` → Title Case; otherwise pass through.
    static func displayString(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return "" }

        // Cheap guard before allocating a date parser: a bare serial, version, or
        // IP never contains both a "T" separator and a ":" time delimiter.
        if trimmed.contains("T"), trimmed.contains(":"),
           let localized = localizedTimestamp(trimmed) {
            return localized
        }

        if trimmed.contains("_") || isShoutingCase(trimmed) {
            return titleCased(trimmed)
        }

        return trimmed
    }

    /// Parses an ISO-8601 timestamp and renders it as a localized medium date with
    /// a short time. Returns nil for anything that isn't a real timestamp so the
    /// caller can fall through to the verbatim value.
    private static func localizedTimestamp(_ value: String) -> String? {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime]
        if let date = parser.date(from: value) {
            return medium(date)
        }
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = parser.date(from: value) {
            return medium(date)
        }
        return nil
    }

    private static func medium(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    /// True only for strings made entirely of uppercase letters and spaces, with at
    /// least one letter (e.g. "ENABLED", "NOT ENABLED"). Any digit or punctuation
    /// disqualifies the value, which keeps serials, versions, and IPs verbatim.
    private static func isShoutingCase(_ value: String) -> Bool {
        var sawLetter = false
        for character in value {
            if character.isLetter {
                sawLetter = true
                if character.isUppercase == false { return false }
            } else if character != " " {
                return false
            }
        }
        return sawLetter
    }

    /// "FULL_SECURITY" → "Full Security"; "NOT ENABLED" → "Not Enabled".
    private static func titleCased(_ value: String) -> String {
        value
            .split(whereSeparator: { $0 == "_" || $0 == " " })
            .map { word in
                let lowered = word.lowercased()
                return lowered.prefix(1).uppercased() + lowered.dropFirst()
            }
            .joined(separator: " ")
    }
}

//endofline
