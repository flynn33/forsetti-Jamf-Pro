import Foundation

// "End of Line"

/// A Jamf Pro Computer Extension Attribute (EA) descriptor.
///
/// EAs are admin-defined custom fields per tenant. The list is fetched at
/// runtime via `GET /api/v2/computer-extension-attributes` and converted into
/// transient `ComputerField` entries so the user can build Advanced Search
/// criteria against them and add them as result columns. Because Jamf's RSQL
/// syntax for filtering computers by extension attributes varies by version
/// (and the public docs don't pin it down), EA criteria are routed to the
/// in-memory client-side matcher rather than emitted as server-side RSQL — see
/// `JamfRSQLComposer.composeForComputers` and the `isServerFilterable` flag.
///
/// This mirrors `MobileDeviceExtensionAttribute` so both search modules behave
/// identically; the only differences are the `cea_` key prefix (vs `ea_`) and
/// the `ComputerFieldDataType` mapping.
nonisolated struct ComputerExtensionAttribute: Identifiable, Decodable, Hashable, Sendable {

    /// Mirrors Jamf's documented EA `dataType` enum. Drives the
    /// `ComputerFieldDataType` mapping below so the Advanced Search picker shows
    /// the correct input control (text / number / date).
    enum DataType: String, Decodable, Sendable {
        case string = "STRING"
        case integer = "INTEGER"
        case dateTime = "DATE_TIME"
        case unknown

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = DataType(rawValue: raw) ?? .unknown
        }
    }

    /// Mirrors Jamf's `inputType`. Only `popup` matters for the UI right now —
    /// the picker can offer `allowedValues` instead of a free-form text field.
    enum InputType: String, Decodable, Sendable {
        case text = "TEXT"
        case popup = "POPUP"
        case ldap = "LDAP"
        case scriptResult = "SCRIPT_RESULT"
        case directoryService = "DIRECTORY_SERVICE_ATTRIBUTE_MAPPING"
        case unknown

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = InputType(rawValue: raw) ?? .unknown
        }
    }

    let id: String
    let name: String
    let description: String?
    let dataType: DataType
    let inputType: InputType
    let popupChoices: [String]?

    /// Catalog-field key prefix. `ComputerSearchViewModel.extractFieldValues`
    /// uses this to recognize EA values when flattening the inventory response,
    /// and the client-side matcher uses it when looking up the criterion's value
    /// on a record. Distinct from the mobile `ea_` prefix so a tenant can run
    /// both modules without synthetic-key collisions.
    static let keyPrefix = "cea_"

    /// The synthetic catalog key for this EA. Always reproducible from `id`.
    var fieldKey: String {
        Self.keyPrefix + id
    }

    /// Maps Jamf's EA data type to the catalog's runtime type. Falls back to
    /// `.string` for unknown variants so the picker still offers a sane operator
    /// allowlist.
    var swiftDataType: ComputerFieldDataType {
        switch dataType {
        case .string: return inputType == .popup ? .enumeration : .string
        case .integer: return .integer
        case .dateTime: return .date
        case .unknown: return .string
        }
    }

    /// Builds a `ComputerField` matching this EA's metadata. The result is
    /// merged into `ComputerSearchViewModel.allCatalogFields` so it shows up in
    /// the field catalog picker, result rows, the detail view, and the Advanced
    /// Search builder.
    ///
    /// `isFilterable` is `true` (so the picker shows it) but `isServerFilterable`
    /// is `false` so the composer routes EA criteria to the client-side matcher.
    /// `supportsRSQLSearch` is `false` for the same reason. The user pays a
    /// slight perf cost (we fetch computers matching the rest of the query first,
    /// then filter EAs in memory) but avoids version-specific RSQL breakage.
    func makeField() -> ComputerField {
        let descriptionText = (description?.isEmpty == false ? description! : "Custom extension attribute")
        return ComputerField(
            key: fieldKey,
            displayName: name,
            description: "Extension attribute • \(descriptionText)",
            section: .extensionAttributes,
            supportsRSQLSearch: false,
            responsePaths: [fieldKey],
            dataType: swiftDataType,
            isFilterable: true,
            isSortable: false,
            isServerFilterable: false,
            allowedValues: (inputType == .popup ? popupChoices : nil)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case dataType
        case inputType
        case popupChoices = "popupMenuChoices"
        case alternatePopupChoices = "popupChoices"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Jamf returns id as either Int or String depending on endpoint version.
        if let intID = try? container.decode(Int.self, forKey: .id) {
            self.id = String(intID)
        } else {
            self.id = try container.decode(String.self, forKey: .id)
        }
        self.name = try container.decode(String.self, forKey: .name)
        self.description = try? container.decode(String.self, forKey: .description)
        self.dataType = (try? container.decode(DataType.self, forKey: .dataType)) ?? .string
        self.inputType = (try? container.decode(InputType.self, forKey: .inputType)) ?? .text
        self.popupChoices =
            (try? container.decode([String].self, forKey: .popupChoices))
            ?? (try? container.decode([String].self, forKey: .alternatePopupChoices))
    }

    /// Memberwise init for tests and synthetic usage. Decoder path is the
    /// production source of truth.
    init(
        id: String,
        name: String,
        description: String? = nil,
        dataType: DataType = .string,
        inputType: InputType = .text,
        popupChoices: [String]? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.dataType = dataType
        self.inputType = inputType
        self.popupChoices = popupChoices
    }
}

//endofline
