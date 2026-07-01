import Foundation

// "A robot may not injure a human being or, through inaction, allow a human being to come to harm.
//  A robot must obey the orders given it by human beings except where such orders would conflict with the First Law.
//  A robot must protect its own existence as long as such protection does not conflict with the First or Second Law."

/// A decoded mobile device record representing a single device from Jamf Pro inventory.
///
/// `MobileDeviceRecord` is the canonical model for device search results. It stores
/// core identity fields (id, name, serial, UDID) as first-class properties, plus a
/// flexible `fieldValues` dictionary that holds any additional catalog fields extracted
/// from the API response. The record also carries Pre-Stage Enrollment metadata
/// (status, profile name, profile ID) used for enriched display in result rows.
///
/// Decoding is intentionally lenient: multiple coding keys are tried for each property
/// to accommodate the varying JSON shapes returned by different Jamf Pro versions
/// and endpoints. Unknown or missing fields are silently skipped rather than causing
/// decoding failures.
struct MobileDeviceRecord: Identifiable, Decodable, Sendable {
    /// The unique device identifier from Jamf Pro, or a generated UUID if none was decoded.
    let id: String

    /// The user-facing device name (e.g. "Jane's iPad").
    let deviceName: String

    /// The hardware serial number; falls back to "Unknown" if not present in the response.
    let serialNumber: String

    /// The Apple UDID, if available in the response.
    let udid: String?

    /// The device model string (e.g. "iPad Pro 11-inch"), if available.
    let model: String?

    /// The installed iOS or iPadOS version string, if available.
    let osVersion: String?

    /// The normalized Pre-Stage Enrollment status (e.g. "Enrolled" or "Not Enrolled"), if resolved.
    let prestageEnrollmentStatus: String?

    /// The display name of the assigned Pre-Stage Enrollment profile, if resolved.
    let prestageEnrollmentProfileName: String?

    /// The numeric ID of the assigned Pre-Stage Enrollment profile, if resolved.
    let prestageEnrollmentProfileID: String?

    /// A dictionary of all extracted field values keyed by their `MobileDeviceField.key`.
    /// This includes the core fields above plus any additional catalog fields that were
    /// successfully extracted from the API response.
    let fieldValues: [String: String]

    /// Creates a `MobileDeviceRecord` with explicit values for all properties.
    ///
    /// This memberwise initializer is used both by the JSON decoder path and by the
    /// manual dictionary-parsing path in the view model, ensuring a single construction
    /// contract regardless of how the record is built.
    init(
        id: String,
        deviceName: String,
        serialNumber: String,
        udid: String?,
        model: String?,
        osVersion: String?,
        prestageEnrollmentStatus: String?,
        prestageEnrollmentProfileName: String?,
        prestageEnrollmentProfileID: String?,
        fieldValues: [String: String] = [:]
    ) {
        self.id = id
        self.deviceName = deviceName
        self.serialNumber = serialNumber
        self.udid = udid
        self.model = model
        self.osVersion = osVersion
        self.prestageEnrollmentStatus = prestageEnrollmentStatus
        self.prestageEnrollmentProfileName = prestageEnrollmentProfileName
        self.prestageEnrollmentProfileID = prestageEnrollmentProfileID
        self.fieldValues = fieldValues
    }

