import Foundation

// "A robot may not injure a human being or, through inaction, allow a human being to come to harm.
//  A robot must obey the orders given it by human beings except where such orders would conflict with the First Law.
//  A robot must protect its own existence as long as such protection does not conflict with the First or Second Law."

/// A single computer record decoded from the Jamf Pro inventory API response.
///
/// `ComputerRecord` handles the deeply nested and inconsistent JSON structures returned by
/// various Jamf Pro API versions (v1, v2, v3). The custom `Decodable` implementation walks
/// through nested containers (`general`, `hardware`, `operatingSystem`, `userAndLocation`)
/// and applies multiple fallback strategies to extract each property, making the decoder
/// resilient to missing keys, type mismatches, and structural differences across API versions.
nonisolated struct ComputerRecord: Identifiable, Decodable, Sendable {
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

    /// The PreStage enrollment status (e.g. "Enrolled", "Not Enrolled"), normalized from various API representations.
    let prestageEnrollmentStatus: String?

    /// The display name of the PreStage enrollment profile, if assigned.
    let prestageEnrollmentProfileName: String?

    /// The numeric ID of the PreStage enrollment profile, decoded as a string.
    let prestageEnrollmentProfileID: String?

    /// A dictionary of all extracted field values keyed by their `ComputerField.key`.
    /// Populated by the view model's dynamic parsing pass so result rows, the detail
    /// view, and client-side advanced filters can resolve any selected catalog field —
    /// not just the fixed first-class properties above.
    let fieldValues: [String: String]

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
        prestageEnrollmentStatus: String? = nil,
        prestageEnrollmentProfileName: String? = nil,
        prestageEnrollmentProfileID: String? = nil,
        fieldValues: [String: String] = [:]
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
        self.prestageEnrollmentStatus = prestageEnrollmentStatus
        self.prestageEnrollmentProfileName = prestageEnrollmentProfileName
        self.prestageEnrollmentProfileID = prestageEnrollmentProfileID
        self.fieldValues = fieldValues
    }

    /// Decodes a `ComputerRecord` from Jamf Pro API JSON, handling multiple structural formats.
    ///
    /// The decoder tries nested containers first (v2/v3 format with `general`, `hardware`, etc.)
    /// and falls back to flat top-level keys (v1 format). PreStage enrollment data is extracted
    /// from multiple possible locations in the JSON hierarchy and normalized into consistent values.
    init(from decoder: Decoder) throws {
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
        } else {
            serialNumber = try container.decodeIfPresent(String.self, forKey: .serialNumber) ?? "Unknown"
            model = nil
            modelIdentifier = nil
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

        udid = try container.decodeIfPresent(String.self, forKey: .udid)

        // Dynamic field values are populated by the view model's dictionary-parsing
        // enrichment pass (it knows which catalog fields were requested); the pure
        // Decodable path starts empty and relies on `value(for:)`'s first-class fallback.
        fieldValues = [:]
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
            prestageEnrollmentStatus: Self.normalizePrestageStatus(status) ?? prestageEnrollmentStatus,
            prestageEnrollmentProfileName: Self.normalizePrestageComponent(profileName) ?? prestageEnrollmentProfileName,
            prestageEnrollmentProfileID: Self.normalizePrestageComponent(profileID) ?? prestageEnrollmentProfileID,
            fieldValues: fieldValues
        )
    }

    /// Returns a copy of this record with `extracted` merged into `fieldValues`
    /// (incoming non-empty values win). Used by the view model to attach the
    /// dynamically-parsed catalog values after the typed decode.
    func withFieldValues(_ extracted: [String: String]) -> ComputerRecord {
        var merged = fieldValues
        for (key, value) in extracted where value.isEmpty == false {
            merged[key] = value
        }

        return ComputerRecord(
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
            prestageEnrollmentStatus: prestageEnrollmentStatus,
            prestageEnrollmentProfileName: prestageEnrollmentProfileName,
            prestageEnrollmentProfileID: prestageEnrollmentProfileID,
            fieldValues: merged
        )
    }

    /// Returns a copy of `self` with the other record's non-empty values merged in.
    /// `other` wins on fields where it has a value; `self` wins where `other` is
    /// empty/missing. Used by the detail-view hardware refresh so a follow-up fetch
    /// that returns less data than the original search row can't discard already-known
    /// fields. Identity (id, name, serial) prefers `other` only when genuinely
    /// populated and not the synthetic UUID / "Unknown" fallback.
    func merging(_ other: ComputerRecord) -> ComputerRecord {
        var merged = fieldValues
        for (key, value) in other.fieldValues where value.isEmpty == false {
            merged[key] = value
        }

        let resolvedComputerName: String = {
            if other.computerName != "Unknown Computer", other.computerName.isEmpty == false {
                return other.computerName
            }
            return computerName
        }()

        let resolvedSerial: String = {
            if other.serialNumber != "Unknown", other.serialNumber.isEmpty == false {
                return other.serialNumber
            }
            return serialNumber
        }()

        // `parseRecord` falls back to UUID().uuidString when the response carries no
        // top-level id. Without this guard `merging` would swap a valid Jamf id for a
        // synthetic UUID, breaking the detail route's `first(where:)` lookup.
        let resolvedID: String = {
            if other.id.isEmpty { return id }
            if UUID(uuidString: other.id) != nil { return id }
            return other.id
        }()

        return ComputerRecord(
            id: resolvedID,
            computerName: resolvedComputerName,
            serialNumber: resolvedSerial,
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
            prestageEnrollmentStatus: other.prestageEnrollmentStatus ?? prestageEnrollmentStatus,
            prestageEnrollmentProfileName: other.prestageEnrollmentProfileName ?? prestageEnrollmentProfileName,
            prestageEnrollmentProfileID: other.prestageEnrollmentProfileID ?? prestageEnrollmentProfileID,
            fieldValues: merged
        )
    }

    // MARK: - Value Lookup

    /// Looks up the display value for a given field key, checking the dynamic
    /// `fieldValues` dictionary first and falling back to first-class properties
    /// for core fields. The `prestageEnrollmentProfile` key composes its display
    /// string on the fly.
    func value(for fieldKey: String) -> String? {
        if let mappedValue = fieldValues[fieldKey],
           mappedValue.isEmpty == false
        {
            return mappedValue
        }

        switch fieldKey {
        case "id":
            return id
        case "general.name", "computerName":
            return computerName
        case "hardware.serialNumber", "serialNumber":
            return serialNumber
        case "udid":
            return udid
        case "hardware.model", "model":
            return model
        case "hardware.modelIdentifier", "modelIdentifier":
            return modelIdentifier
        case "operatingSystem.version", "osVersion":
            return osVersion
        case "operatingSystem.build", "osBuild":
            return osBuild
        case "general.lastIpAddress", "lastIpAddress":
            return lastIpAddress
        case "userAndLocation.username", "username":
            return username
        case "userAndLocation.email", "email":
            return email
        case "general.assetTag", "assetTag":
            return assetTag
        case "prestageEnrollmentProfile":
            return prestageDisplayValue
        default:
            return nil
        }
    }

    /// Parses the value of a field key into an `Int`, tolerating decimal strings
    /// ("12345.0") and comma-joined array values ("994662, 500000" → first element).
    func intValue(for fieldKey: String) -> Int? {
        guard let raw = value(for: fieldKey) else {
            return nil
        }

        let firstComponent = raw
            .split(separator: ",")
            .first
            .map(String.init) ?? raw
        let trimmed = firstComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return nil
        }

        let normalized = trimmed.split(separator: ".").first.map(String.init) ?? trimmed
        return Int(normalized)
    }

    // MARK: - Hardware accessors
    //
    // Typed convenience accessors backing the hardware visualization card. Each parses
    // the corresponding `fieldValues` string (populated when the HARDWARE / STORAGE
    // sections are requested) and returns nil when missing, so the card renders "—".

    /// Total internal storage capacity in megabytes, or nil if not in inventory.
    var totalStorageMb: Int? { intValue(for: "storage.totalSizeMegabytes") }

    /// Boot-drive free space in megabytes, or nil if not in inventory.
    var bootDriveAvailableMb: Int? { intValue(for: "storage.bootDriveAvailableSpaceMegabytes") }

    /// Boot-volume used percentage 0-100, derived from the partition's reported
    /// `percentUsed` when present, otherwise computed from total and free space.
    var storageUsedPercentage: Int? {
        if let reported = intValue(for: "storage.percentUsed"), (0...100).contains(reported) {
            return reported
        }
        guard let total = totalStorageMb, total > 0, let free = bootDriveAvailableMb else {
            return nil
        }
        let used = max(0, total - free)
        return Int((Double(used) / Double(total) * 100).rounded())
    }

    /// Installed RAM in megabytes, or nil if not present.
    var totalRamMb: Int? { intValue(for: "hardware.totalRamMegabytes") }

    /// CPU core count, or nil if not present.
    var coreCount: Int? { intValue(for: "hardware.coreCount") }

    /// Battery capacity percentage 0-100 for portable Macs, or nil for desktops /
    /// when not reported.
    var batteryCapacityPercent: Int? { intValue(for: "hardware.batteryCapacityPercent") }

    /// Reported processor type string (e.g. "Apple M2 Pro"), or nil.
    var processorType: String? {
        guard let value = value(for: "hardware.processorType"), value.isEmpty == false else {
            return nil
        }
        return value
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

// "Klatu-barada-Nikto"

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
