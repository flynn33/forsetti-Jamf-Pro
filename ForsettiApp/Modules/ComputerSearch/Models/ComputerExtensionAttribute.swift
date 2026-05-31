import Foundation

/// Tenant-defined custom field metadata for Jamf Pro computer inventory.
struct ComputerExtensionAttribute: Identifiable, Decodable, Hashable, Sendable {

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

    static let keyPrefix = "ea_"

    var fieldKey: String {
        Self.keyPrefix + id
    }

    var fieldDataType: MobileDeviceFieldDataType {
        switch dataType {
        case .string:
            return inputType == .popup ? .enumeration : .string
        case .integer:
            return .integer
        case .dateTime:
            return .date
        case .unknown:
            return .string
        }
    }

    func makeField() -> ComputerField {
        let descriptionText = description?.isEmpty == false ? description! : "Custom extension attribute"
        return ComputerField(
            key: fieldKey,
            displayName: name,
            description: "Extension attribute - \(descriptionText)",
            section: .extensionAttributes,
            supportsRSQLSearch: false,
            responsePaths: [fieldKey, "extensionAttributes.\(name)"],
            dataType: fieldDataType,
            isFilterable: true,
            isSortable: false,
            isServerFilterable: false,
            allowedValues: inputType == .popup ? popupChoices : nil
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
        if let intID = try? container.decode(Int.self, forKey: .id) {
            id = String(intID)
        } else {
            id = try container.decode(String.self, forKey: .id)
        }
        name = try container.decode(String.self, forKey: .name)
        description = try? container.decode(String.self, forKey: .description)
        dataType = (try? container.decode(DataType.self, forKey: .dataType)) ?? .string
        inputType = (try? container.decode(InputType.self, forKey: .inputType)) ?? .text
        popupChoices =
            (try? container.decode([String].self, forKey: .popupChoices))
            ?? (try? container.decode([String].self, forKey: .alternatePopupChoices))
    }

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
