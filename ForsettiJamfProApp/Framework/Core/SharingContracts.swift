import Foundation

/// One labeled value contributed by a record when it is copied or exported.
struct ShareField: Hashable, Sendable {
    /// The human-readable field label (e.g. "Serial Number").
    let label: String
    /// The field's display value.
    let value: String
}

/// A record that can be exported to Markdown and shared via the system share sheet.
///
/// Modules conform their domain record type (e.g. `MobileDeviceRecord`) to this protocol
/// so the shared `RecordMarkdown` exporter and the framework copy/share UI can operate
/// on any module's records without duplicating logic.
///
/// The contract is main-actor-isolated (the app's default isolation), matching its UI and
/// view-model callers; conformers typically read main-actor model state to build their fields.
protocol ShareableRecord {
    /// Heading text for the record, rendered as a Markdown `## <title>`.
    var shareTitle: String { get }
    /// The record's already-populated fields, in display order. Conformers omit empties.
    var shareFields: [ShareField] { get }
}

//endofline
