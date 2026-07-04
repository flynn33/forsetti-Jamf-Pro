import Combine
import Foundation

#if canImport(OSLog)
import OSLog
#endif

#if canImport(Security)
import Security
#endif

enum ForsettiAppVersion {
    static let current = "A1.0.0"
    static let moduleSemVer = SemVer(major: 1, minor: 0, patch: 0, prerelease: "A1")
}

enum Platform: String, Codable, CaseIterable, Sendable {
    case iOS
    case macOS

    static var current: Platform {
#if os(iOS)
        .iOS
#elseif os(macOS)
        .macOS
#else
        .macOS
#endif
    }
}

enum Capability: String, Codable, CaseIterable, Hashable, Sendable {
    case networking
    case storage
    case secureStorage = "secure_storage"
    case fileExport = "file_export"
    case cryptoUtilities = "crypto_utilities"
    case telemetry
    case routingOverlay = "routing_overlay"
    case uiThemeMask = "ui_theme_mask"
    case toolbarItems = "toolbar_items"
    case viewInjection = "view_injection"
    case sharedDatabase = "shared_database"
    case authentication
    case diagnostics
    case api
    case security
}

enum ModuleType: String, Codable, Sendable {
    case service
    case ui
    case app
}

struct SemVer: Codable, Hashable, Comparable, Sendable {
    let major: Int
    let minor: Int
    let patch: Int
    let prerelease: String?

    init(major: Int, minor: Int, patch: Int, prerelease: String? = nil) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease?.isEmpty == true ? nil : prerelease
    }

    var description: String {
        if let prerelease {
            return "\(major).\(minor).\(patch)-\(prerelease)"
        }
        return "\(major).\(minor).\(patch)"
    }

    static func < (lhs: SemVer, rhs: SemVer) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        if lhs.patch != rhs.patch { return lhs.patch < rhs.patch }

        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil), (nil, _):
            return false
        case (_, nil):
            return true
        case let (left?, right?):
            return left.localizedStandardCompare(right) == .orderedAscending
        }
    }
}

struct ModuleDescriptor: Codable, Hashable, Sendable {
    let moduleID: String
    let displayName: String
    let moduleVersion: SemVer
    let moduleType: ModuleType
}

// swiftlint:disable identifier_name
enum ManifestTemplateVersion: String, Codable, CaseIterable, Sendable {
    case v1_0 = "1.0"
    case v1_1 = "1.1"

    static let current = ManifestTemplateVersion.v1_1
}
// swiftlint:enable identifier_name

enum DefaultModuleRole: String, Codable, CaseIterable, Hashable, Sendable {
    case ui
    case sharedDatabase = "shared_database"
    case authentication
    case diagnostics
    case api
    case security

    func isValid(for moduleType: ModuleType) -> Bool {
        switch self {
        case .ui:
            return moduleType == .ui || moduleType == .app
        case .sharedDatabase, .authentication, .diagnostics, .api, .security:
            return moduleType == .service
        }
    }
}

enum ModuleIOKind: String, Codable, CaseIterable, Hashable, Sendable {
    case networking
    case storage
    case secureStorage = "secure_storage"
    case fileExport = "file_export"
    case telemetry
    case sharedDatabase = "shared_database"
    case authentication
    case diagnostics
    case api
    case security

    var requiredCapability: Capability {
        switch self {
        case .networking: return .networking
        case .storage: return .storage
        case .secureStorage: return .secureStorage
        case .fileExport: return .fileExport
        case .telemetry: return .telemetry
        case .sharedDatabase: return .sharedDatabase
        case .authentication: return .authentication
        case .diagnostics: return .diagnostics
        case .api: return .api
        case .security: return .security
        }
    }
}

enum ModuleIOAccess: String, Codable, CaseIterable, Sendable {
    case read
    case write
    case readWrite = "read_write"
    case execute
    case emit
    case consume
}

enum ModuleDataIsolationMode: String, Codable, CaseIterable, Sendable {
    case privateToModule = "private_to_module"
    case frameworkMediatedShared = "framework_mediated_shared"
}

struct ModuleIORequirement: Codable, Hashable, Sendable {
    let requirementID: String
    let kind: ModuleIOKind
    let access: ModuleIOAccess
    let required: Bool
    let description: String?

