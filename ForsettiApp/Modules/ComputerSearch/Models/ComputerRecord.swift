import Foundation

/// A single computer record decoded from the Jamf Pro inventory API response.
///
/// `ComputerRecord` handles the deeply nested and inconsistent JSON structures returned by
/// various Jamf Pro API versions (v1, v2, v3). The custom `Decodable` implementation walks
/// through nested containers (`general`, `hardware`, `operatingSystem`, `userAndLocation`)
/// and applies multiple fallback strategies to extract each property, making the decoder
/// resilient to missing keys, type mismatches, and structural differences across API versions.
struct ComputerRecord: Identifiable, Decodable, Sendable {
    /// The Jamf Pro computer ID, decoded as either a string or integer.
    let id: String

    /// The display name of the computer (e.g. "Jim's MacBook Pro").
    let computerName: String

    /// The hardware serial number, used as a primary lookup key across prestage enrollments.
    let serialNumber: String

    /// The unique device identifier (UDID) assigned by Apple.
    let udid: String?

    /// The marketing model name (e.g. "MacBook Pro (14-inch, 2023)").
    let model: String?

    /// The internal model identifier (e.g. "Mac14,5").
    let modelIdentifier: String?

    /// The macOS version string (e.g. "14.3.1").
    let osVersion: String?

    /// The OS build number (e.g. "23D60").
    let osBuild: String?

    /// The last IP address the computer reported to Jamf Pro.
    let lastIpAddress: String?

    /// The username of the assigned user from the User and Location section.
    let username: String?

    /// The email address of the assigned user.
    let email: String?

    /// The asset tag assigned to this computer for inventory tracking.
    let assetTag: String?

    /// The numeric department ID from User and Location, decoded as a string for display.
    let departmentID: String?

    /// The numeric building ID from User and Location, decoded as a string for display.
    let buildingID: String?

    /// Processor label reported by Jamf, if present.
    let processorType: String?

    /// Total RAM in megabytes, decoded as a string for display and filtering.
    let totalRamMegabytes: String?

    /// Battery capacity percentage, decoded as a string for display and filtering.
    let batteryCapacityPercent: String?

    /// Apple Silicon status, decoded as a string for display and filtering.
    let appleSilicon: String?

    /// Extension attribute values keyed by stable synthetic and display keys.
    let extensionAttributes: [String: String]

    /// Dynamic inventory values extracted through `ComputerField.responsePaths`.
    let decodedFieldValues: [String: String]

    /// The PreStage enrollment status (e.g. "Enrolled", "Not Enrolled"), normalized from various API representations.
    let prestageEnrollmentStatus: String?

    /// The display name of the PreStage enrollment profile, if assigned.
    let prestageEnrollmentProfileName: String?

    /// The numeric ID of the PreStage enrollment profile, decoded as a string.
    let prestageEnrollmentProfileID: String?

    /// A formatted display string combining the prestage status, profile name, and profile ID.
    ///
    /// Returns `nil` if no prestage information is available for this record.
    var prestageDisplayValue: String? {
        Self.prestageDisplayValue(
            status: prestageEnrollmentStatus,
            profileName: prestageEnrollmentProfileName,
            profileID: prestageEnrollmentProfileID
        )
    }

    /// Top-level coding keys for the Jamf Pro computer inventory JSON structure.
    private enum CodingKeys: String, CodingKey {
        case id
        case udid
        case general
        case hardware
        case operatingSystem
        case userAndLocation
        case computerName
        case serialNumber
        case extensionAttributes
        case prestageEnrollmentStatus
        case prestageEnrollmentProfile
        case prestageEnrollmentProfileName
        case prestageEnrollmentProfileId
        case prestageId
    }

    /// Coding keys for fields nested under the `general` JSON container.
    private enum GeneralKeys: String, CodingKey {
        case name
        case lastIpAddress
        case assetTag
        case managementStatus
        case enrollmentStatus
        case managed
        case prestageEnrollmentProfile
        case prestageEnrollmentProfileName
        case prestageEnrollmentProfileId
        case prestageId
    }

