import Foundation

/// Enumerates the supported types of module packages in the Forsetti.
///
/// Each case corresponds to a distinct functional area of the app. The raw value is a
/// kebab-case identifier used in JSON serialization for package manifest files.
/// Conforms to `Codable`, `CaseIterable`, and `Sendable` for persistence, enumeration, and concurrency safety.
enum ModulePackageType: String, Codable, CaseIterable, Sendable {
    /// A module for searching and browsing computer inventory records.
    case computerSearch = "computer-search"
    /// A module for searching and browsing mobile device inventory records.
    case mobileDeviceSearch = "mobile-device-search"
    /// A unified support workflow module for handling computer and mobile device tickets.
    case supportTechnician = "support-technician"
    /// A module for viewing and managing prestage enrollment assignments.
    case prestageDirector = "prestage-director"
    /// A module for creating visual fleet reports from Jamf Pro inventory.
    case reports = "reports"
    /// A module for tracking Apple deployment workflows, Jamf Inventory Preload, SD+ exports, and ABM verification.
    case deploymentTracker = "deployment-tracker"

    /// The default user-facing title displayed for this module type when no custom name is provided.
    var defaultTitle: String {
        switch self {
        case .computerSearch:
            return "Computer Search"
        case .mobileDeviceSearch:
            return "Mobile Device Search"
        case .supportTechnician:
            return "Support Technician"
        case .prestageDirector:
            return "Prestage Director"
        case .reports:
            return "Reports"
        case .deploymentTracker:
            return "Deployment Tracker Demo"
        }
    }

    /// The default subtitle describing the module's purpose, shown in the UI when no custom subtitle is set.
    var defaultSubtitle: String {
        switch self {
        case .computerSearch:
            return "Search computer inventory and create reusable field-based profiles."
        case .mobileDeviceSearch:
            return "Search inventory and create reusable field-based profiles."
        case .supportTechnician:
            return "Unified support workflow for computer and mobile device tickets."
        case .prestageDirector:
            return "View prestages and move or remove assigned devices."
        case .reports:
            return "Create visual fleet reports from Jamf Pro inventory."
        case .deploymentTracker:
            return "Interactive preview of the upcoming Deployment Tracker Module. Dummy data only. No live Jamf actions."
        }
    }

    /// The default SF Symbol name used as the module's icon when no custom icon is specified.
    var defaultIconSystemName: String {
        switch self {
        case .computerSearch:
            return "desktopcomputer"
        case .mobileDeviceSearch:
            return "iphone.gen3"
        case .supportTechnician:
            return "wrench.and.screwdriver"
        case .prestageDirector:
            return "arrow.left.arrow.right.square"
        case .reports:
            return "chart.pie.fill"
        case .deploymentTracker:
            return "sparkles.rectangle.stack"
        }
    }
}

/// Describes a single installed module package, including its identity, type, version, and display metadata.
///
/// A manifest is the serializable representation of a module package on disk. It holds everything
/// needed to present the module in the UI and to instantiate the correct `JamfModule` subclass.
/// Conforms to `Identifiable` (keyed by `packageID`), `Codable` for JSON round-tripping,
/// `Hashable` for collection operations, and `Sendable` for concurrency safety.
struct ModulePackageManifest: Identifiable, Codable, Hashable, Sendable {
    /// The reverse-DNS-style unique identifier for this package (e.g., "forsetti.feature.computer-search").
    let packageID: String
    /// The functional type of this module, determining which concrete module class is instantiated.
    let moduleType: ModulePackageType
    /// The semantic version string of the package (e.g., "1.0.0").
    let packageVersion: String
    /// An optional custom display name that overrides the module type's default title.
    let moduleDisplayName: String?
    /// An optional custom subtitle that overrides the module type's default subtitle.
    let moduleSubtitle: String?
    /// An optional custom SF Symbol name that overrides the module type's default icon.
    let iconSystemName: String?
    /// The date and time this package was installed or registered.
    let installedAt: Date

    /// Creates a new manifest with all fields specified explicitly.
    ///
    /// - Parameters:
    ///   - packageID: The unique package identifier.
    ///   - moduleType: The module's functional type.
    ///   - packageVersion: The semantic version of the package.
    ///   - moduleDisplayName: Optional custom display name.
    ///   - moduleSubtitle: Optional custom subtitle.
    ///   - iconSystemName: Optional custom SF Symbol icon name.
    ///   - installedAt: The installation timestamp.
    init(
        packageID: String,
        moduleType: ModulePackageType,
        packageVersion: String,
        moduleDisplayName: String?,
        moduleSubtitle: String?,
        iconSystemName: String?,
        installedAt: Date
    ) {
        self.packageID = packageID
        self.moduleType = moduleType
        self.packageVersion = packageVersion
        self.moduleDisplayName = moduleDisplayName
        self.moduleSubtitle = moduleSubtitle
        self.iconSystemName = iconSystemName
        self.installedAt = installedAt
    }