    init(
        requirementID: String,
        kind: ModuleIOKind,
        access: ModuleIOAccess,
        required: Bool,
        description: String? = nil
    ) {
        self.requirementID = requirementID
        self.kind = kind
        self.access = access
        self.required = required
        self.description = description
    }
}

struct ModuleUIRequirements: Codable, Hashable, Sendable {
    let controlSchemeID: String?
    let layoutID: String?
    let themeIDs: [String]
    let viewIDs: [String]
    let slotIDs: [String]
    let toolbarItemIDs: [String]
    let routeIDs: [String]
    let pointerIDs: [String]

    init(
        controlSchemeID: String? = nil,
        layoutID: String? = nil,
        themeIDs: [String] = [],
        viewIDs: [String] = [],
        slotIDs: [String] = [],
        toolbarItemIDs: [String] = [],
        routeIDs: [String] = [],
        pointerIDs: [String] = []
    ) {
        self.controlSchemeID = controlSchemeID
        self.layoutID = layoutID
        self.themeIDs = themeIDs
        self.viewIDs = viewIDs
        self.slotIDs = slotIDs
        self.toolbarItemIDs = toolbarItemIDs
        self.routeIDs = routeIDs
        self.pointerIDs = pointerIDs
    }
}

struct ModuleDataIsolation: Codable, Hashable, Sendable {
    let mode: ModuleDataIsolationMode
    let ownedStoreIDs: [String]
    let requiredDefaultRoles: [DefaultModuleRole]

    init(
        mode: ModuleDataIsolationMode,
        ownedStoreIDs: [String] = [],
        requiredDefaultRoles: [DefaultModuleRole] = []
    ) {
        self.mode = mode
        self.ownedStoreIDs = ownedStoreIDs
        self.requiredDefaultRoles = requiredDefaultRoles
    }

    static let privateToModule = ModuleDataIsolation(mode: .privateToModule)
}

struct ModuleRuntimeRequirements: Codable, Hashable, Sendable {
    let io: [ModuleIORequirement]
    let ui: ModuleUIRequirements?
    let dataIsolation: ModuleDataIsolation

    init(
        io: [ModuleIORequirement] = [],
        ui: ModuleUIRequirements? = nil,
        dataIsolation: ModuleDataIsolation = .privateToModule
    ) {
        self.io = io
        self.ui = ui
        self.dataIsolation = dataIsolation
    }
}

struct ModuleManifest: Codable, Hashable, Sendable {
    static let currentSchemaVersion = "1.1"

    let schemaVersion: String
    let manifestTemplateVersion: ManifestTemplateVersion
    let moduleID: String
    let displayName: String
    let moduleVersion: SemVer
    let moduleType: ModuleType
    let supportedPlatforms: [Platform]
    let minForsettiVersion: SemVer
    let maxForsettiVersion: SemVer?
    let capabilitiesRequested: [Capability]
    let iapProductID: String?
    let entryPoint: String
    let defaultModuleRole: DefaultModuleRole?
    let runtimeRequirements: ModuleRuntimeRequirements
    let appVersion: String