    /// Coding keys for fields nested under the `hardware` JSON container.
    private enum HardwareKeys: String, CodingKey {
        case serialNumber
        case model
        case modelIdentifier
        case processorType
        case totalRamMegabytes
        case batteryCapacityPercent
        case appleSilicon
    }

    /// Coding keys for fields nested under the `operatingSystem` JSON container.
    private enum OperatingSystemKeys: String, CodingKey {
        case version
        case build
    }

    /// Coding keys for fields nested under the `userAndLocation` JSON container.
    private enum UserAndLocationKeys: String, CodingKey {
        case username
        case email
        case departmentId
        case buildingId
    }

    /// Coding keys for the nested prestage enrollment profile object, which may appear
    /// under `general.prestageEnrollmentProfile` with varying key names across API versions.
    private enum PrestageProfileKeys: String, CodingKey {
        case id
        case name
        case profileName
        case displayName
        case prestageEnrollmentProfileName
    }

    /// Creates a `ComputerRecord` directly with all properties.
    ///
    /// This memberwise initializer is used by `withPrestageEnrollment(...)` to create
    /// updated copies and by `makeScopeOnlyRecord(...)` to synthesize records from
    /// prestage scope data that has no matching inventory entry.
    init(
        id: String,
        computerName: String,
        serialNumber: String,
        udid: String? = nil,
        model: String? = nil,
        modelIdentifier: String? = nil,
        osVersion: String? = nil,
        osBuild: String? = nil,
        lastIpAddress: String? = nil,
        username: String? = nil,
        email: String? = nil,
        assetTag: String? = nil,
        departmentID: String? = nil,
        buildingID: String? = nil,
        processorType: String? = nil,
        totalRamMegabytes: String? = nil,
        batteryCapacityPercent: String? = nil,
        appleSilicon: String? = nil,
        extensionAttributes: [String: String] = [:],
        decodedFieldValues: [String: String] = [:],
        prestageEnrollmentStatus: String? = nil,
        prestageEnrollmentProfileName: String? = nil,
        prestageEnrollmentProfileID: String? = nil
    ) {
        self.id = id
        self.computerName = computerName
        self.serialNumber = serialNumber
        self.udid = udid
        self.model = model
        self.modelIdentifier = modelIdentifier
        self.osVersion = osVersion
        self.osBuild = osBuild
        self.lastIpAddress = lastIpAddress
        self.username = username
        self.email = email
        self.assetTag = assetTag
        self.departmentID = departmentID
        self.buildingID = buildingID
        self.processorType = processorType
        self.totalRamMegabytes = totalRamMegabytes
        self.batteryCapacityPercent = batteryCapacityPercent
        self.appleSilicon = appleSilicon
        self.extensionAttributes = extensionAttributes
        self.decodedFieldValues = decodedFieldValues
        self.prestageEnrollmentStatus = prestageEnrollmentStatus
        self.prestageEnrollmentProfileName = prestageEnrollmentProfileName
        self.prestageEnrollmentProfileID = prestageEnrollmentProfileID
    }