    /// Returns a copy of `self` with the other record's non-empty values
    /// merged in. The `other` record wins on fields where it has a value;
    /// `self` wins on fields where `other` is empty/missing. Used by the
    /// detail-view's hardware refresh so a follow-up fetch that returns less
    /// data than the original list response can't accidentally erase
    /// already-known fields like `capacityMb` or `model`.
    ///
    /// Identity (id, deviceName, serialNumber) prefers `other` when it's
    /// genuinely populated and not the "Unknown" / fallback sentinel.
    func merging(_ other: MobileDeviceRecord) -> MobileDeviceRecord {
        var merged = fieldValues
        for (key, value) in other.fieldValues where value.isEmpty == false {
            merged[key] = value
        }

        let resolvedDeviceName: String = {
            if other.deviceName != "Unknown Device", other.deviceName.isEmpty == false {
                return other.deviceName
            }
            return deviceName
        }()

        let resolvedSerial: String = {
            if other.serialNumber != "Unknown", other.serialNumber.isEmpty == false {
                return other.serialNumber
            }
            return serialNumber
        }()

        // Identity preservation. `parseRecord` falls back to UUID().uuidString
        // when the API response carries no top-level `id` (some Jamf Pro
        // versions only put the id under `general` for the single-device
        // detail endpoint). Without this guard, `merging` would replace a
        // valid Jamf id with a synthetic UUID, the search-results array's
        // slot would have an id that no longer matches the route's
        // `recordID`, and `MobileDeviceDetailView`'s `first(where:)` lookup
        // would return nil — i.e. the gauge "appears for a second then
        // disappears" because the view falls into ContentUnavailableView.
        let resolvedID: String = {
            if other.id.isEmpty { return id }
            // Jamf ids are short numeric strings; UUIDs are 36 chars with
            // dashes. Either heuristic catches the fallback case.
            if UUID(uuidString: other.id) != nil { return id }
            return other.id
        }()

        return MobileDeviceRecord(
            id: resolvedID,
            deviceName: resolvedDeviceName,
            serialNumber: resolvedSerial,
            udid: other.udid ?? udid,
            model: other.model ?? model,
            osVersion: other.osVersion ?? osVersion,
            prestageEnrollmentStatus: other.prestageEnrollmentStatus ?? prestageEnrollmentStatus,
            prestageEnrollmentProfileName: other.prestageEnrollmentProfileName ?? prestageEnrollmentProfileName,
            prestageEnrollmentProfileID: other.prestageEnrollmentProfileID ?? prestageEnrollmentProfileID,
            fieldValues: merged
        )
    }

    /// Returns a copy of this record with updated Pre-Stage Enrollment metadata.
    ///
    /// Merges the provided profile name, profile ID, and status with any existing values
    /// on this record (provided values take precedence). The `prestageEnrollmentProfile`
    /// entry in `fieldValues` is also updated to reflect the composed display string.
    ///
    /// - Parameters:
    ///   - profileName: The resolved profile name, or `nil` to keep the existing value.
    ///   - profileID: The resolved profile ID, or `nil` to keep the existing value.
    ///   - status: The resolved enrollment status, or `nil` to keep the existing value.
    /// - Returns: A new `MobileDeviceRecord` with the merged Pre-Stage data.
    func withPrestageEnrollment(
        profileName: String?,
        profileID: String?,
        status: String? = nil
    ) -> MobileDeviceRecord {
        // Prefer newly provided values; fall back to existing record values
        let resolvedName = profileName ?? prestageEnrollmentProfileName
        let resolvedID = profileID ?? prestageEnrollmentProfileID
        let resolvedStatus = status ?? prestageEnrollmentStatus

        var updatedFieldValues = fieldValues
        // Compose a human-readable display value combining status, name, and ID
        if let displayValue = Self.prestageDisplayValue(
            status: resolvedStatus,
            profileName: resolvedName,
            profileID: resolvedID
        ) {
            updatedFieldValues["prestageEnrollmentProfile"] = displayValue
        }

        return MobileDeviceRecord(
            id: id,
            deviceName: deviceName,
            serialNumber: serialNumber,
            udid: udid,
            model: model,
            osVersion: osVersion,
            prestageEnrollmentStatus: resolvedStatus,
            prestageEnrollmentProfileName: resolvedName,
            prestageEnrollmentProfileID: resolvedID,
            fieldValues: updatedFieldValues
        )
    }

    // MARK: - Hardware accessors
    //
    // These typed convenience accessors back the hardware visualization card.
    // Each parses the corresponding string in `fieldValues` (populated when the
    // HARDWARE inventory section is requested) and returns nil when the value
    // is missing or unparseable, so the card can render "—" gracefully.