    init(
        schemaVersion: String,
        manifestTemplateVersion: ManifestTemplateVersion? = nil,
        moduleID: String,
        displayName: String,
        moduleVersion: SemVer,
        moduleType: ModuleType,
        supportedPlatforms: [Platform],
        minForsettiVersion: SemVer,
        maxForsettiVersion: SemVer? = nil,
        capabilitiesRequested: [Capability],
        iapProductID: String? = nil,
        entryPoint: String,
        defaultModuleRole: DefaultModuleRole? = nil,
        runtimeRequirements: ModuleRuntimeRequirements = ModuleRuntimeRequirements(),
        appVersion: String = ForsettiAppVersion.current
    ) {
        self.schemaVersion = schemaVersion
        self.manifestTemplateVersion = manifestTemplateVersion ?? .current
        self.moduleID = moduleID
        self.displayName = displayName
        self.moduleVersion = moduleVersion
        self.moduleType = moduleType
        self.supportedPlatforms = supportedPlatforms
        self.minForsettiVersion = minForsettiVersion
        self.maxForsettiVersion = maxForsettiVersion
        self.capabilitiesRequested = capabilitiesRequested
        self.iapProductID = iapProductID
        self.entryPoint = entryPoint
        self.defaultModuleRole = defaultModuleRole
        self.runtimeRequirements = runtimeRequirements
        self.appVersion = appVersion
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case manifestTemplateVersion
        case moduleID
        case displayName
        case moduleVersion
        case moduleType
        case supportedPlatforms
        case minForsettiVersion
        case maxForsettiVersion
        case capabilitiesRequested
        case iapProductID
        case entryPoint
        case defaultModuleRole
        case runtimeRequirements
        case appVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(String.self, forKey: .schemaVersion)
        manifestTemplateVersion = try container.decodeIfPresent(
            ManifestTemplateVersion.self,
            forKey: .manifestTemplateVersion
        ) ?? .current
        moduleID = try container.decode(String.self, forKey: .moduleID)
        displayName = try container.decode(String.self, forKey: .displayName)
        moduleVersion = try container.decode(SemVer.self, forKey: .moduleVersion)
        moduleType = try container.decode(ModuleType.self, forKey: .moduleType)
        supportedPlatforms = try container.decode([Platform].self, forKey: .supportedPlatforms)
        minForsettiVersion = try container.decode(SemVer.self, forKey: .minForsettiVersion)
        maxForsettiVersion = try container.decodeIfPresent(SemVer.self, forKey: .maxForsettiVersion)
        capabilitiesRequested = try container.decode([Capability].self, forKey: .capabilitiesRequested)
        iapProductID = try container.decodeIfPresent(String.self, forKey: .iapProductID)
        entryPoint = try container.decode(String.self, forKey: .entryPoint)
        defaultModuleRole = try container.decodeIfPresent(DefaultModuleRole.self, forKey: .defaultModuleRole)
        runtimeRequirements = try container.decodeIfPresent(
            ModuleRuntimeRequirements.self,
            forKey: .runtimeRequirements
        ) ?? ModuleRuntimeRequirements()
        appVersion = try container.decodeIfPresent(String.self, forKey: .appVersion) ?? ForsettiAppVersion.current
    }
}

struct UIContributions: Codable, Hashable, Sendable {
    let themeMask: ThemeMask?
    let toolbarItems: [ToolbarItemDescriptor]
    let viewInjections: [ViewInjectionDescriptor]
    let overlaySchema: OverlaySchema?

    init(
        themeMask: ThemeMask? = nil,
        toolbarItems: [ToolbarItemDescriptor] = [],
        viewInjections: [ViewInjectionDescriptor] = [],
        overlaySchema: OverlaySchema? = nil
    ) {
        self.themeMask = themeMask
        self.toolbarItems = toolbarItems
        self.viewInjections = viewInjections
        self.overlaySchema = overlaySchema
    }
}

struct ThemeMask: Codable, Hashable, Sendable {
    let themeID: String
    let tokens: [ThemeToken]
}

struct ThemeToken: Codable, Hashable, Sendable {
    let key: String
    let value: String
}

struct ToolbarItemDescriptor: Codable, Hashable, Sendable {
    let itemID: String
    let title: String
    let systemImageName: String?
    let action: ToolbarAction
}

enum ToolbarAction: Codable, Hashable, Sendable {
    case navigate(pointerID: String)
    case openOverlay(routeID: String)
    case publishEvent(type: String, payload: [String: String]?)
}

struct ViewInjectionDescriptor: Codable, Hashable, Sendable {
    let injectionID: String
    let slot: String
    let viewID: String
    let priority: Int
}

struct OverlaySchema: Codable, Hashable, Sendable {
    let schemaID: String
    let pointers: [NavigationPointer]
    let routes: [OverlayRoute]
}

struct NavigationPointer: Codable, Hashable, Sendable {
    let pointerID: String
    let label: String
    let target: BaseDestinationRef
    let presentation: OverlayPresentation
}

enum OverlayPresentation: String, Codable, Hashable, Sendable {
    case sheet
    case popover
    case inline
    case push
}

struct BaseDestinationRef: Codable, Hashable, Sendable {
    let destinationID: String
    let parameters: [String: String]?