    /// Decodes a `ComputerRecord` from Jamf Pro API JSON, handling multiple structural formats.
    ///
    /// The decoder tries nested containers first (v2/v3 format with `general`, `hardware`, etc.)
    /// and falls back to flat top-level keys (v1 format). PreStage enrollment data is extracted
    /// from multiple possible locations in the JSON hierarchy and normalized into consistent values.
    init(from decoder: Decoder) throws {
        let rawPayload = try? ComputerInventoryJSONValue(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Try decoding ID as string first, then integer, falling back to a generated UUID
        id =
            Self.decodeStringOrInt(from: container, key: .id) ??
            UUID().uuidString

        // Extract general fields from the nested container, or fall back to top-level keys
        if let general = try? container.nestedContainer(keyedBy: GeneralKeys.self, forKey: .general) {
            computerName = try general.decodeIfPresent(String.self, forKey: .name) ?? "Unknown Computer"
            lastIpAddress = try general.decodeIfPresent(String.self, forKey: .lastIpAddress)
            assetTag = try general.decodeIfPresent(String.self, forKey: .assetTag)
        } else {
            computerName = try container.decodeIfPresent(String.self, forKey: .computerName) ?? "Unknown Computer"
            lastIpAddress = nil
            assetTag = nil
        }

        var decodedPrestageStatus: String?
        var decodedPrestageName: String?
        var decodedPrestageID: String?

        // Hardware fields: try nested container first, then top-level fallback
        if let hardware = try? container.nestedContainer(keyedBy: HardwareKeys.self, forKey: .hardware) {
            serialNumber = try hardware.decodeIfPresent(String.self, forKey: .serialNumber) ??
                (try container.decodeIfPresent(String.self, forKey: .serialNumber)) ??
                "Unknown"
            model = try hardware.decodeIfPresent(String.self, forKey: .model)
            modelIdentifier = try hardware.decodeIfPresent(String.self, forKey: .modelIdentifier)
            processorType = try hardware.decodeIfPresent(String.self, forKey: .processorType)
            totalRamMegabytes = Self.decodeLossyString(from: hardware, key: .totalRamMegabytes)
            batteryCapacityPercent = Self.decodeLossyString(from: hardware, key: .batteryCapacityPercent)
            appleSilicon = Self.decodeLossyString(from: hardware, key: .appleSilicon)
        } else {
            serialNumber = try container.decodeIfPresent(String.self, forKey: .serialNumber) ?? "Unknown"
            model = nil
            modelIdentifier = nil
            processorType = nil
            totalRamMegabytes = nil
            batteryCapacityPercent = nil
            appleSilicon = nil
        }

        // OS version and build from the operatingSystem nested container
        if let operatingSystem = try? container.nestedContainer(keyedBy: OperatingSystemKeys.self, forKey: .operatingSystem) {
            osVersion = try operatingSystem.decodeIfPresent(String.self, forKey: .version)
            osBuild = try operatingSystem.decodeIfPresent(String.self, forKey: .build)
        } else {
            osVersion = nil
            osBuild = nil
        }

        // User and location: decode username, email, and numeric IDs (which may arrive as int or string)
        if let userAndLocation = try? container.nestedContainer(keyedBy: UserAndLocationKeys.self, forKey: .userAndLocation) {
            username = try userAndLocation.decodeIfPresent(String.self, forKey: .username)
            email = try userAndLocation.decodeIfPresent(String.self, forKey: .email)
            departmentID = Self.decodeStringOrInt(from: userAndLocation, key: .departmentId)
            buildingID = Self.decodeStringOrInt(from: userAndLocation, key: .buildingId)
        } else {
            username = nil
            email = nil
            departmentID = nil
            buildingID = nil
        }

        // PreStage enrollment: gathered from multiple possible locations in the JSON hierarchy
        // because different Jamf Pro API versions nest this data differently
        if let general = try? container.nestedContainer(keyedBy: GeneralKeys.self, forKey: .general) {
            decodedPrestageStatus =
                Self.decodeLossyString(from: general, key: .managementStatus) ??
                Self.decodeLossyString(from: general, key: .enrollmentStatus) ??
                Self.decodeLossyString(from: general, key: .managed)

            decodedPrestageName = Self.decodeLossyString(from: general, key: .prestageEnrollmentProfileName)
            decodedPrestageID =
                Self.decodeStringOrInt(from: general, key: .prestageEnrollmentProfileId) ??
                Self.decodeStringOrInt(from: general, key: .prestageId)

            // Some API versions nest the profile inside an object rather than flat keys
            if let nested = try? general.nestedContainer(keyedBy: PrestageProfileKeys.self, forKey: .prestageEnrollmentProfile) {
                decodedPrestageName =
                    decodedPrestageName ??
                    Self.decodeLossyString(from: nested, key: .name) ??
                    Self.decodeLossyString(from: nested, key: .profileName) ??
                    Self.decodeLossyString(from: nested, key: .displayName) ??
                    Self.decodeLossyString(from: nested, key: .prestageEnrollmentProfileName)

                decodedPrestageID =
                    decodedPrestageID ??
                    Self.decodeStringOrInt(from: nested, key: .id)
            }
        }

        // Final fallback: check top-level keys for prestage data
        decodedPrestageStatus =
            decodedPrestageStatus ??
            Self.decodeLossyString(from: container, key: .prestageEnrollmentStatus)

        decodedPrestageName =
            decodedPrestageName ??
            Self.decodeLossyString(from: container, key: .prestageEnrollmentProfileName)
        decodedPrestageID =
            decodedPrestageID ??
            Self.decodeStringOrInt(from: container, key: .prestageEnrollmentProfileId) ??
            Self.decodeStringOrInt(from: container, key: .prestageId)

        // Last resort: the profile key itself might be a plain string value
        if decodedPrestageName == nil,
           let directValue = Self.decodeLossyString(from: container, key: .prestageEnrollmentProfile)
        {
            decodedPrestageName = directValue
        }

        // Normalize all prestage values to canonical form before storing
        prestageEnrollmentStatus = Self.normalizePrestageStatus(decodedPrestageStatus)
        prestageEnrollmentProfileName = Self.normalizePrestageComponent(decodedPrestageName)
        prestageEnrollmentProfileID = Self.normalizePrestageComponent(decodedPrestageID)

        extensionAttributes = Self.decodeExtensionAttributes(from: container)
        var extractedValues = rawPayload.map(Self.extractCatalogValues(from:)) ?? [:]
        for (key, value) in extensionAttributes {
            extractedValues[key] = value
        }
        decodedFieldValues = extractedValues
        udid = try container.decodeIfPresent(String.self, forKey: .udid)
    }

    var fieldValues: [String: String] {
        var values = decodedFieldValues
        func insert(_ key: String, _ value: String?) {
            guard let value = Self.normalizePrestageComponent(value) else { return }
            values[key] = value
        }

        insert("id", id)
        insert("general.name", computerName)
        insert("computerName", computerName)
        insert("hardware.serialNumber", serialNumber)
        insert("serialNumber", serialNumber)
        insert("udid", udid)
        insert("hardware.model", model)
        insert("hardware.modelIdentifier", modelIdentifier)
        insert("operatingSystem.version", osVersion)
        insert("operatingSystem.build", osBuild)
        insert("general.lastIpAddress", lastIpAddress)
        insert("userAndLocation.username", username)
        insert("userAndLocation.email", email)
        insert("general.assetTag", assetTag)
        insert("userAndLocation.departmentId", departmentID)
        insert("userAndLocation.buildingId", buildingID)
        insert("hardware.processorType", processorType)
        insert("hardware.totalRamMegabytes", totalRamMegabytes)
        insert("hardware.batteryCapacityPercent", batteryCapacityPercent)
        insert("hardware.appleSilicon", appleSilicon)
        insert("prestageEnrollmentStatus", prestageEnrollmentStatus)
        insert("prestageEnrollmentProfile", prestageDisplayValue)
        extensionAttributes.forEach { values[$0.key] = $0.value }
        return values
    }

    func value(for fieldKey: String) -> String? {
        fieldValues[fieldKey]
    }

    var totalRamMegabytesInt: Int? {
        intValue(for: "hardware.totalRamMegabytes")
    }

    var batteryCapacityPercentInt: Int? {
        intValue(for: "hardware.batteryCapacityPercent")
    }

    var storageTotalMegabytes: Int? {
        intValue(for: "hardware.capacityMb")
            ?? intValue(for: "hardware.storageCapacityMegabytes")
            ?? intValue(for: "storage.disks[].partitions[].sizeMegabytes")
            ?? intValue(for: "storage.disks[].sizeMegabytes")
    }

    var storageAvailableMegabytes: Int? {
        intValue(for: "hardware.availableSpaceMb")
            ?? intValue(for: "hardware.bootDriveAvailableSpaceMegabytes")
            ?? intValue(for: "storage.disks[].partitions[].availableMegabytes")
    }

    var usedSpacePercentage: Int? {
        intValue(for: "hardware.usedSpacePercentage")
    }

    var storageUsedFraction: Double? {
        if let usedSpacePercentage {
            return min(1.0, max(0.0, Double(usedSpacePercentage) / 100.0))
        }
        guard let total = storageTotalMegabytes, total > 0,
              let available = storageAvailableMegabytes else {
            return nil
        }
        let used = max(0, total - available)
        return min(1.0, max(0.0, Double(used) / Double(total)))
    }

    func merging(_ other: ComputerRecord) -> ComputerRecord {
        var mergedValues = decodedFieldValues
        for (key, value) in other.decodedFieldValues where value.isEmpty == false {
            mergedValues[key] = value
        }

        var mergedAttributes = extensionAttributes
        for (key, value) in other.extensionAttributes where value.isEmpty == false {
            mergedAttributes[key] = value
        }

        let resolvedID: String = {
            if other.id.isEmpty { return id }
            if UUID(uuidString: other.id) != nil { return id }
            return other.id
        }()

        return ComputerRecord(
            id: resolvedID,
            computerName: other.computerName == "Unknown Computer" ? computerName : other.computerName,
            serialNumber: other.serialNumber == "Unknown" ? serialNumber : other.serialNumber,
            udid: other.udid ?? udid,
            model: other.model ?? model,
            modelIdentifier: other.modelIdentifier ?? modelIdentifier,
            osVersion: other.osVersion ?? osVersion,
            osBuild: other.osBuild ?? osBuild,
            lastIpAddress: other.lastIpAddress ?? lastIpAddress,
            username: other.username ?? username,
            email: other.email ?? email,
            assetTag: other.assetTag ?? assetTag,
            departmentID: other.departmentID ?? departmentID,
            buildingID: other.buildingID ?? buildingID,
            processorType: other.processorType ?? processorType,
            totalRamMegabytes: other.totalRamMegabytes ?? totalRamMegabytes,
            batteryCapacityPercent: other.batteryCapacityPercent ?? batteryCapacityPercent,
            appleSilicon: other.appleSilicon ?? appleSilicon,
            extensionAttributes: mergedAttributes,
            decodedFieldValues: mergedValues,
            prestageEnrollmentStatus: other.prestageEnrollmentStatus ?? prestageEnrollmentStatus,
            prestageEnrollmentProfileName: other.prestageEnrollmentProfileName ?? prestageEnrollmentProfileName,
            prestageEnrollmentProfileID: other.prestageEnrollmentProfileID ?? prestageEnrollmentProfileID
        )
    }

    /// Returns a copy of this record with updated prestage enrollment information.
    ///
    /// Non-nil parameters override the existing values; `nil` parameters preserve the current values.
    /// All incoming values are normalized before being stored.
    ///
    /// - Parameters:
    ///   - status: The new enrollment status string (e.g. "Enrolled"), or `nil` to keep the current value.
    ///   - profileName: The new profile display name, or `nil` to keep the current value.
    ///   - profileID: The new profile ID, or `nil` to keep the current value.
    /// - Returns: A new `ComputerRecord` with the updated prestage fields.
    func withPrestageEnrollment(
        status: String?,
        profileName: String?,
        profileID: String?
    ) -> ComputerRecord {
        ComputerRecord(
            id: id,
            computerName: computerName,
            serialNumber: serialNumber,
            udid: udid,
            model: model,
            modelIdentifier: modelIdentifier,
            osVersion: osVersion,
            osBuild: osBuild,
            lastIpAddress: lastIpAddress,
            username: username,
            email: email,
            assetTag: assetTag,
            departmentID: departmentID,
            buildingID: buildingID,
            processorType: processorType,
            totalRamMegabytes: totalRamMegabytes,
            batteryCapacityPercent: batteryCapacityPercent,
            appleSilicon: appleSilicon,
            extensionAttributes: extensionAttributes,
            decodedFieldValues: decodedFieldValues,
            prestageEnrollmentStatus: Self.normalizePrestageStatus(status) ?? prestageEnrollmentStatus,
            prestageEnrollmentProfileName: Self.normalizePrestageComponent(profileName) ?? prestageEnrollmentProfileName,
            prestageEnrollmentProfileID: Self.normalizePrestageComponent(profileID) ?? prestageEnrollmentProfileID
        )
    }

    /// Assembles a human-readable display string from the prestage status, profile name, and profile ID.
    ///
    /// Combines whichever components are available into a single formatted string:
    /// - Status + name/ID: `"Enrolled - Profile Name (ID: 42)"`
    /// - Status only: `"Enrolled"`
    /// - Name/ID only: `"Profile Name (ID: 42)"`
    ///
    /// - Returns: A formatted string, or `nil` if no prestage information is available.
    static func prestageDisplayValue(
        status: String?,
        profileName: String?,
        profileID: String?
    ) -> String? {
        let normalizedStatus = normalizePrestageStatus(status)
        let normalizedName = normalizePrestageComponent(profileName)
        let normalizedID = normalizePrestageComponent(profileID)
        let profileDisplay: String?

        // Build the profile portion from name and/or ID
        switch (normalizedName, normalizedID) {
        case let (name?, id?):
            profileDisplay = "\(name) (ID: \(id))"
        case let (name?, nil):
            profileDisplay = name
        case let (nil, id?):
            profileDisplay = id
        case (nil, nil):
            profileDisplay = nil
        }

        // Combine status and profile display with a separator
        if let normalizedStatus, let profileDisplay {
            return "\(normalizedStatus) - \(profileDisplay)"
        }

        if let normalizedStatus {
            return normalizedStatus
        }

        return profileDisplay
    }

    private func intValue(for fieldKey: String) -> Int? {
        guard let value = fieldValues[fieldKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
              value.isEmpty == false else {
            return nil
        }
        return Int(value) ?? Double(value).map { Int($0.rounded()) }
    }

    private enum ComputerInventoryJSONValue: Decodable, Sendable {
        case object([String: ComputerInventoryJSONValue])
        case array([ComputerInventoryJSONValue])
        case string(String)
        case number(String)
        case bool(Bool)
        case null

        init(from decoder: Decoder) throws {
            if let container = try? decoder.container(keyedBy: DynamicCodingKey.self) {
                var values: [String: ComputerInventoryJSONValue] = [:]
                for key in container.allKeys {
                    values[key.stringValue] = try container.decode(ComputerInventoryJSONValue.self, forKey: key)
                }
                self = .object(values)
                return
            }

            if var array = try? decoder.unkeyedContainer() {
                var values: [ComputerInventoryJSONValue] = []
                while array.isAtEnd == false {
                    values.append(try array.decode(ComputerInventoryJSONValue.self))
                }
                self = .array(values)
                return
            }

            let single = try decoder.singleValueContainer()
            if single.decodeNil() {
                self = .null
            } else if let value = try? single.decode(Bool.self) {
                self = .bool(value)
            } else if let value = try? single.decode(Int.self) {
                self = .number(String(value))
            } else if let value = try? single.decode(Double.self) {
                self = .number(String(value))
            } else if let value = try? single.decode(String.self) {
                self = .string(value)
            } else {
                self = .null
            }
        }
    }

    private struct DynamicCodingKey: CodingKey {
        let stringValue: String
        let intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
            intValue = nil
        }

        init?(intValue: Int) {
            stringValue = String(intValue)
            self.intValue = intValue
        }
    }

    nonisolated private static func extractCatalogValues(from payload: ComputerInventoryJSONValue) -> [String: String] {
        var values: [String: String] = [:]
        for field in ComputerField.catalog {
            for responsePath in field.responsePaths {
                let extracted = extractValues(atPath: responsePath, from: payload)
                    .compactMap(displayString)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { $0.isEmpty == false }
                if extracted.isEmpty == false {
                    values[field.key] = orderedUnique(extracted).joined(separator: ", ")
                    break
                }
            }
        }
        return values
    }

    nonisolated private static func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var unique: [String] = []
        for value in values where seen.insert(value).inserted {
            unique.append(value)
        }
        return unique
    }