    /// Maps stored properties to their JSON keys for encoding and decoding.
    private enum CodingKeys: String, CodingKey {
        case packageID
        case moduleType
        case packageVersion
        case moduleDisplayName
        case moduleSubtitle
        case iconSystemName
        case installedAt
    }

    /// Decodes a manifest from JSON, defaulting `installedAt` to the current date if absent.
    ///
    /// This gracefully handles older persisted manifests that predate the `installedAt` field.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        packageID = try container.decode(String.self, forKey: .packageID)
        moduleType = try container.decode(ModulePackageType.self, forKey: .moduleType)
        packageVersion = try container.decode(String.self, forKey: .packageVersion)
        moduleDisplayName = try container.decodeIfPresent(String.self, forKey: .moduleDisplayName)
        moduleSubtitle = try container.decodeIfPresent(String.self, forKey: .moduleSubtitle)
        iconSystemName = try container.decodeIfPresent(String.self, forKey: .iconSystemName)
        // Fall back to current date for manifests persisted before this field existed
        installedAt = try container.decodeIfPresent(Date.self, forKey: .installedAt) ?? Date()
    }

    /// Encodes all manifest fields into the keyed JSON container.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(packageID, forKey: .packageID)
        try container.encode(moduleType, forKey: .moduleType)
        try container.encode(packageVersion, forKey: .packageVersion)
        try container.encode(moduleDisplayName, forKey: .moduleDisplayName)
        try container.encode(moduleSubtitle, forKey: .moduleSubtitle)
        try container.encode(iconSystemName, forKey: .iconSystemName)
        try container.encode(installedAt, forKey: .installedAt)
    }

    /// The `Identifiable` conformance key, using `packageID` as the stable identity.
    var id: String { packageID }

    /// Returns the custom display name if set and non-empty, otherwise falls back to the module type's default title.
    var resolvedModuleTitle: String {
        let fallback = moduleType.defaultTitle
        guard let moduleDisplayName else {
            return fallback
        }

        let trimmed = moduleDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    /// Returns the custom subtitle if set and non-empty, otherwise falls back to the module type's default subtitle.
    var resolvedModuleSubtitle: String {
        let fallback = moduleType.defaultSubtitle
        guard let moduleSubtitle else {
            return fallback
        }

        let trimmed = moduleSubtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    /// Returns the custom icon name if set and non-empty, otherwise falls back to the module type's default icon.
    var resolvedIconSystemName: String {
        let fallback = moduleType.defaultIconSystemName
        guard let iconSystemName else {
            return fallback
        }

        let trimmed = iconSystemName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    /// Returns a copy of this manifest with the `installedAt` date replaced by the given value.
    ///
    /// Useful for stamping a fresh installation timestamp onto a bundled default manifest.
    ///
    /// - Parameter date: The new installation date; defaults to now.
    /// - Returns: A new `ModulePackageManifest` with the updated timestamp.
    func withInstalledDate(_ date: Date = Date()) -> ModulePackageManifest {
        ModulePackageManifest(
            packageID: packageID,
            moduleType: moduleType,
            packageVersion: packageVersion,
            moduleDisplayName: moduleDisplayName,
            moduleSubtitle: moduleSubtitle,
            iconSystemName: iconSystemName,
            installedAt: date
        )
    }
}

// MARK: - Bundled Defaults & Package File Parsing

extension ModulePackageManifest {
    /// The set of module packages that ship with the app out of the box.
    ///
    /// These are always available and cannot be removed by the user. If they are missing
    /// from the persisted store, `ModulePackageManager` will re-add them during bootstrap.
    static let bundledDefaults: [ModulePackageManifest] = [
        ModulePackageManifest(
            packageID: "forsetti.feature.computer-search",
            moduleType: .computerSearch,
            packageVersion: "1.0.0",
            moduleDisplayName: nil,
            moduleSubtitle: nil,
            iconSystemName: nil,
            installedAt: Date()
        ),
        ModulePackageManifest(
            packageID: "forsetti.feature.mobile-device-search",
            moduleType: .mobileDeviceSearch,
            packageVersion: "1.0.0",
            moduleDisplayName: nil,
            moduleSubtitle: nil,
            iconSystemName: nil,
            installedAt: Date()
        ),
        ModulePackageManifest(
            packageID: "forsetti.feature.support-technician",
            moduleType: .supportTechnician,
            packageVersion: "1.0.0",
            moduleDisplayName: nil,
            moduleSubtitle: nil,
            iconSystemName: nil,
            installedAt: Date()
        ),
        ModulePackageManifest(
            packageID: "forsetti.feature.prestage-director",
            moduleType: .prestageDirector,
            packageVersion: "1.0.0",
            moduleDisplayName: nil,
            moduleSubtitle: nil,
            iconSystemName: nil,
            installedAt: Date()
        ),
        ModulePackageManifest(
            packageID: "forsetti.feature.reports",
            moduleType: .reports,
            packageVersion: "1.0.0",
            moduleDisplayName: nil,
            moduleSubtitle: nil,
            iconSystemName: nil,
            installedAt: Date()
        ),
        ModulePackageManifest(
            packageID: "forsetti.feature.deployment-tracker",
            moduleType: .deploymentTracker,
            packageVersion: "1.0.0",
            moduleDisplayName: nil,
            moduleSubtitle: nil,
            iconSystemName: nil,
            installedAt: Date()
        )
    ]

    /// A precomputed set of all bundled default package IDs for fast membership checks.
    static var bundledDefaultPackageIDs: Set<String> {
        Set(bundledDefaults.map(\.packageID))
    }

    /// Whether this manifest represents one of the app's bundled default modules.
    var isBundledDefault: Bool {
        Self.bundledDefaultPackageIDs.contains(packageID)
    }

    /// Parses raw JSON data from a `.jamfmodule` package file into a `ModulePackageManifest`.
    ///
    /// Supports multiple key naming conventions (snake_case, camelCase, short forms) to be
    /// tolerant of hand-authored or third-party package files. Required fields are `package_id`
    /// and `module_type`; everything else has sensible defaults.
    ///
    /// - Parameter data: The raw JSON data to parse.
    /// - Returns: A fully populated `ModulePackageManifest`.
    /// - Throws: `JamfFrameworkError.invalidModulePackage` or `.unsupportedModulePackageType`
    ///   if the JSON structure is invalid or contains an unrecognized module type.
    static func fromPackageFileData(_ data: Data) throws -> ModulePackageManifest {
        let rawObject = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = rawObject as? [String: Any] else {
            throw JamfFrameworkError.invalidModulePackage(message: "Module package JSON must be an object.")
        }

        // Look up the package ID from multiple possible key names
        let packageID = try requiredString(
            in: dictionary,
            keys: ["package_id", "packageID", "id"],
            fieldDescription: "package_id"
        )

        let moduleTypeValue = try requiredString(
            in: dictionary,
            keys: ["module_type", "moduleType"],
            fieldDescription: "module_type"
        )

        guard let moduleType = ModulePackageType(rawValue: moduleTypeValue) else {
            throw JamfFrameworkError.unsupportedModulePackageType(type: moduleTypeValue)
        }

        let packageVersion = optionalString(
            in: dictionary,
            keys: ["package_version", "packageVersion", "version"]
        ) ?? "1.0.0"

        let moduleDisplayName = optionalString(
            in: dictionary,
            keys: ["module_display_name", "moduleDisplayName", "displayName", "name"]
        )

        let moduleSubtitle = optionalString(
            in: dictionary,
            keys: ["module_subtitle", "moduleSubtitle", "subtitle", "description"]
        )

        let iconSystemName = optionalString(
            in: dictionary,
            keys: ["icon_system_name", "iconSystemName"]
        )

        return ModulePackageManifest(
            packageID: packageID,
            moduleType: moduleType,
            packageVersion: packageVersion,
            moduleDisplayName: moduleDisplayName,
            moduleSubtitle: moduleSubtitle,
            iconSystemName: iconSystemName,
            installedAt: Date()
        )
    }

    /// Extracts a required string value from a dictionary, trying multiple possible key names.
    ///
    /// - Parameters:
    ///   - dictionary: The source dictionary (parsed from JSON).
    ///   - keys: An ordered list of possible key names to try.
    ///   - fieldDescription: A label for the field, used in error messages.
    /// - Returns: The first non-empty string value found.
    /// - Throws: `JamfFrameworkError.invalidModulePackage` if no valid value is found.
    private static func requiredString(
        in dictionary: [String: Any],
        keys: [String],
        fieldDescription: String
    ) throws -> String {
        if let value = optionalString(in: dictionary, keys: keys) {
            return value
        }

        throw JamfFrameworkError.invalidModulePackage(
            message: "Missing required field '\(fieldDescription)' in module package."
        )
    }

    /// Attempts to extract a string value from a dictionary by trying multiple possible key names.
    ///
    /// Returns the first non-empty, trimmed string found, or `nil` if none of the keys
    /// yield a usable value.
    ///
    /// - Parameters:
    ///   - dictionary: The source dictionary (parsed from JSON).
    ///   - keys: An ordered list of possible key names to try.
    /// - Returns: The first non-empty trimmed string, or `nil`.
    private static func optionalString(
        in dictionary: [String: Any],
        keys: [String]
    ) -> String? {
        for key in keys {
            if let value = dictionary[key] as? String {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty == false {
                    return trimmed
                }
            }
        }

        return nil
    }
}

//endofline