    init(destinationID: String, parameters: [String: String]? = nil) {
        self.destinationID = destinationID
        self.parameters = parameters
    }
}

struct OverlayRoute: Codable, Hashable, Sendable {
    let routeID: String
    let path: String
    let destination: OverlayDestination
}

enum OverlayDestination: Codable, Hashable, Sendable {
    case base(destinationID: String, parameters: [String: String]?)
    case moduleOverlay(viewID: String, slot: String)
}

protocol ForsettiModule: AnyObject {
    var descriptor: ModuleDescriptor { get }
    var manifest: ModuleManifest { get }

    func start(context: any ForsettiModuleContext) throws
    func stop(context: any ForsettiModuleContext)
}

protocol ForsettiUIModule: ForsettiModule {
    var uiContributions: UIContributions { get }
}

protocol ForsettiAppModule: ForsettiUIModule {}

typealias ModuleFactory = @Sendable () -> any ForsettiModule

enum ModuleRegistryError: Error, LocalizedError {
    case duplicateEntryPoint(String)
    case entryPointNotRegistered(String)

    var errorDescription: String? {
        switch self {
        case let .duplicateEntryPoint(entryPoint):
            return "Module factory already registered for entryPoint '\(entryPoint)'."
        case let .entryPointNotRegistered(entryPoint):
            return "No module factory registered for entryPoint '\(entryPoint)'."
        }
    }
}

final class ModuleRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var factories: [String: ModuleFactory] = [:]

    var registeredEntryPoints: [String] {
        lock.lock()
        defer { lock.unlock() }
        return factories.keys.sorted()
    }

    func register(
        entryPoint: String,
        replacingExisting: Bool = false,
        factory: @escaping ModuleFactory
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        if factories[entryPoint] != nil, !replacingExisting {
            throw ModuleRegistryError.duplicateEntryPoint(entryPoint)
        }

        factories[entryPoint] = factory
    }

    func makeModule(entryPoint: String) throws -> any ForsettiModule {
        lock.lock()
        let factory = factories[entryPoint]
        lock.unlock()

        guard let factory else {
            throw ModuleRegistryError.entryPointNotRegistered(entryPoint)
        }

        return factory()
    }
}

final class ManifestLoader {
    func loadManifests(resourceURLs: [URL]) throws -> [String: ModuleManifest] {
        let decoder = JSONDecoder()
        var manifests: [String: ModuleManifest] = [:]

        for resourceURL in resourceURLs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let manifest = try decoder.decode(ModuleManifest.self, from: Data(contentsOf: resourceURL))
            guard manifests[manifest.moduleID] == nil else {
                throw ManifestLoaderError.duplicateModuleID(manifest.moduleID)
            }
            manifests[manifest.moduleID] = manifest
        }

        return manifests
    }

    func loadManifests(bundle: Bundle = .main, subdirectory: String = "ForsettiManifests") throws -> [ModuleManifest] {
        var resourceURLs = bundle.urls(forResourcesWithExtension: "json", subdirectory: subdirectory) ?? []

        if resourceURLs.isEmpty {
            resourceURLs = (bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? [])
                .filter { $0.deletingPathExtension().lastPathComponent.hasSuffix("Module") }
        }

        guard !resourceURLs.isEmpty else {
            throw ManifestLoaderError.noManifestResourcesFound(subdirectory)
        }

        return try loadManifests(resourceURLs: resourceURLs)
            .values
            .sorted { $0.moduleID < $1.moduleID }
    }
}

enum ManifestLoaderError: Error, LocalizedError {
    case noManifestResourcesFound(String)
    case duplicateModuleID(String)

    var errorDescription: String? {
        switch self {
        case let .noManifestResourcesFound(subdirectory):
            return "No module manifest resources were found in '\(subdirectory)' or the application bundle root."
        case let .duplicateModuleID(moduleID):
            return "Duplicate module manifest ID '\(moduleID)'."
        }
    }
}

struct CompatibilityChecker {
    let appVersion: String
    let platform: Platform

    init(appVersion: String = ForsettiAppVersion.current, platform: Platform = .current) {
        self.appVersion = appVersion
        self.platform = platform
    }

