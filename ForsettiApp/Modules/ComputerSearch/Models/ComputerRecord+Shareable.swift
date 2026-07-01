import Foundation

/// Makes `ComputerRecord` exportable through the shared `RecordMarkdown` pipeline.
///
/// The title is the computer name; the fields are every catalog field that currently holds a
/// non-empty value, in catalog (section) order — the "all populated fields" content used by
/// copy/share. `nonisolated` to match `ComputerRecord` and `ComputerField.catalog`.
extension ComputerRecord: ShareableRecord {
    nonisolated var shareTitle: String { computerName }

    nonisolated var shareFields: [ShareField] {
        ComputerField.catalog.compactMap { field in
            guard let value = value(for: field.key), value.isEmpty == false else { return nil }
            return ShareField(label: field.displayName, value: value)
        }
    }
}

//endofline