    /// Total device storage in megabytes, or nil if not present in inventory.
    var capacityMb: Int? { intValue(forFieldKey: "capacityMb") }

    /// Free device storage in megabytes, or nil if not present in inventory.
    var availableSpaceMb: Int? { intValue(forFieldKey: "availableSpaceMb") }

    /// Used-space percentage 0-100, or nil if not present in inventory.
    var usedSpacePercentage: Int? { intValue(forFieldKey: "usedSpacePercentage") }

    /// Battery level percentage 0-100, or nil if not present in inventory.
    var batteryLevel: Int? { intValue(forFieldKey: "batteryLevel") }

    /// Apple model identifier (e.g. `iPad14,5`), or nil if not present.
    var modelIdentifier: String? {
        if let value = value(for: "modelIdentifier"),
           value.isEmpty == false
        {
            return value
        }
        return nil
    }

    /// Apple model number (e.g. `A2848`), or nil if not present. Used as a
    /// secondary chip-identification hint when `modelIdentifier` is not
    /// reported (Jamf returns `null` for some devices).
    var modelNumber: String? {
        if let value = value(for: "modelNumber"),
           value.isEmpty == false
        {
            return value
        }
        return nil
    }

    /// Battery health classification ("Normal", "Service Recommended", etc.).
    /// Useful even when `batteryLevel` is null because Jamf reports health on
    /// iOS 17+ via Apple's declarative status framework. Returned as a
    /// trimmed non-empty string or nil.
    var batteryHealth: String? {
        if let value = value(for: "batteryHealth"),
           value.isEmpty == false
        {
            return value
        }
        return nil
    }

    /// Parses the string value of a field key into Int, returning nil on failure.
    private func intValue(forFieldKey key: String) -> Int? {
        guard let raw = value(for: key) else {
            return nil
        }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return nil
        }

