import Foundation

// MARK: - Hardware derivation service
//
// Jamf inventory payloads can contain useful hardware values under several
// different key names. The derivation service normalizes those summaries into a
// compact model that catalog matching and local enrichment can use.
nonisolated struct DeploymentDerivedHardwareInfo: Codable, Equatable, Sendable {
    var model: String?
    var modelIdentifier: String?
    var modelNumber: String?
    var capacityMb: Int?
    var availableSpaceMb: Int?
    var usedSpacePercentage: Int?
    var batteryLevel: Int?
    var batteryHealth: String?

    var payloadSummary: [String: String] {
        // Keep this summary sparse. Nil values are intentionally omitted so
        // downstream snapshots only record facts the module actually derived.
        var summary: [String: String] = [:]
        summary["model"] = model
        summary["modelIdentifier"] = modelIdentifier
        summary["modelNumber"] = modelNumber
        summary["capacityMb"] = capacityMb.map(String.init)
        summary["availableSpaceMb"] = availableSpaceMb.map(String.init)
        summary["usedSpacePercentage"] = usedSpacePercentage.map(String.init)
        summary["batteryLevel"] = batteryLevel.map(String.init)
        summary["batteryHealth"] = batteryHealth
        return summary
    }

    var isEmpty: Bool {
        payloadSummary.isEmpty
    }
}

/// Deployment Tracker's independent copy of the Mobile Device Search hardware
/// response-path extraction. It keeps the module self-contained while still
/// deriving the model identifier and hardware hints Jamf nests under the
/// `hardware` and `general` sections.
nonisolated struct DeploymentHardwareDerivationService: Sendable {
    private static let modelPaths = [
        "hardware.model",
        "general.model",
        "model",
        "hardware.modelIdentifier",
        "general.modelIdentifier",
        "modelIdentifier"
    ]
    private static let modelIdentifierPaths = [
        "hardware.modelIdentifier",
        "general.modelIdentifier",
        "modelIdentifier"
    ]
    private static let modelNumberPaths = [
        "hardware.modelNumber",
        "general.modelNumber",
        "modelNumber"
    ]
    private static let capacityPaths = ["hardware.capacityMb", "capacityMb"]
    private static let availableSpacePaths = ["hardware.availableSpaceMb", "availableSpaceMb"]
    private static let usedSpacePaths = ["hardware.usedSpacePercentage", "usedSpacePercentage"]
    private static let batteryLevelPaths = ["hardware.batteryLevel", "batteryLevel"]
    private static let batteryHealthPaths = ["hardware.batteryHealth", "batteryHealth"]

    func derive(from payloadSummary: [String: String]) -> DeploymentDerivedHardwareInfo {
        DeploymentDerivedHardwareInfo(
            model: nilIfEmpty(payloadSummary["model"]),
            modelIdentifier: nilIfEmpty(payloadSummary["modelIdentifier"]),
            modelNumber: nilIfEmpty(payloadSummary["modelNumber"]),
            capacityMb: intValue(payloadSummary["capacityMb"]),
            availableSpaceMb: intValue(payloadSummary["availableSpaceMb"]),
            usedSpacePercentage: intValue(payloadSummary["usedSpacePercentage"]),
            batteryLevel: intValue(payloadSummary["batteryLevel"]),
            batteryHealth: nilIfEmpty(payloadSummary["batteryHealth"])
        )
    }

    func derive(from dictionary: [String: Any]) -> DeploymentDerivedHardwareInfo {
        DeploymentDerivedHardwareInfo(
            model: extractValue(using: Self.modelPaths, from: dictionary),
            modelIdentifier: extractValue(using: Self.modelIdentifierPaths, from: dictionary),
            modelNumber: extractValue(using: Self.modelNumberPaths, from: dictionary),
            capacityMb: intValue(extractValue(using: Self.capacityPaths, from: dictionary)),
            availableSpaceMb: intValue(extractValue(using: Self.availableSpacePaths, from: dictionary)),
            usedSpacePercentage: intValue(extractValue(using: Self.usedSpacePaths, from: dictionary)),
            batteryLevel: intValue(extractValue(using: Self.batteryLevelPaths, from: dictionary)),
            batteryHealth: extractValue(using: Self.batteryHealthPaths, from: dictionary)
        )
    }

    func enrich(_ device: DeploymentDevice, with hardwareInfo: DeploymentDerivedHardwareInfo) -> DeploymentDevice {
        var copy = device
        if copy.model == nil {
            copy.model = hardwareInfo.model
        }
        if copy.modelIdentifier == nil {
            copy.modelIdentifier = hardwareInfo.modelIdentifier
        }
        return copy
    }

    private func extractValue(using paths: [String], from dictionary: [String: Any]) -> String? {
        for path in paths {
            guard let resolved = resolveValue(atPath: path, in: dictionary),
                  let stringValue = extractString(from: resolved)
            else {
                continue
            }
            return stringValue
        }
        return nil
    }

    private func resolveValue(atPath path: String, in dictionary: [String: Any]) -> Any? {
        let components = path.split(separator: ".").map(String.init)
        guard components.isEmpty == false else {
            return nil
        }

        var current: Any = dictionary
        for component in components {
            if let currentDictionary = current as? [String: Any] {
                guard let next = currentDictionary[component] else {
                    return nil
                }
                current = next
                continue
            }

            if let currentArray = current as? [Any] {
                let mappedValues = currentArray.compactMap { element -> Any? in
                    (element as? [String: Any])?[component]
                }
                guard mappedValues.isEmpty == false else {
                    return nil
                }
                current = mappedValues.count == 1 ? mappedValues[0] : mappedValues
                continue
            }

            return nil
        }

        return current
    }

    private func extractString(from value: Any?) -> String? {
        switch value {
        case let stringValue as String:
            return nilIfEmpty(stringValue)
        case let boolValue as Bool:
            return boolValue ? "true" : "false"
        case let intValue as Int:
            return String(intValue)
        case let doubleValue as Double:
            return String(doubleValue)
        case let numberValue as NSNumber:
            return numberValue.stringValue
        case let dictionary as [String: Any]:
            return
                extractString(from: dictionary["displayName"]) ??
                extractString(from: dictionary["name"]) ??
                extractString(from: dictionary["value"]) ??
                extractString(from: dictionary["id"])
        case let array as [Any]:
            let flattened = array.compactMap { extractString(from: $0) }
                .filter { $0.isEmpty == false }
            return flattened.isEmpty ? nil : flattened.joined(separator: ", ")
        default:
            return nil
        }
    }

    private func nilIfEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), trimmed.isEmpty == false else {
            return nil
        }
        return trimmed
    }

    private func intValue(_ value: String?) -> Int? {
        guard let value = nilIfEmpty(value) else {
            return nil
        }
        if let integer = Int(value) {
            return integer
        }
        if let double = Double(value) {
            return Int(double.rounded())
        }
        return nil
    }
}