    func validate(_ manifest: ModuleManifest) throws {
        guard manifest.appVersion == appVersion else {
            throw CompatibilityError.appVersionMismatch(moduleID: manifest.moduleID, expected: appVersion, actual: manifest.appVersion)
        }

        guard manifest.supportedPlatforms.contains(platform) else {
            throw CompatibilityError.unsupportedPlatform(moduleID: manifest.moduleID, platform: platform)
        }

        if let role = manifest.defaultModuleRole, !role.isValid(for: manifest.moduleType) {
            throw CompatibilityError.invalidDefaultRole(moduleID: manifest.moduleID)
        }
    }
}

enum CompatibilityError: Error, LocalizedError {
    case appVersionMismatch(moduleID: String, expected: String, actual: String)
    case unsupportedPlatform(moduleID: String, platform: Platform)
    case invalidDefaultRole(moduleID: String)

    var errorDescription: String? {
        switch self {
        case let .appVersionMismatch(moduleID, expected, actual):
            return "\(moduleID) requires appVersion \(actual), but runtime expected \(expected)."
        case let .unsupportedPlatform(moduleID, platform):
            return "\(moduleID) does not support \(platform.rawValue)."
        case let .invalidDefaultRole(moduleID):
            return "\(moduleID) declares a default role that is invalid for its module type."
        }
    }
}

final class CapabilityPolicy: @unchecked Sendable {
    private let allowedCapabilities: Set<Capability>

    init(allowedCapabilities: Set<Capability> = Set(Capability.allCases)) {
        self.allowedCapabilities = allowedCapabilities
    }

    func grantedCapabilities(for manifest: ModuleManifest) -> Set<Capability> {
        Set(manifest.capabilitiesRequested).intersection(allowedCapabilities)
    }
}

protocol ActivationStore: Sendable {
    func loadActiveModuleIDs() -> Set<String>
    func saveActiveModuleIDs(_ moduleIDs: Set<String>)
}

final class UserDefaultsActivationStore: ActivationStore, @unchecked Sendable {
    private let defaults: UserDefaults
    private let key: String

    init(defaults: UserDefaults = .standard, key: String) {
        self.defaults = defaults
        self.key = key
    }

    func loadActiveModuleIDs() -> Set<String> {
        Set(defaults.stringArray(forKey: key) ?? [])
    }

    func saveActiveModuleIDs(_ moduleIDs: Set<String>) {
        defaults.set(moduleIDs.sorted(), forKey: key)
    }
}

struct RuntimeEvent: Sendable {
    let type: String
    let sourceModuleID: String?
    let payload: [String: String]
    let date: Date
}

final class EventBus: @unchecked Sendable {
    typealias Handler = @Sendable (RuntimeEvent) -> Void

    private let lock = NSLock()
    private var handlers: [UUID: Handler] = [:]

    @discardableResult
    func subscribe(_ handler: @escaping Handler) -> UUID {
        let id = UUID()
        lock.lock()
        handlers[id] = handler
        lock.unlock()
        return id
    }

    func unsubscribe(_ id: UUID) {
        lock.lock()
        handlers[id] = nil
        lock.unlock()
    }

    func publish(type: String, sourceModuleID: String? = nil, payload: [String: String] = [:]) {
        let event = RuntimeEvent(type: type, sourceModuleID: sourceModuleID, payload: payload, date: Date())
        lock.lock()
        let currentHandlers = Array(handlers.values)
        lock.unlock()
        currentHandlers.forEach { $0(event) }
    }
}

enum LogLevel: String, Sendable {
    case debug
    case info
    case warning
    case error
}

protocol RuntimeDiagnosticsLogging: Sendable {
    func log(_ level: LogLevel, message: String, metadata: [String: String])
}

extension RuntimeDiagnosticsLogging {
    func debug(_ message: String, metadata: [String: String] = [:]) {
        log(.debug, message: message, metadata: metadata)
    }

    func info(_ message: String, metadata: [String: String] = [:]) {
        log(.info, message: message, metadata: metadata)
    }

    func warning(_ message: String, metadata: [String: String] = [:]) {
        log(.warning, message: message, metadata: metadata)
    }

    func error(_ message: String, metadata: [String: String] = [:]) {
        log(.error, message: message, metadata: metadata)
    }
}

