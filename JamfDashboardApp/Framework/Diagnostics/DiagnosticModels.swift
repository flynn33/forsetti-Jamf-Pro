import Foundation

// "Klatu-barada-Nikto"

/// Represents the severity level of a diagnostic event.
///
/// Used to classify diagnostic events by urgency so that consumers (UI, logs, exports)
/// can filter or highlight events appropriately. Conforms to `Codable` for persistence,
/// `CaseIterable` for enumeration in UI pickers, and `Sendable` for safe cross-actor use.
enum DiagnosticSeverity: String, Codable, CaseIterable, Sendable {
    /// Informational message indicating normal operation or noteworthy state.
    case info
    /// A potential issue that does not prevent operation but may require attention.
    case warning
    /// A failure or critical problem that requires investigation or corrective action.
    case error
}

/// A single diagnostic event captured by the diagnostics subsystem.
///
/// Each event records what happened (`message`), where it originated (`source`, `category`),
/// how severe it is (`severity`), and when it occurred (`timestamp`). An optional `metadata`
/// dictionary carries arbitrary key-value context for debugging. The struct is `Identifiable`
/// for use in SwiftUI lists, `Codable` for JSON serialization, `Hashable` for set membership,
/// and `Sendable` for safe passage across concurrency boundaries.
struct DiagnosticEvent: Identifiable, Codable, Hashable, Sendable {
    /// Unique identifier for this event, generated automatically on creation.
    let id: UUID
    /// The moment the event was recorded.
    let timestamp: Date
    /// The subsystem or component that produced the event (e.g., "framework.api-gateway").
    let source: String
    /// A logical grouping within the source (e.g., "authentication", "modules").
    let category: String
    /// The urgency level of this event.
    let severity: DiagnosticSeverity
    /// A human-readable description of what happened.
    let message: String
    /// Arbitrary key-value pairs providing additional context for the event.
    let metadata: [String: String]

    /// Maps each stored property to its JSON key for encoding and decoding.
    private enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case source
        case category
        case severity
        case message
        case metadata
    }

    /// Creates a new diagnostic event with sensible defaults for `id`, `timestamp`, and `metadata`.
    ///
    /// - Parameters:
    ///   - id: A unique identifier; defaults to a new UUID.
    ///   - timestamp: When the event occurred; defaults to now.
    ///   - source: The originating subsystem name.
    ///   - category: A logical grouping tag within the source.
    ///   - severity: How urgent or critical the event is.
    ///   - message: A human-readable description of the event.
    ///   - metadata: Optional dictionary of extra context; defaults to empty.
    nonisolated init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        source: String,
        category: String,
        severity: DiagnosticSeverity,
        message: String,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.category = category
        self.severity = severity
        self.message = message
        self.metadata = metadata
    }

    /// Decodes a `DiagnosticEvent` from a keyed container, restoring all stored properties
    /// from their corresponding JSON keys.
    nonisolated init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        source = try container.decode(String.self, forKey: .source)
        category = try container.decode(String.self, forKey: .category)
        severity = try container.decode(DiagnosticSeverity.self, forKey: .severity)
        message = try container.decode(String.self, forKey: .message)
        metadata = try container.decode([String: String].self, forKey: .metadata)
    }

    /// Encodes all stored properties into a keyed container for JSON serialization.
    nonisolated func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encode(source, forKey: .source)
        try container.encode(category, forKey: .category)
        try container.encode(severity, forKey: .severity)
        try container.encode(message, forKey: .message)
        try container.encode(metadata, forKey: .metadata)
    }
}

// "End of Line"

//endofline