    nonisolated private static func extractValues(
        atPath path: String,
        from payload: ComputerInventoryJSONValue
    ) -> [ComputerInventoryJSONValue] {
        let components = path.split(separator: ".").map(String.init)
        return components.reduce([payload]) { currentValues, component in
            let expectsArray = component.hasSuffix("[]")
            let key = expectsArray ? String(component.dropLast(2)) : component
            var nextValues: [ComputerInventoryJSONValue] = []

            for value in currentValues {
                switch value {
                case .object(let object):
                    guard let child = object[key] else { continue }
                    append(child, expectsArray: expectsArray, to: &nextValues)
                case .array(let array):
                    for element in array {
                        if case .object(let object) = element,
                           let child = object[key] {
                            append(child, expectsArray: expectsArray, to: &nextValues)
                        } else if expectsArray == false {
                            nextValues.append(element)
                        }
                    }
                default:
                    continue
                }
            }

            return nextValues
        }
    }

    nonisolated private static func append(
        _ value: ComputerInventoryJSONValue,
        expectsArray: Bool,
        to values: inout [ComputerInventoryJSONValue]
    ) {
        if expectsArray, case .array(let array) = value {
            values.append(contentsOf: array)
        } else {
            values.append(value)
        }
    }

    nonisolated private static func displayString(from value: ComputerInventoryJSONValue) -> String? {
        switch value {
        case .string(let string):
            return string
        case .number(let number):
            return number
        case .bool(let bool):
            return bool ? "true" : "false"
        case .array(let array):
            let nested = array.compactMap(displayString)
            return nested.isEmpty ? nil : nested.joined(separator: ", ")
        case .object:
            return nil
        case .null:
            return nil
        }
    }