final class AppRuntimeLogger: RuntimeDiagnosticsLogging, @unchecked Sendable {
#if canImport(OSLog)
    private let logger: Logger
#endif

    init(subsystem: String = "com.forsetti.jamfpro", category: String = "runtime") {
#if canImport(OSLog)
        logger = Logger(subsystem: subsystem, category: category)
#endif
    }

    func log(_ level: LogLevel, message: String, metadata: [String: String] = [:]) {
        let renderedMessage: String
        if metadata.isEmpty {
            renderedMessage = message
        } else {
            let renderedMetadata = metadata
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: " ")
            renderedMessage = "\(message) [\(renderedMetadata)]"
        }

#if canImport(OSLog)
        switch level {
        case .debug:
            logger.debug("\(renderedMessage, privacy: .public)")
        case .info:
            logger.info("\(renderedMessage, privacy: .public)")
        case .warning:
            logger.warning("\(renderedMessage, privacy: .public)")
        case .error:
            logger.error("\(renderedMessage, privacy: .public)")
        }
#else
#if DEBUG
        print("[Forsetti][\(level.rawValue.uppercased())] \(renderedMessage)")
#endif
#endif
    }
}

protocol ForsettiServiceProviding: Sendable {
    func resolve<T>(_ type: T.Type) -> T?
}

final class ServiceContainer: ForsettiServiceProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var services: [ObjectIdentifier: Any] = [:]

    func register<T>(_ type: T.Type, service: T) {
        lock.lock()
        services[ObjectIdentifier(type)] = service
        lock.unlock()
    }

    func resolve<T>(_ type: T.Type) -> T? {
        lock.lock()
        defer { lock.unlock() }
        return services[ObjectIdentifier(type)] as? T
    }
}

typealias ForsettiServiceContainer = ServiceContainer

final class CapabilityScopedServiceProvider: ForsettiServiceProviding, @unchecked Sendable {
    private let baseProvider: any ForsettiServiceProviding
    private let grantedCapabilities: Set<Capability>

    init(baseProvider: any ForsettiServiceProviding, grantedCapabilities: Set<Capability>) {
        self.baseProvider = baseProvider
        self.grantedCapabilities = grantedCapabilities
    }

    func resolve<T>(_ type: T.Type) -> T? {
        guard let requiredCapability = Self.requiredCapability(for: type),
              grantedCapabilities.contains(requiredCapability)
        else {
            return nil
        }

        return baseProvider.resolve(type)
    }

    private static func requiredCapability<T>(for type: T.Type) -> Capability? {
        serviceCapabilities[ObjectIdentifier(type)]
    }

    private static let serviceCapabilities: [ObjectIdentifier: Capability] = [
        ObjectIdentifier(NetworkingService.self): .networking,
        ObjectIdentifier(StorageService.self): .storage,
        ObjectIdentifier(SecureStorageService.self): .secureStorage,
        ObjectIdentifier(FileExportService.self): .fileExport,
        ObjectIdentifier(TelemetryService.self): .telemetry,
        ObjectIdentifier(SharedDatabaseService.self): .sharedDatabase,
        ObjectIdentifier(AuthenticationService.self): .authentication,
        ObjectIdentifier(DiagnosticsService.self): .diagnostics,
        ObjectIdentifier(APIService.self): .api,
        ObjectIdentifier(SecurityService.self): .security
    ]
}

protocol NetworkingService: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

protocol StorageService: Sendable {
    func set(_ value: String, forKey key: String)
    func value(forKey key: String) -> String?
    func removeValue(forKey key: String)
}

protocol SecureStorageService: Sendable {
    func set(_ value: Data, forKey key: String) throws
    func value(forKey key: String) throws -> Data?
    func removeValue(forKey key: String) throws
}

protocol FileExportService: Sendable {
    func export(data: Data, suggestedFileName: String) throws -> URL
}

protocol TelemetryService: Sendable {
    func track(event: String, properties: [String: String])
}

protocol SharedDatabaseService: Sendable {}
protocol AuthenticationService: Sendable {}
protocol DiagnosticsService: Sendable {}
protocol APIService: Sendable {}
protocol SecurityService: Sendable {}

