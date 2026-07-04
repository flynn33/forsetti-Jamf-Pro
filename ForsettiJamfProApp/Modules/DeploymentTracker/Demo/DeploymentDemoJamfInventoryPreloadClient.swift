import Foundation

nonisolated struct DeploymentDemoJamfInventoryPreloadClient: JamfInventoryPreloadAPIClient {
    private let records: [JamfInventoryPreloadRecord]

    init(records: [JamfInventoryPreloadRecord] = DeploymentTrackerDemoDataFactory.makePreloadRecords()) {
        self.records = records
    }

    func submitMultipart(path: String, parts: [JamfMultipartFormPart]) async throws -> Data {
        let response = [
            "externalDataChanged": "false",
            "liveAction": "false",
            "mode": "demo",
            "status": "simulated",
            "message": "Deployment Tracker Demo simulated an Inventory Preload submission. No live Jamf actions were run.",
            "partCount": "\(parts.count)"
        ]
        let body = response
            .sorted { $0.key < $1.key }
            .map { "\"\($0.key)\":\"\($0.value)\"" }
            .joined(separator: ",")
        return Data("{\(body)}".utf8)
    }

    func fetchPreloadRecords(filter: String) async throws -> [JamfInventoryPreloadRecord] {
        let requestedSerials = Self.serials(from: filter)
        guard requestedSerials.isEmpty == false else {
            return records
        }
        return records.filter { requestedSerials.contains(Self.normalizedSerial($0.serialNumber)) }
    }

    private static func serials(from filter: String) -> Set<String> {
        let quotedValues = filter
            .split(separator: "'")
            .enumerated()
            .compactMap { index, value -> String? in
                index.isMultiple(of: 2) ? nil : String(value)
            }
        return Set(quotedValues.map(normalizedSerial))
    }

    private static func normalizedSerial(_ serial: String) -> String {
        serial.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}