    /// Attempts to decode a value as a `String` first, then as an `Int` (converting to string).
    ///
    /// This handles Jamf Pro API inconsistencies where numeric IDs sometimes arrive as
    /// JSON strings and sometimes as JSON numbers.
    ///
    /// - Returns: The decoded string, or `nil` if neither type matches or the value is blank.
    private static func decodeStringOrInt<K: CodingKey>(
        from container: KeyedDecodingContainer<K>,
        key: K
    ) -> String? {
        if let stringValue = try? container.decode(String.self, forKey: key) {
            let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        if let intValue = try? container.decode(Int.self, forKey: key) {
            return String(intValue)
        }

        return nil
    }

    private struct ExtensionAttributePayload: Decodable {
        let id: String?
        let definitionId: String?
        let name: String?
        let values: [String]

        private enum CodingKeys: String, CodingKey {
            case id
            case definitionId
            case name
            case value
            case values
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = Self.decodeStringOrInt(from: container, key: .id)
            definitionId = Self.decodeStringOrInt(from: container, key: .definitionId)
            name = try? container.decode(String.self, forKey: .name)
            if let rawValues = try? container.decode([String].self, forKey: .values) {
                values = rawValues
            } else if let rawValue = Self.decodeLossyString(from: container, key: .value) {
                values = [rawValue]
            } else {
                values = []
            }
        }

        private static func decodeStringOrInt<K: CodingKey>(
            from container: KeyedDecodingContainer<K>,
            key: K
        ) -> String? {
            if let stringValue = try? container.decode(String.self, forKey: key) {
                let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }

            if let intValue = try? container.decode(Int.self, forKey: key) {
                return String(intValue)
            }

            return nil
        }

        private static func decodeLossyString<K: CodingKey>(
            from container: KeyedDecodingContainer<K>,
            key: K
        ) -> String? {
            if let stringValue = try? container.decode(String.self, forKey: key) {
                let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }

            if let intValue = try? container.decode(Int.self, forKey: key) {
                return String(intValue)
            }

            if let doubleValue = try? container.decode(Double.self, forKey: key) {
                return String(doubleValue)
            }

            if let boolValue = try? container.decode(Bool.self, forKey: key) {
                return boolValue ? "true" : "false"
            }

            return nil
        }
    }

    private static func decodeExtensionAttributes(from container: KeyedDecodingContainer<CodingKeys>) -> [String: String] {
        guard let payloads = try? container.decode([ExtensionAttributePayload].self, forKey: .extensionAttributes) else {
            return [:]
        }

        var values: [String: String] = [:]
        var aggregateValues: [String] = []
        for payload in payloads {
            let displayValue = payload.values
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.isEmpty == false }
                .joined(separator: ", ")
            guard displayValue.isEmpty == false else { continue }
            aggregateValues.append(displayValue)

            if let id = normalizePrestageComponent(payload.definitionId ?? payload.id) {
                values["ea_\(id)"] = displayValue
            }
            if let name = normalizePrestageComponent(payload.name) {
                values["extensionAttributes.\(name)"] = displayValue
            }
        }
        if aggregateValues.isEmpty == false {
            values["extensionAttributes[].values[]"] = aggregateValues.joined(separator: ", ")
        }
        return values
    }