final class URLSessionNetworkingService: NetworkingService, @unchecked Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }
}

final class UserDefaultsStorageService: StorageService, @unchecked Sendable {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func set(_ value: String, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    func value(forKey key: String) -> String? {
        defaults.string(forKey: key)
    }

    func removeValue(forKey key: String) {
        defaults.removeObject(forKey: key)
    }
}

enum KeychainSecureStorageError: Error, LocalizedError {
    case unavailable
    case unexpectedStatus(Int32)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Secure storage is unavailable on this platform."
        case let .unexpectedStatus(status):
            return "Keychain operation failed with status \(status)."
        }
    }
}

final class KeychainSecureStorageService: SecureStorageService, @unchecked Sendable {
    private let service: String

    init(service: String = "com.forsetti.jamfpro") {
        self.service = service
    }

    func set(_ value: Data, forKey key: String) throws {
#if canImport(Security)
        var addQuery = keychainQuery(forKey: key)
        addQuery[kSecValueData as String] = value

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        if status == errSecDuplicateItem {
            try validate(status: SecItemUpdate(keychainQuery(forKey: key) as CFDictionary, [kSecValueData as String: value] as CFDictionary))
            return
        }

        try validate(status: status)
#else
        throw KeychainSecureStorageError.unavailable
#endif
    }

    func value(forKey key: String) throws -> Data? {
#if canImport(Security)
        var query = keychainQuery(forKey: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }

        try validate(status: status)
        return result as? Data
#else
        throw KeychainSecureStorageError.unavailable
#endif
    }

    func removeValue(forKey key: String) throws {
#if canImport(Security)
        let status = SecItemDelete(keychainQuery(forKey: key) as CFDictionary)
        if status == errSecItemNotFound {
            return
        }
        try validate(status: status)
#else
        throw KeychainSecureStorageError.unavailable
#endif
    }

#if canImport(Security)
    private func keychainQuery(forKey key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }

    private func validate(status: OSStatus) throws {
        guard status == errSecSuccess else {
            throw KeychainSecureStorageError.unexpectedStatus(Int32(status))
        }
    }
#endif
}

enum LocalFileExportError: Error, LocalizedError {
    case invalidFileName
    case targetEscapesExportDirectory

    var errorDescription: String? {
        switch self {
        case .invalidFileName:
            return "The suggested file name is invalid."
        case .targetEscapesExportDirectory:
            return "The export target must remain inside the export directory."
        }
    }
}

final class LocalFileExportService: FileExportService, @unchecked Sendable {
    private let directoryURL: URL

    init(directoryURL: URL = FileManager.default.temporaryDirectory) {
        self.directoryURL = directoryURL
    }

    func export(data: Data, suggestedFileName: String) throws -> URL {
        let fileName = try sanitized(fileName: suggestedFileName)
        let exportDirectory = directoryURL.standardizedFileURL
        try FileManager.default.createDirectory(at: exportDirectory, withIntermediateDirectories: true)

        let targetURL = exportDirectory.appendingPathComponent(fileName).standardizedFileURL
        guard targetURL.deletingLastPathComponent().path == exportDirectory.path else {
            throw LocalFileExportError.targetEscapesExportDirectory
        }

        try data.write(to: targetURL, options: .atomic)
        return targetURL
    }

    private func sanitized(fileName: String) throws -> String {
        let lastPathComponent = URL(fileURLWithPath: fileName).lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lastPathComponent.isEmpty, lastPathComponent != ".", lastPathComponent != ".." else {
            throw LocalFileExportError.invalidFileName
        }
        return lastPathComponent
    }
}

protocol ForsettiModuleContext: AnyObject {
    var moduleID: String { get }
    var services: any ForsettiServiceProviding { get }
    var eventBus: EventBus { get }
    var logger: any RuntimeDiagnosticsLogging { get }
}

extension ForsettiModuleContext {
    func publishEvent(type: String, payload: [String: String] = [:]) {
        eventBus.publish(type: type, sourceModuleID: moduleID, payload: payload)
    }
}

final class AppModuleContext: ForsettiModuleContext {
    let moduleID: String
    let services: any ForsettiServiceProviding
    let eventBus: EventBus
    let logger: any RuntimeDiagnosticsLogging