        // Many Jamf numeric fields are encoded as JSON numbers but a few arrive
        // as decimal strings. Strip any trailing fraction so "12345.0" parses.
        let normalized = trimmed.split(separator: ".").first.map(String.init) ?? trimmed
        return Int(normalized)
    }

    /// Looks up the display value for a given field key.
    ///
    /// First checks the `fieldValues` dictionary for a pre-extracted value. If no match
    /// is found there, falls back to the record's first-class stored properties for core
    /// fields. For the special `prestageEnrollmentProfile` key, a composed display string
    /// is built on the fly from the status, name, and ID components.
    ///
    /// - Parameter fieldKey: The `MobileDeviceField.key` to look up.
    /// - Returns: The display string for the field, or `nil` if unavailable.
    func value(for fieldKey: String) -> String? {
        // Check the flexible field values dictionary first
        if let mappedValue = fieldValues[fieldKey],
           mappedValue.isEmpty == false
        {
            return mappedValue
        }

        // Fall back to first-class properties for core fields
        switch fieldKey {
        case "id":
            return id
        case "deviceName":
            return deviceName
        case "serialNumber":
            return serialNumber
        case "udid":
            return udid
        case "model":
            return model
        case "osVersion":
            return osVersion
        case "prestageEnrollmentProfile":
            return Self.prestageDisplayValue(
                status: prestageEnrollmentStatus,
                profileName: prestageEnrollmentProfileName,
                profileID: prestageEnrollmentProfileID
            )
        default:
            return nil
        }
    }

    /// Composes a human-readable Pre-Stage Enrollment display value from its components.
    ///
    /// The output format varies depending on which components are available:
    /// - Status + name + ID: `"Enrolled - My Profile (ID: 42)"`
    /// - Status + name only: `"Enrolled - My Profile"`
    /// - Status only: `"Enrolled"`
    /// - Name + ID only: `"My Profile (ID: 42)"`
    /// - None available: `nil`
    ///
    /// - Parameters:
    ///   - status: The normalized enrollment status string.
    ///   - profileName: The Pre-Stage profile display name.
    ///   - profileID: The Pre-Stage profile numeric ID.
    /// - Returns: A formatted display string, or `nil` if no components are available.
    static func prestageDisplayValue(
        status: String? = nil,
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

        // Combine status prefix with profile display when both are present
        if let normalizedStatus, let profileDisplay {
            return "\(normalizedStatus) - \(profileDisplay)"
        }

        if let normalizedStatus {
            return normalizedStatus
        }

        return profileDisplay
    }

    // MARK: - Coding Keys

    /// Top-level coding keys covering the various JSON shapes returned by Jamf Pro endpoints.
    /// Multiple keys map to the same concept (e.g. `id`, `mobileDeviceId`, `deviceId`) to
    /// handle response variations across API versions.
    private enum CodingKeys: String, CodingKey {
        case id
        case mobileDeviceId
        case deviceId
        case deviceName
        case displayName
        case name
        case serialNumber
        case udid
        case model
        case modelIdentifier
        case osVersion
        case operatingSystemVersion
        case prestageEnrollmentProfile
        case prestageEnrollmentStatus
        case enrollmentStatus
        case prestageEnrollmentProfileName
        case prestageEnrollmentProfileId
        case prestageId
        case general
    }

    /// Coding keys for the nested `general` object present in v2 detail responses.
    private enum GeneralKeys: String, CodingKey {
        case name
        case serialNumber
        case udid
        case model
        case osVersion
        case managementStatus
        case enrollmentStatus
        case managed
    }

    /// Coding keys for the nested Pre-Stage Enrollment profile object.
    private enum PrestageProfileKeys: String, CodingKey {
        case id
        case name
        case profileName
        case displayName
        case prestageEnrollmentProfileName
    }


    /// Decodes a `MobileDeviceRecord` from JSON, tolerating multiple response shapes.
    ///
    /// The decoder first attempts to read fields from a nested `general` container
    /// (the v2 detail response format). If that container is absent, it falls back to
    /// flat top-level keys (the v1 / list response format). Pre-Stage Enrollment data
    /// is extracted from both nested objects and flat keys, with the most specific
    /// source taking precedence. All field values are additionally collected into the
    /// `fieldValues` dictionary for flexible downstream access.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Resolve device ID from whichever key is present; generate a UUID as last resort
        id =
            Self.decodeStringOrInt(from: container, key: .id) ??
            Self.decodeStringOrInt(from: container, key: .mobileDeviceId) ??
            Self.decodeStringOrInt(from: container, key: .deviceId) ??
            UUID().uuidString

        var decodedPrestageStatus: String?

        // Try the nested "general" container first (v2 detail shape)
        if let generalContainer = try? container.nestedContainer(keyedBy: GeneralKeys.self, forKey: .general) {
            deviceName = Self.decodeLossyString(from: generalContainer, key: .name) ?? "Unknown Device"
            serialNumber = Self.decodeLossyString(from: generalContainer, key: .serialNumber) ?? "Unknown"
            udid = Self.decodeLossyString(from: generalContainer, key: .udid)
            model = Self.decodeLossyString(from: generalContainer, key: .model)
            osVersion = Self.decodeLossyString(from: generalContainer, key: .osVersion)

            decodedPrestageStatus =
                Self.decodeLossyString(from: generalContainer, key: .managementStatus) ??
                Self.decodeLossyString(from: generalContainer, key: .enrollmentStatus) ??
                Self.decodeLossyString(from: generalContainer, key: .managed)
        } else {
            // Fall back to flat top-level keys (v1 / list shape)
            deviceName =
                Self.decodeLossyString(from: container, key: .deviceName) ??
                Self.decodeLossyString(from: container, key: .name) ??
                Self.decodeLossyString(from: container, key: .displayName) ??
                "Unknown Device"

            serialNumber = Self.decodeLossyString(from: container, key: .serialNumber) ?? "Unknown"
            udid = Self.decodeLossyString(from: container, key: .udid)

            model =
                Self.decodeLossyString(from: container, key: .model) ??
                Self.decodeLossyString(from: container, key: .modelIdentifier)

            osVersion =
                Self.decodeLossyString(from: container, key: .osVersion) ??
                Self.decodeLossyString(from: container, key: .operatingSystemVersion)
        }

        // Resolve Pre-Stage enrollment status from multiple possible keys
        decodedPrestageStatus =
            decodedPrestageStatus ??
            Self.decodeLossyString(from: container, key: .prestageEnrollmentStatus) ??
            Self.decodeLossyString(from: container, key: .enrollmentStatus)

        // Resolve Pre-Stage profile name and ID from flat keys first
        var decodedPrestageName = Self.decodeLossyString(from: container, key: .prestageEnrollmentProfileName)
        var decodedPrestageID = Self.decodeStringOrInt(from: container, key: .prestageEnrollmentProfileId)
            ?? Self.decodeStringOrInt(from: container, key: .prestageId)

        // Then try the nested prestageEnrollmentProfile object for richer data
        if let nestedPrestage = try? container.nestedContainer(keyedBy: PrestageProfileKeys.self, forKey: .prestageEnrollmentProfile) {
            decodedPrestageName =
                decodedPrestageName ??
                Self.decodeLossyString(from: nestedPrestage, key: .name) ??
                Self.decodeLossyString(from: nestedPrestage, key: .profileName) ??
                Self.decodeLossyString(from: nestedPrestage, key: .displayName) ??
                Self.decodeLossyString(from: nestedPrestage, key: .prestageEnrollmentProfileName)

            decodedPrestageID =
                decodedPrestageID ??
                Self.decodeStringOrInt(from: nestedPrestage, key: .id)
        } else if decodedPrestageName == nil {
            // If no nested object, try decoding the key as a plain string (some responses inline the name)
            decodedPrestageName = Self.decodeLossyString(from: container, key: .prestageEnrollmentProfile)
        }

        prestageEnrollmentStatus = Self.normalizePrestageStatus(decodedPrestageStatus)
        prestageEnrollmentProfileName = decodedPrestageName
        prestageEnrollmentProfileID = decodedPrestageID

        // Populate the fieldValues dictionary with all successfully decoded values
        var decodedFieldValues: [String: String] = [
            "id": id,
            "deviceName": deviceName,
            "serialNumber": serialNumber
        ]

        if let udid, udid.isEmpty == false {
            decodedFieldValues["udid"] = udid
        }

        if let model, model.isEmpty == false {
            decodedFieldValues["model"] = model
        }

        if let osVersion, osVersion.isEmpty == false {
            decodedFieldValues["osVersion"] = osVersion
        }

        if let displayValue = Self.prestageDisplayValue(
            status: prestageEnrollmentStatus,
            profileName: decodedPrestageName,
            profileID: decodedPrestageID
        ) {
            decodedFieldValues["prestageEnrollmentProfile"] = displayValue
        }

        fieldValues = decodedFieldValues
    }

    // MARK: - Normalization Helpers

    /// Trims and nil-coalesces a string component, returning `nil` for empty or whitespace-only values.
    private static func normalizePrestageComponent(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Normalizes a raw Pre-Stage status string into a consistent display label.
    ///
    /// Recognizes common Jamf Pro status representations ("true"/"managed"/"enrolled" and
    /// their negatives) and maps them to "Enrolled" or "Not Enrolled". Unrecognized values
    /// are returned as-is after trimming.
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
            // Substring matching for less common representations
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

    /// Attempts to decode a value as a `String` first, then as an `Int` (converting to String).
    /// Returns `nil` for empty or whitespace-only strings and for missing keys.
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

    /// Attempts to decode a value as `String`, `Int`, `Double`, or `Bool` (in that order),
    /// always returning a trimmed `String`. This handles the loosely-typed JSON values that
    /// Jamf Pro sometimes returns (e.g. booleans for status fields, numbers for IDs).
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

//endofline