    /// Attempts to decode a value as String, Int, Double, or Bool, coercing everything to a string.
    ///
    /// This is the most permissive decoder, used for prestage fields where the API may return
    /// booleans, numbers, or strings depending on the version and configuration.
    ///
    /// - Returns: The decoded value as a string, or `nil` if no type matches or the value is blank.
    private static func decodeLossyString<K: CodingKey>(
        from container: KeyedDecodingContainer<K>,
        key: K
    ) -> String? {
        if let stringValue = try? container.decode(String.self, forKey: key) {
            let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        if let intValue = try? container.decode(Int.self, forKey: key) {
            return String(intValue)
        }

        if let doubleValue = try? container.decode(Double.self, forKey: key) {
            return String(doubleValue)
        }

        if let boolValue = try? container.decode(Bool.self, forKey: key) {
            return boolValue ? "true" : "false"
        }

        return nil
    }

    /// Trims whitespace from a prestage component string, returning `nil` for blank values.
    private static func normalizePrestageComponent(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Normalizes raw prestage status values into canonical "Enrolled" or "Not Enrolled" labels.
    ///
    /// Handles various representations from the API: boolean strings ("true"/"false"),
    /// management labels ("managed"/"unmanaged"), and enrollment labels ("enrolled"/"not enrolled").
    /// Unrecognized values are returned as-is after trimming.
    private static func normalizePrestageStatus(_ value: String?) -> String? {
        guard let normalized = normalizePrestageComponent(value) else {
            return nil
        }

        switch normalized.lowercased() {
        case "true", "managed", "enrolled":
            return "Enrolled"
        case "false", "unmanaged", "not enrolled":
            return "Not Enrolled"
        default:
            // Partial-match fallback for compound status strings
            if normalized.lowercased().contains("not enrolled") ||
                normalized.lowercased().contains("unmanaged")
            {
                return "Not Enrolled"
            }

            if normalized.lowercased().contains("enrolled") ||
                normalized.lowercased().contains("managed")
            {
                return "Enrolled"
            }

            return normalized
        }
    }
}

/// The top-level response wrapper for computer inventory search API calls.
///
/// Handles multiple response formats by trying `results`, `computers`, and `items`
/// as the array key name, accommodating differences across Jamf Pro API versions.
struct ComputerSearchResponse: Decodable {
    /// The array of decoded computer records from the API response.
    let results: [ComputerRecord]

    /// Coding keys representing the various array key names used across API versions.
    private enum CodingKeys: String, CodingKey {
        case results
        case computers
        case items
    }

    /// Decodes the response by trying each known array key in priority order.
    ///
    /// Falls back to an empty array if none of the expected keys are present,
    /// which can happen with edge-case empty responses.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Try the standard "results" key first (most common in v2/v3)
        if let records = try container.decodeIfPresent([ComputerRecord].self, forKey: .results) {
            results = records
            return
        }

        // Fall back to "computers" (used in some v1 responses)
        if let records = try container.decodeIfPresent([ComputerRecord].self, forKey: .computers) {
            results = records
            return
        }

        // Last resort: "items" (used in some paginated endpoints)
        if let records = try container.decodeIfPresent([ComputerRecord].self, forKey: .items) {
            results = records
            return
        }

        results = []
    }
}

//endofline