    init(
        moduleID: String,
        services: any ForsettiServiceProviding,
        eventBus: EventBus,
        logger: any RuntimeDiagnosticsLogging
    ) {
        self.moduleID = moduleID
        self.services = services
        self.eventBus = eventBus
        self.logger = logger
    }
}

@MainActor
final class RuntimeController: ObservableObject {
    @Published private(set) var enabledServiceModuleIDs: Set<String> = []
    @Published private(set) var activeUIModuleID: String?
    @Published private(set) var errorMessage: String?

    let registry: ModuleRegistry
    let services: ServiceContainer
    let eventBus: EventBus

    private let compatibilityChecker: CompatibilityChecker
    private let capabilityPolicy: CapabilityPolicy
    private let activationStore: any ActivationStore
    private let logger: any RuntimeDiagnosticsLogging
    private var activeModules: [String: any ForsettiModule] = [:]

    init(
        registry: ModuleRegistry,
        services: ServiceContainer,
        eventBus: EventBus = EventBus(),
        compatibilityChecker: CompatibilityChecker = CompatibilityChecker(),
        capabilityPolicy: CapabilityPolicy = CapabilityPolicy(),
        activationStore: any ActivationStore = UserDefaultsActivationStore(key: "com.forsetti.jamfpro.activation.state"),
        logger: any RuntimeDiagnosticsLogging = AppRuntimeLogger()
    ) {
        self.registry = registry
        self.services = services
        self.eventBus = eventBus
        self.compatibilityChecker = compatibilityChecker
        self.capabilityPolicy = capabilityPolicy
        self.activationStore = activationStore
        self.logger = logger
    }

    func boot(manifests: [ModuleManifest], activationOrder: [String]) async {
        clearError()

        do {
            try validatePatternB(manifests: manifests)
            let manifestByID = Dictionary(uniqueKeysWithValues: manifests.map { ($0.moduleID, $0) })
            for moduleID in activationOrder {
                guard let manifest = manifestByID[moduleID] else {
                    throw RuntimeControllerError.missingManifest(moduleID)
                }
                try activate(manifest: manifest)
            }
            activationStore.saveActiveModuleIDs(Set(activationOrder))
        } catch {
            errorMessage = error.localizedDescription
            logger.error("Runtime boot failed.", metadata: ["error": error.localizedDescription])
        }
    }

    func clearError() {
        errorMessage = nil
    }

    private func activate(manifest: ModuleManifest) throws {
        try compatibilityChecker.validate(manifest)

        let module = try registry.makeModule(entryPoint: manifest.entryPoint)
        guard module.manifest == manifest else {
            throw RuntimeControllerError.manifestMismatch(manifest.moduleID)
        }

        let scopedProvider = CapabilityScopedServiceProvider(
            baseProvider: services,
            grantedCapabilities: capabilityPolicy.grantedCapabilities(for: manifest)
        )
        let context = AppModuleContext(
            moduleID: manifest.moduleID,
            services: scopedProvider,
            eventBus: eventBus,
            logger: logger
        )
        try module.start(context: context)

        activeModules[manifest.moduleID] = module
        switch manifest.moduleType {
        case .service:
            enabledServiceModuleIDs.insert(manifest.moduleID)
        case .ui, .app:
            activeUIModuleID = manifest.moduleID
        }
    }

    private func validatePatternB(manifests: [ModuleManifest]) throws {
        let uiManifests = manifests.filter { $0.moduleType == .ui }
        guard uiManifests.count == 1 else {
            throw RuntimeControllerError.invalidUIModuleCount(uiManifests.count)
        }
    }
}

enum RuntimeControllerError: Error, LocalizedError {
    case missingManifest(String)
    case manifestMismatch(String)
    case invalidUIModuleCount(Int)

    var errorDescription: String? {
        switch self {
        case let .missingManifest(moduleID):
            return "Required module manifest missing: \(moduleID)."
        case let .manifestMismatch(moduleID):
            return "Registered module does not match manifest \(moduleID)."
        case let .invalidUIModuleCount(count):
            return "Pattern B requires exactly one UI module; observed \(count)."
        }
    }
}
