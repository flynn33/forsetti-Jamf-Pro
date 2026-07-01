import Foundation

/// Makes `MobileDeviceRecord` exportable through the shared `RecordMarkdown` pipeline.
///
/// The title is the device name; the fields are every catalog field that currently holds a
/// non-empty value, in catalog (section) order — the "all populated fields" content used by
/// copy/share.
extension MobileDeviceRecord: ShareableRecord {
    var shareTitle: String { deviceName }

    var shareFields: [ShareField] {
        MobileDeviceField.catalog.compactMap { field in
            guard let value = value(for: field.key), value.isEmpty == false else { return nil }
            return ShareField(label: field.displayName, value: value)
        }
    }
}

//endofline
