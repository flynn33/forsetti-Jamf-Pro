import Foundation

/// Defines the scope of an asset search -- all device types, computers only, or mobile devices only.
///
/// Used by the search scope segmented picker to let the technician narrow results
/// and reduce noise from irrelevant device types.
enum SupportSearchScope: String, CaseIterable, Identifiable, Sendable {
    case all
    case computers
    case mobileDevices

    /// The raw value serves as a stable identifier for `Identifiable` conformance.
    var id: String { rawValue }

    /// Human-readable label for the segmented picker control.
    nonisolated var title: String {
        switch self {
        case .all:
            return "All"
        case .computers:
            return "Computers"
        case .mobileDevices:
            return "Mobile"
        }
    }
}

// "Would you like to play a game?"

/// Categorizes a managed asset as either a computer or mobile device.
///
/// Determines which API endpoints are used for detail fetching, which management
/// actions are available, and which icon is shown in search result rows.
enum SupportAssetType: String, CaseIterable, Identifiable, Sendable {
    case computer
    case mobileDevice

    /// The raw value serves as a stable identifier for `Identifiable` conformance.
    var id: String { rawValue }

    /// Human-readable label shown in asset type badges and detail views.
    nonisolated var title: String {
        switch self {
        case .computer:
            return "Computer"
        case .mobileDevice:
            return "Mobile Device"
        }
    }

    /// SF Symbol name used as the leading icon in search result rows.
    nonisolated var iconSystemName: String {
        switch self {
        case .computer:
            return "desktopcomputer"
        case .mobileDevice:
            return "iphone.gen3"
        }
    }
}

/// A single search result representing a managed computer or mobile device.
///
/// Contains the minimal set of fields needed to display a result row and to
/// navigate to the full device detail view. The `id` is synthesized from the
/// asset type and inventory ID to ensure uniqueness across device types.
nonisolated struct SupportSearchResult: Identifiable, Hashable, Sendable {
    /// Whether this result represents a computer or mobile device.
    let assetType: SupportAssetType

    /// The Jamf Pro inventory record identifier.
    let inventoryID: String

    /// The MDM management identifier, required for queuing MDM commands. `nil` when missing.
    let managementID: String?

    /// The client-side management identifier, required for LAPS operations. `nil` when missing.
    let clientManagementID: String?

    /// The device's display name as shown in Jamf Pro.
    let displayName: String

    /// The hardware serial number.
    let serialNumber: String

    /// The assigned username, if any.
    let username: String?

    /// The assigned user's email address, if any.
    let email: String?

    /// The hardware model string (e.g. "MacBook Pro 16-inch"), if available.
    let model: String?

    /// The operating system version string, if available.
    let osVersion: String?

    /// ISO 8601 timestamp of the last inventory update, if available.
    let lastInventoryUpdate: String?

    /// PreStage enrollment name or identifier reported by Jamf inventory.
    let prestageEnrollment: String?

    /// Whether inventory reports Automated Device Enrollment for this device.
    let automatedDeviceEnrollment: Bool?

    /// A composite identifier combining asset type and inventory ID for cross-type uniqueness.
    var id: String {
        "\(assetType.rawValue)-\(inventoryID)"
    }
}

/// A single key-value pair displayed in the device detail sections.
nonisolated struct SupportDetailItem: Identifiable, Hashable, Sendable {
    /// The field label (e.g. "Serial Number", "OS Version").
    let key: String

    /// The field value as a displayable string.
    let value: String

    /// Composite identifier for SwiftUI list diffing.
    var id: String { "\(key):\(value)" }
}

/// A named group of detail items forming a collapsible section in the device detail view.
nonisolated struct SupportDetailSection: Identifiable, Hashable, Sendable {
    /// The section heading (e.g. "General", "Hardware", "Security").
    let title: String

    /// The key-value pairs displayed within this section.
    let items: [SupportDetailItem]

    /// The section title serves as the stable identifier.
    var id: String { title }
}

// "A robot may not injure a human being or, through inaction, allow a human being to come to harm.
//  A robot must obey the orders given it by human beings except where such orders would conflict with the First Law.
//  A robot must protect its own existence as long as such protection does not conflict with the First or Second Law."

/// Severity levels for device health diagnostic indicators.
///
/// Each severity maps to a distinct icon and color in the diagnostics section
/// to help technicians quickly triage device health.
enum SupportDiagnosticSeverity: String, Sendable {
    case info
    case warning
    case critical

    /// SF Symbol name for the diagnostic severity icon.
    var iconSystemName: String {
        switch self {
        case .info:
            return "checkmark.circle"
        case .warning:
            return "exclamationmark.triangle"
        case .critical:
            return "xmark.octagon"
        }
    }
}

/// A single diagnostic check result shown in the device diagnostics section.
///
/// Examples include management ID presence, FileVault status, inventory age,
/// and supervision state -- each with an appropriate severity indicator.
nonisolated struct SupportDiagnosticItem: Identifiable, Hashable, Sendable {
    /// The diagnostic check name (e.g. "FileVault", "Inventory Age").
    let title: String

    /// The diagnostic result value (e.g. "Enabled", "14 day(s)").
    let value: String

    /// The severity level determining the icon and color treatment.
    let severity: SupportDiagnosticSeverity

    /// Composite identifier for SwiftUI list diffing.
    var id: String { "\(title):\(value)" }
}

/// The full detail record for a managed device, combining the search result summary,
/// health diagnostics, structured inventory sections, application list, and raw JSON.
///
/// The redesigned Technician Module reads from `categorized`, `extensionAttributes`,
/// and `hardwareSpecs` for the new category-frame layout. The legacy `sections`
/// array is kept populated for raw-payload fallback rendering.
nonisolated struct SupportDeviceDetail: Identifiable, Hashable, Sendable {
    /// The original search result summary containing identity fields.
    let summary: SupportSearchResult

    /// Health and posture diagnostic checks derived from inventory data.
    let diagnostics: [SupportDiagnosticItem]

    /// Structured inventory sections (General, Hardware, Security, etc.).
    let sections: [SupportDetailSection]

    /// Names of applications discovered on the device via inventory.
    let applications: [String]

    /// The full Jamf Pro API response as pretty-printed JSON for troubleshooting.
    let rawJSON: String

    /// Sections grouped by category for the redesigned frame layout. Defaults
    /// to `.empty` when the API service hasn't classified the payload yet —
    /// the view falls back to `sections` in that case.
    let categorized: CategorizedDeviceDetail

    /// Extension attributes as typed name/value pairs. Replaces the previous
    /// generic-array rendering that produced unreadable "item 1: {...}" rows.
    let extensionAttributes: [SupportExtensionAttribute]

    /// Hardware specifications extracted up-front so the General frame can
    /// drive the storage gauge and the CPU/RAM spec cards directly.
    let hardwareSpecs: SupportHardwareSpecs?

    /// OS-specific fields surfaced in the OS frame. `nil` when the payload
    /// didn't yield any usable OS values.
    let osInfo: SupportOSInfo?

    /// Security posture fields surfaced in the Security frame.
    let securityProfile: SupportSecurityProfile?

    /// Network identifiers surfaced in the Network frame.
    let networkInfo: SupportNetworkInfo?

    /// Device group memberships surfaced in the Group frame.
    let deviceGroups: [SupportDeviceGroup]

    /// Configuration profiles assigned to the device, surfaced in the Profiles frame.
    let configurationProfiles: [SupportDeviceProfile]

    /// Local user accounts on a Mac, surfaced in the User Accounts frame.
    /// Mobile devices report an empty list.
    let localUsers: [SupportLocalUser]

    /// Explicit init that supplies safe defaults for the new fields so the
    /// existing API-service call site keeps compiling unchanged while the
    /// service is updated to populate the new fields.
    init(
        summary: SupportSearchResult,
        diagnostics: [SupportDiagnosticItem],
        sections: [SupportDetailSection],
        applications: [String],
        rawJSON: String,
        categorized: CategorizedDeviceDetail = .empty,
        extensionAttributes: [SupportExtensionAttribute] = [],
        hardwareSpecs: SupportHardwareSpecs? = nil,
        osInfo: SupportOSInfo? = nil,
        securityProfile: SupportSecurityProfile? = nil,
        networkInfo: SupportNetworkInfo? = nil,
        deviceGroups: [SupportDeviceGroup] = [],
        configurationProfiles: [SupportDeviceProfile] = [],
        localUsers: [SupportLocalUser] = []
    ) {
        self.summary = summary
        self.diagnostics = diagnostics
        self.sections = sections
        self.applications = applications
        self.rawJSON = rawJSON
        self.categorized = categorized
        self.extensionAttributes = extensionAttributes
        self.hardwareSpecs = hardwareSpecs
        self.osInfo = osInfo
        self.securityProfile = securityProfile
        self.networkInfo = networkInfo
        self.deviceGroups = deviceGroups
        self.configurationProfiles = configurationProfiles
        self.localUsers = localUsers
    }

    /// Delegates identity to the search result summary.
    var id: String {
        summary.id
    }
}


// MARK: - Application Manager (v3.18+)

/// A single application discovered on a managed Mac via the Jamf Pro
/// `APPLICATIONS` inventory section.
///
/// Populated exclusively from `GET /api/v1/computers-inventory/{id}?section=APPLICATIONS` —
/// no catalog data and no install-state inference. The ID falls back from
/// bundle identifier to path to display name so rows remain stable across
/// refreshes even when Jamf omits some fields for a given app.
///
/// Declared `nonisolated` so instances can freely cross actor boundaries —
/// the project sets `-default-isolation MainActor`, which would otherwise
/// pin the synthesized `Equatable`/`Hashable` conformances to the main
/// actor and block usage from the `SupportTechnicianAPIService` actor.
nonisolated struct DeviceApplication: Identifiable, Hashable, Sendable {
    /// Stable selection / diffing key. Prefers `bundleIdentifier`, then `path`,
    /// then `displayName`. Never empty.
    let id: String

    /// Exact display name reported by the device. This is the value the
    /// zsh wrapper passes to `jamf policy -trigger install-<name>` /
    /// `uninstall-<name>`, so it must be preserved verbatim.
    let displayName: String

    /// Version string as reported by the device (e.g. "4.37.101"). `nil` when
    /// the Jamf payload omits it — not all inventory records include version.
    let version: String?

    /// Install path on disk (e.g. "/Applications/Slack.app"). `nil` when the
    /// payload omits it.
    let path: String?

    /// Bundle identifier (e.g. "com.tinyspeck.slackmacgap"). `nil` for apps
    /// the device's agent couldn't resolve.
    let bundleIdentifier: String?
}

/// A command issued against a specific application on the target Mac.
///
/// Both cases carry the exact application display name so the downstream
/// script and policy can reference it verbatim. The `customTrigger` computed
/// property yields the Jamf Pro custom-trigger string the admin is expected
/// to have configured on the server side (e.g. `install-Slack`,
/// `uninstall-Microsoft Word`).
///
/// Declared `nonisolated` for the same reason as `DeviceApplication` — this
/// value is passed across the main-actor / service-actor boundary.
nonisolated enum ApplicationAction: Hashable, Sendable {
    case install(appName: String)
    case uninstall(appName: String)

    /// The exact application display name this action targets.
    var appName: String {
        switch self {
        case let .install(appName), let .uninstall(appName):
            return appName
        }
    }

    /// The custom-trigger string the wrapper script passes to `jamf policy -trigger`.
    /// The admin is expected to have a matching pre-existing policy on Jamf Pro.
    var customTrigger: String {
        switch self {
        case let .install(appName):
            return "install-\(appName)"
        case let .uninstall(appName):
            return "uninstall-\(appName)"
        }
    }

    /// Short verb for UI labels (Install / Uninstall).
    var verb: String {
        switch self {
        case .install:
            return "Install"
        case .uninstall:
            return "Uninstall"
        }
    }

    /// Past-participle for status banners ("Install queued for …", "Uninstall queued for …").
    var queuedVerb: String {
        switch self {
        case .install:
            return "Install"
        case .uninstall:
            return "Uninstall"
        }
    }

    /// Title for the standard confirmation alert.
    var confirmationTitle: String {
        switch self {
        case let .install(appName):
            return "Install \(appName)?"
        case let .uninstall(appName):
            return "Uninstall \(appName)?"
        }
    }

    /// Message for the standard confirmation alert. Explains the indirect,
    /// non-destructive semantics so the technician doesn't misread
    /// "Uninstall" as a permanent removal.
    var confirmationMessage: String {
        switch self {
        case let .install(appName):
            return "A one-shot Jamf Pro policy runs on this device at its next check-in and fires the install-\(appName) custom trigger."
        case let .uninstall(appName):
            return "A one-shot Jamf Pro policy runs on this device at its next check-in and fires the uninstall-\(appName) custom trigger. If the device's group still assigns the app, it reinstalls automatically on the following check-in."
        }
    }
}

/// The post-action verification state for the most recent Application
/// Manager action.
///
/// The view model transitions through these states while polling the
/// APPLICATIONS inventory section to confirm the device actually executed
/// the queued policy. The view renders a matching banner per state so the
/// technician knows whether the action landed, is still pending, or timed
/// out and needs a manual check.
enum ApplicationActionVerificationState: Sendable {
    /// No action has been dispatched, or the last one is fully complete.
    case idle

    /// Action dispatched to Jamf Pro; device has not yet checked in.
    /// The polling task is running and will transition to `.checkingIn`
    /// on the first APPLICATIONS fetch after dispatch, or directly to
    /// `.verified` / `.timedOut` depending on the outcome.
    case queued(action: ApplicationAction, serialNumber: String, startedAt: Date)

    /// Mid-poll — at least one APPLICATIONS fetch has completed since dispatch
    /// but the expected state (app present for install / app absent for
    /// uninstall) has not yet been observed.
    case checkingIn(
        action: ApplicationAction,
        serialNumber: String,
        startedAt: Date,
        attempt: Int
    )

    /// The expected state was observed. Terminal.
    case verified(action: ApplicationAction, serialNumber: String, duration: TimeInterval)

    /// Polling exhausted its budget without observing the expected state.
    /// Terminal. The admin can verify manually via Jamf Pro's device policy
    /// log or by re-running the action.
    case timedOut(action: ApplicationAction, serialNumber: String)
}

/// The outcome of a successful `triggerAppPolicy` call.
///
/// Carries every ID the Support Technician view needs to report the action
/// in the UI banner and in diagnostics — nothing is inferred or re-derived
/// from the request later. On failure, the service throws instead of
/// returning this record.
struct ApplicationActionResult: Sendable {
    /// The action that was queued.
    let action: ApplicationAction

    /// Jamf Pro inventory ID of the target computer.
    let inventoryID: String

    /// Serial number of the target computer — used for the UI status string
    /// and for cross-checking that Jamf delivered the policy to the right
    /// device.
    let serialNumber: String

    /// ID of the transient script created for this action (`POST /api/v1/scripts`).
    let scriptID: String

    /// ID of the one-shot policy created for this action
    /// (`POST /JSSResource/policies/id/0`).
    let policyID: String

    /// Custom-trigger string the delivered script will fire.
    var customTrigger: String { action.customTrigger }

    /// ISO-8601 timestamp recorded when the result was constructed. Used by
    /// the ephemeral-cleanup queue to purge script and policy records older
    /// than 24 hours on next app launch.
    let createdAt: Date
}

// MARK: - MDM management actions

/// MDM management actions that can be performed on a selected device.
///
/// Actions range from non-destructive inventory refreshes to highly destructive
/// operations like device erasure. Each case carries UI metadata and confirmation
/// requirements proportional to its severity.
enum SupportManagementAction: String, CaseIterable, Identifiable, Sendable {
    case refreshInventory
    case blankPush
    case discoverApplications
    case restartDevice
    case shutDownDevice
    case sendDeviceLock
    case logOutUser
    case clearPasscode
    case eraseDevice
    case viewFileVaultPersonalRecoveryKey
    case viewRecoveryLockPassword
    case viewDeviceLockPIN
    case viewLAPSAccountPassword
    case rotateLAPSPassword
    // -- Mobile-leaning commands added in 3.22.1 --
    case enableBluetooth
    case disableBluetooth
    case enableLostMode
    case disableLostMode
    case playLostModeSound
    case requestDeviceLocation
    case clearRestrictionsPassword
    case refreshCellularPlans
    case scheduleOSUpdate
    case settingsSync
    // -- Wi-Fi toggles (Classic Settings command) — 3.22.7 --
    case enableWifi
    case disableWifi
    // -- FileVault — 3.22.7 — Mac only --
    case enableFileVault
    case redeployManagementFramework
    // -- Legacy management account password (jssmanage) — 3.22.8 — Mac only --
    case viewJamfManagementAccountPassword

    /// The raw value serves as a stable identifier.
    var id: String { rawValue }

    /// Short button label for the management action.
    nonisolated var title: String {
        switch self {
        case .refreshInventory:
            return "Update Inventory"
        case .blankPush:
            return "Blank Push"
        case .discoverApplications:
            return "Discover Applications"
        case .restartDevice:
            return "Restart Device"
        case .shutDownDevice:
            return "Shut Down Device"
        case .sendDeviceLock:
            return "Send Device Lock"
        case .logOutUser:
            return "Log Out User"
        case .clearPasscode:
            return "Clear Passcode"
        case .eraseDevice:
            return "Erase Device"
        case .viewFileVaultPersonalRecoveryKey:
            return "View FileVault Key"
        case .viewRecoveryLockPassword:
            return "View Recovery Lock"
        case .viewDeviceLockPIN:
            return "View Device Lock PIN"
        case .viewLAPSAccountPassword:
            return "View LAPS Password"
        case .rotateLAPSPassword:
            return "Rotate LAPS Password"
        case .enableBluetooth:
            return "Turn On Bluetooth"
        case .disableBluetooth:
            return "Turn Off Bluetooth"
        case .enableLostMode:
            return "Enable Lost Mode"
        case .disableLostMode:
            return "Disable Lost Mode"
        case .playLostModeSound:
            return "Play Lost Mode Sound"
        case .requestDeviceLocation:
            return "Request Device Location"
        case .clearRestrictionsPassword:
            return "Clear Restrictions Password"
        case .refreshCellularPlans:
            return "Refresh Cellular Plans"
        case .scheduleOSUpdate:
            return "Schedule OS Update"
        case .settingsSync:
            return "Sync Device Settings"
        case .enableWifi:
            return "Turn On Wi-Fi"
        case .disableWifi:
            return "Turn Off Wi-Fi"
        case .enableFileVault:
            return "Enable FileVault"
        case .redeployManagementFramework:
            return "Redeploy Management Framework"
        case .viewJamfManagementAccountPassword:
            return "View jssmanage Password"
        }
    }

    /// Longer description shown below the action title explaining what it does.
    var subtitle: String {
        switch self {
        case .refreshInventory:
            return "Queue MDM inventory collection"
        case .blankPush:
            return "Send an empty APNs push to force an MDM check-in"
        case .discoverApplications:
            return "Queue installed application discovery"
        case .restartDevice:
            return "Queue remote restart command"
        case .shutDownDevice:
            return "Queue remote shut-down command"
        case .sendDeviceLock:
            return "Lock the device (Macs return a 6-digit PIN)"
        case .logOutUser:
            return "Log out the currently signed-in user (Mac)"
        case .clearPasscode:
            return "Clear device passcode (PIN)"
        case .eraseDevice:
            return "Send erase command"
        case .viewFileVaultPersonalRecoveryKey:
            return "Retrieve personal recovery key"
        case .viewRecoveryLockPassword:
            return "Retrieve recovery lock password"
        case .viewDeviceLockPIN:
            return "Retrieve lock PIN from Jamf"
        case .viewLAPSAccountPassword:
            return "Retrieve local admin account password"
        case .rotateLAPSPassword:
            return "Rotate local admin account password"
        case .enableBluetooth:
            return "Settings command — turn Bluetooth on (Classic API)"
        case .disableBluetooth:
            return "Settings command — turn Bluetooth off (Classic API)"
        case .enableLostMode:
            return "Place this supervised device in Lost Mode"
        case .disableLostMode:
            return "Exit Lost Mode on this device"
        case .playLostModeSound:
            return "Play an audible alert on this device"
        case .requestDeviceLocation:
            return "Query the device's last reported location"
        case .clearRestrictionsPassword:
            return "Remove the Screen Time / restrictions PIN"
        case .refreshCellularPlans:
            return "Refresh installed eSIM cellular plans"
        case .scheduleOSUpdate:
            return "Schedule the next OS update install"
        case .settingsSync:
            return "Push a generic Settings payload (no-op sync)"
        case .enableWifi:
            return "Settings command — turn Wi-Fi on (Classic API)"
        case .disableWifi:
            return "Settings command — turn Wi-Fi off (Classic API)"
        case .enableFileVault:
            return "Redeploy the management framework so the assigned FileVault configuration profile re-applies"
        case .redeployManagementFramework:
            return "POST /api/v1/jamf-management-framework/redeploy/{id} — re-runs jamf binary management"
        case .viewJamfManagementAccountPassword:
            return "Retrieves the password for the legacy jssmanage local-admin account from Jamf LAPS"
        }
    }

    /// SF Symbol name for the action button icon.
    var systemImage: String {
        switch self {
        case .refreshInventory:
            return "arrow.clockwise"
        case .blankPush:
            return "paperplane"
        case .discoverApplications:
            return "square.stack.3d.up"
        case .restartDevice:
            return "restart"
        case .shutDownDevice:
            return "power"
        case .sendDeviceLock:
            return "lock"
        case .logOutUser:
            return "rectangle.portrait.and.arrow.right"
        case .clearPasscode:
            return "key.slash"
        case .eraseDevice:
            return "trash"
        case .viewFileVaultPersonalRecoveryKey:
            return "key"
        case .viewRecoveryLockPassword:
            return "lock.shield"
        case .viewDeviceLockPIN:
            return "number"
        case .viewLAPSAccountPassword:
            return "person.badge.key"
        case .rotateLAPSPassword:
            return "arrow.triangle.2.circlepath"
        case .enableBluetooth:
            return "antenna.radiowaves.left.and.right"
        case .disableBluetooth:
            return "antenna.radiowaves.left.and.right.slash"
        case .enableLostMode:
            return "mappin.and.ellipse"
        case .disableLostMode:
            return "mappin.slash"
        case .playLostModeSound:
            return "speaker.wave.2.fill"
        case .requestDeviceLocation:
            return "location.viewfinder"
        case .clearRestrictionsPassword:
            return "hourglass.bottomhalf.filled"
        case .refreshCellularPlans:
            return "simcard"
        case .scheduleOSUpdate:
            return "arrow.up.circle.dotted"
        case .settingsSync:
            return "gearshape.2"
        case .enableWifi:
            return "wifi"
        case .disableWifi:
            return "wifi.slash"
        case .enableFileVault:
            return "lock.shield.fill"
        case .redeployManagementFramework:
            return "arrow.triangle.swap"
        case .viewJamfManagementAccountPassword:
            return "key.fill"
        }
    }

    /// Whether this action requires an explicit confirmation dialog before execution.
    /// Destructive/irreversible actions require confirmation; Clear Passcode is
    /// included because it removes device security and locks out end users.
    var requiresConfirmation: Bool {
        switch self {
        case .eraseDevice,
             .clearPasscode,
             .shutDownDevice,
             .sendDeviceLock,
             .logOutUser,
             .restartDevice:
            return true
        default:
            return false
        }
    }

    /// The title shown in the confirmation alert dialog.
    var confirmationTitle: String {
        switch self {
        case .eraseDevice:
            return "Erase Device?"
        case .clearPasscode:
            return "Clear Passcode?"
        case .shutDownDevice:
            return "Shut Down Device?"
        case .sendDeviceLock:
            return "Lock Device?"
        case .logOutUser:
            return "Log Out Current User?"
        case .restartDevice:
            return "Restart Device?"
        default:
            return title
        }
    }

    /// The message body shown in the confirmation alert dialog.
    var confirmationMessage: String {
        switch self {
        case .eraseDevice:
            return "This command is destructive and may not be reversible."
        case .clearPasscode:
            return "This removes the device passcode. The end user will be locked out of the device until a new passcode is set."
        case .shutDownDevice:
            return "This will queue a shut-down command. The end user loses any unsaved work and must power the device on again manually."
        case .sendDeviceLock:
            return "This will lock the device immediately. On macOS a random 6-digit PIN is generated and shown once here — the end user must enter that PIN at the firmware lock screen to unlock."
        case .logOutUser:
            return "This will queue a log-out command for the currently signed-in user. Unsaved work in their apps will be lost."
        case .restartDevice:
            return "This will queue an immediate restart. The end user loses any unsaved work."
        default:
            return subtitle
        }
    }
}

/// The result of executing a management action or application command.
///
/// Contains a human-readable title and detail message, plus an optional
/// sensitive value (e.g. a recovery key or password) that gets special
/// UI treatment with copy-to-clipboard functionality.
struct SupportActionResult: Sendable {
    /// A short label identifying the action that was performed.
    let title: String

    /// A descriptive message about the outcome.
    let detail: String

    /// An optional secret value (password, recovery key, PIN) to display securely.
    let sensitiveValue: String?

    // `nonisolated` is required under Swift 6 strict concurrency because this
    // struct is constructed from `actor SupportTechnicianAPIService` (off the
    // main actor). Without it, the explicit init picks up default actor
    // isolation from the enclosing module configuration and becomes callable
    // only from the main actor. The prior compiler-synthesized memberwise
    // init was nonisolated by default; reproducing that behavior here.
    nonisolated init(
        title: String,
        detail: String,
        sensitiveValue: String? = nil
    ) {
        self.title = title
        self.detail = detail
        self.sensitiveValue = sensitiveValue
    }
}

/// A secret credential surfaced to the technician for one-time display in a
/// modal popup with copy-to-clipboard (local admin / LAPS password, jssmanage
/// password, recovery-lock password, device-lock PIN, FileVault recovery key).
///
/// This type exists so the secret value travels only to the popup surface —
/// it is intentionally never persisted and never written into the sidebar's
/// result-summary frame. A fresh `id` per instance ensures SwiftUI's
/// `.sheet(item:)` re-presents the popup for each new credential, even when
/// the same value is fetched twice.
struct SupportCredentialDisplay: Identifiable, Sendable {
    let id = UUID()

    /// The action label shown as the popup title (e.g. "View Local Admin Password").
    let title: String

    /// The secret value to display and copy. Never logged, never stored.
    let value: String

    nonisolated init(title: String, value: String) {
        self.title = title
        self.value = value
    }
}

/// The non-secret summary of a server response, rendered in the sidebar's
/// scrollable "Server Response" frame. Deliberately carries only the result
/// title and human-readable detail — never `SupportActionResult.sensitiveValue`.
struct SupportResultSummary: Identifiable, Equatable, Sendable {
    let id = UUID()
    let title: String
    let detail: String

    nonisolated init(title: String, detail: String) {
        self.title = title
        self.detail = detail
    }

    /// Equality ignores the synthetic `id` so summaries compare on content —
    /// keeps unit tests and SwiftUI diffing keyed to what the technician sees.
    nonisolated static func == (lhs: SupportResultSummary, rhs: SupportResultSummary) -> Bool {
        lhs.title == rhs.title && lhs.detail == rhs.detail
    }
}

/// Pure mapping from a server `SupportActionResult` to its two UI surfaces:
/// the one-time credential popup and the persistent non-secret summary frame.
///
/// Extracted as a free function (no view-model or networking dependencies) so
/// the security-critical guarantee — the secret reaches the popup but never
/// the summary — is unit-testable in isolation.
enum SupportActionResultPresentation {
    /// - Returns: `credential` is non-nil only when the result carries a
    ///   non-empty secret; `summary` always carries the non-secret title +
    ///   detail and never contains the secret value.
    nonisolated static func make(
        from result: SupportActionResult
    ) -> (credential: SupportCredentialDisplay?, summary: SupportResultSummary) {
        let credential: SupportCredentialDisplay?
        if let value = result.sensitiveValue,
           value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            credential = SupportCredentialDisplay(title: result.title, value: value)
        } else {
            credential = nil
        }
        let summary = SupportResultSummary(title: result.title, detail: result.detail)
        return (credential, summary)
    }
}

/// Errors specific to the Support Technician module, providing user-facing
/// descriptions for each failure case encountered during search, detail
/// loading, and management action workflows.
enum SupportTechnicianError: LocalizedError {
    case invalidSearchQuery
    case missingManagementID
    case missingClientManagementID
    case missingSelection
    case unsupportedAction
    case noLAPSAccounts
    case unsupportedResponseShape
    case unsupportedSecretPayload
    case applicationCatalogUnavailable
    /// The application command the tech tapped can't be completed via
    /// Jamf's documented APIs from this app; the message explains why
    /// and — when applicable — includes the manual Jamf Pro URL to open.
    case applicationCommandRequiresManualStep(message: String)
    /// The deploy-package manifest for the selected application can't
    /// be constructed from the tenant's `/api/v1/packages` response.
    /// The message names the specific missing fields the admin must
    /// add on the Jamf Pro side (url / hash / bundleId / sizeInBytes /
    /// etc.). The raw response body is captured in the diagnostics log
    /// under category `application-command` for admin review.
    case applicationCommandRequiresSetup(message: String)
    /// The application command targets a flow that this tool hasn't
    /// wired up yet (e.g. mobile-device app installs via v1 InstallApplication
    /// MDM, or the uninstall-via-policy pipeline). Distinct from
    /// Jamf-API limits — it's an app-side gap.
    case applicationCommandNotYetSupported(message: String)

    /// A localized, user-facing description of the error.
    var errorDescription: String? {
        switch self {
        case .invalidSearchQuery:
            return "Enter a username or serial number before searching."
        case .missingManagementID:
            return "Selected device is missing a management identifier required for this action."
        case .missingClientManagementID:
            return "Selected computer is missing the client management identifier required for LAPS."
        case .missingSelection:
            return "Select a device from search results first."
        case .unsupportedAction:
            return "The selected action is not supported for this device type."
        case .noLAPSAccounts:
            return "No local admin password accounts were returned by Jamf Pro."
        case .unsupportedResponseShape:
            return "Jamf Pro returned an unexpected payload shape."
        case .unsupportedSecretPayload:
            return "Jamf Pro returned an unexpected secret payload."
        case .applicationCatalogUnavailable:
            return "No available application catalog was returned by Jamf Pro for this device."
        case .applicationCommandRequiresManualStep(let message):
            return message
        case .applicationCommandRequiresSetup(let message):
            return message
        case .applicationCommandNotYetSupported(let message):
            return message
        }
    }
}

// MARK: - Management action availability

/// User-facing availability state for a technician action before dispatch.
///
/// This is intentionally lightweight: Jamf privilege failures still come from
/// the API response and diagnostics path, while identifiers and device-type
/// blockers are detectable before the technician clicks.
nonisolated struct SupportActionAvailability: Sendable, Equatable {
    enum State: String, Sendable {
        case available
        case blocked
        case confirmationRequired
        case permissionSensitive
        case unsupported
    }

    let state: State
    let reason: String?

    var isAvailable: Bool {
        switch state {
        case .available, .confirmationRequired, .permissionSensitive:
            return true
        case .blocked, .unsupported:
            return false
        }
    }

    var helpText: String {
        switch state {
        case .available:
            return reason ?? "Available"
        case .blocked:
            return reason ?? "Blocked for this device"
        case .confirmationRequired:
            return reason ?? "Requires typed confirmation before execution"
        case .permissionSensitive:
            return reason ?? "Permission-sensitive action"
        case .unsupported:
            return reason ?? "Unsupported for this device type"
        }
    }

    static let available = SupportActionAvailability(state: .available, reason: "Available")

    static func blocked(_ reason: String) -> SupportActionAvailability {
        SupportActionAvailability(state: .blocked, reason: reason)
    }

    static func unsupported(_ reason: String) -> SupportActionAvailability {
        SupportActionAvailability(state: .unsupported, reason: reason)
    }

    static func confirmationRequired(_ reason: String) -> SupportActionAvailability {
        SupportActionAvailability(state: .confirmationRequired, reason: reason)
    }

    static func permissionSensitive(_ reason: String) -> SupportActionAvailability {
        SupportActionAvailability(state: .permissionSensitive, reason: reason)
    }
}

// MARK: - Category routing (Technician Module redesign)

/// Top-level categorization used by the redesigned Technician Module to
/// route inventory sections into the correct frame.
///
/// `defaultOrder` defines the on-screen ordering of frames; lower values
/// render first. The view is responsible for hiding categories that have no
/// content (except `.general`, which is always shown because the identity
/// rows and gauges live there).
nonisolated enum SupportDeviceCategory: String, CaseIterable, Identifiable, Sendable {
    case general
    case hardware
    case storage
    case os
    case security
    case network
    case extensionAttributes
    case profiles
    case groups
    case policies
    case applications
    case userAccounts
    case other

    var id: String { rawValue }

    /// Human-readable frame title.
    var displayName: String {
        switch self {
        case .general: return "General"
        case .hardware: return "Hardware"
        case .storage: return "Storage"
        case .os: return "Operating System"
        case .security: return "Security"
        case .network: return "Network"
        case .extensionAttributes: return "Extension Attributes"
        case .profiles: return "Profiles"
        case .groups: return "Groups"
        case .policies: return "Policies"
        case .applications: return "Applications"
        case .userAccounts: return "User Accounts"
        case .other: return "Other"
        }
    }

    /// SF Symbol shown next to the frame title.
    var iconSystemName: String {
        switch self {
        case .general: return "info.bubble"
        case .hardware: return "cpu"
        case .storage: return "internaldrive"
        case .os: return "macwindow"
        case .security: return "lock.shield"
        case .network: return "network"
        case .extensionAttributes: return "tag"
        case .profiles: return "doc.badge.gearshape"
        case .groups: return "person.3.fill"
        case .policies: return "list.bullet.rectangle.fill"
        case .applications: return "app.badge"
        case .userAccounts: return "person.crop.circle"
        case .other: return "ellipsis.rectangle"
        }
    }

    /// Render order in the scrollable list of frames.
    var defaultOrder: Int {
        switch self {
        case .general: return 0
        case .hardware: return 1
        case .storage: return 2
        case .os: return 3
        case .security: return 4
        case .network: return 5
        case .extensionAttributes: return 6
        case .profiles: return 7
        case .groups: return 8
        case .policies: return 9
        case .applications: return 10
        case .userAccounts: return 11
        case .other: return 12
        }
    }
}

/// Sections grouped by category, replacing the priority-sorted flat list.
nonisolated struct CategorizedDeviceDetail: Hashable, Sendable {
    /// Map of category to sections that belong in that category's frame.
    let sectionsByCategory: [SupportDeviceCategory: [SupportDetailSection]]

    static let empty = CategorizedDeviceDetail(sectionsByCategory: [:])

    /// Returns the sections routed to a given category, sorted by section title
    /// for a stable presentation order.
    func sections(for category: SupportDeviceCategory) -> [SupportDetailSection] {
        (sectionsByCategory[category] ?? []).sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    /// `true` when the categorizer ran and emitted at least one section.
    /// The view uses this to decide whether to fall back to the legacy
    /// flat-list rendering when categorization was not performed.
    var hasContent: Bool {
        sectionsByCategory.values.contains { $0.isEmpty == false }
    }
}

/// One entry from the tenant-wide Extension Attribute catalog —
/// fetched once and cached so the EA frame can render the full set
/// (with descriptions + data-type) even on devices whose payload
/// happens to omit specific EAs. Mirrors the Mobile Device Search
/// module's `MobileDeviceExtensionAttribute` shape.
nonisolated struct SupportExtensionAttributeDefinition: Identifiable, Hashable, Sendable {
    let attributeID: String
    let name: String
    let description: String?
    let dataType: String?
    let inputType: String?
    let popupChoices: [String]?
    let category: String?

    var id: String { attributeID }
}

/// A single Jamf extension attribute as a typed name/value pair.
///
/// Replaces the previous generic array-flattening that produced unreadable
/// `"item 1: <dictionary>"` rows. The Technician view's Extension Attributes
/// frame iterates over `[SupportExtensionAttribute]` and renders one row per
/// attribute with the actual value visible.
nonisolated struct SupportExtensionAttribute: Identifiable, Hashable, Sendable {
    let attributeID: String
    let name: String
    let value: String
    let type: String?
    let category: String?

    var id: String { attributeID.isEmpty ? name : attributeID }
}

/// Hardware specs surfaced in the General frame and consumed by the storage
/// Metal gauge plus the CPU and RAM spec cards.
///
/// Each field is optional because Jamf inventory does not guarantee every
/// hardware key is populated for every device type — mobile devices in
/// particular omit several Mac-only fields. For mobile devices the CPU /
/// chip / core counts / RAM are *derived* from `SupportTechnicianDeviceSpecCatalog`
/// lookups against `modelIdentifier` rather than read directly from the
/// payload (Jamf doesn't expose them for iOS/iPadOS).
nonisolated struct SupportHardwareSpecs: Hashable, Sendable {
    let modelName: String?
    let modelIdentifier: String?
    let modelNumber: String?
    let cpuType: String?
    let chipName: String?
    let coreCount: Int?
    let gpuCoreCount: Int?
    let gpuCoreDescription: String?
    let neuralCoreCount: Int?
    let cpuSpeedMhz: Int?
    let cpuFrequencyDescription: String?
    let totalRamMB: Int?
    let memoryDescription: String?
    let storageTotalMB: Int?
    let storageAvailableMB: Int?
    let usedSpacePercentage: Int?
    let batteryLevel: Int?
    let batteryHealth: String?
    let bluetoothMacAddress: String?
    let wifiMacAddress: String?

    /// 0...1 fraction of storage currently used, computed from the most
    /// reliable source available: `usedSpacePercentage` if Jamf reports it
    /// directly, otherwise `(total - available) / total`. Returns `nil`
    /// when neither path yields a usable value.
    var storageUsedFraction: Double? {
        if let percent = usedSpacePercentage, percent >= 0 {
            return min(1.0, Double(percent) / 100.0)
        }
        guard let total = storageTotalMB, total > 0,
              let avail = storageAvailableMB
        else {
            return nil
        }
        let used = max(0, total - avail)
        return min(1.0, Double(used) / Double(total))
    }

    /// Multi-line summary for the CPU spec card. `nil` when no CPU fields
    /// are populated for this device.
    var cpuSummary: String? {
        var parts: [String] = []
        if let chipName, chipName.isEmpty == false {
            parts.append(chipName)
        } else if let cpuType, cpuType.isEmpty == false {
            parts.append(cpuType)
        }
        if let coreCount, coreCount > 0 {
            parts.append("\(coreCount) CPU core\(coreCount == 1 ? "" : "s")")
        }
        if let cpuSpeedMhz, cpuSpeedMhz > 0 {
            if cpuSpeedMhz >= 1000 {
                parts.append(String(format: "%.2f GHz", Double(cpuSpeedMhz) / 1000.0))
            } else {
                parts.append("\(cpuSpeedMhz) MHz")
            }
        } else if let cpuFrequencyDescription, cpuFrequencyDescription.isEmpty == false {
            parts.append(cpuFrequencyDescription)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// GPU + Neural Engine line used as a secondary detail on the CPU spec
    /// card for mobile devices where Apple publishes those counts.
    var gpuSummary: String? {
        var parts: [String] = []
        if let gpu = gpuCoreCount, gpu > 0 {
            parts.append("\(gpu) GPU core\(gpu == 1 ? "" : "s")")
        } else if let gpuCoreDescription, gpuCoreDescription.isEmpty == false {
            parts.append(gpuCoreDescription)
        }
        if let neural = neuralCoreCount, neural > 0 {
            parts.append("\(neural)-core Neural Engine")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Concise total RAM string for the RAM spec card (e.g. "16 GB").
    var ramSummary: String? {
        guard let totalRamMB, totalRamMB > 0 else {
            return nil
        }
        if totalRamMB >= 1024 {
            let gb = Double(totalRamMB) / 1024.0
            if gb.truncatingRemainder(dividingBy: 1) == 0 {
                return String(format: "%.0f GB", gb)
            }
            return String(format: "%.1f GB", gb)
        }
        return "\(totalRamMB) MB"
    }

    /// "X of Y used" string surfaced alongside the storage gauge.
    var storageSummary: String? {
        guard let total = storageTotalMB, total > 0 else {
            return nil
        }
        let totalText = humanReadable(megabytes: total)
        if let avail = storageAvailableMB {
            let used = max(0, total - avail)
            return "\(humanReadable(megabytes: used)) of \(totalText) used"
        }
        return totalText
    }

    /// Concise battery summary used on the General/Hardware frame.
    var batterySummary: String? {
        if let level = batteryLevel, level >= 0 {
            if let health = batteryHealth, health.isEmpty == false {
                return "\(level)% · \(health)"
            }
            return "\(level)%"
        }
        if let health = batteryHealth, health.isEmpty == false {
            return health
        }
        return nil
    }

    /// `true` when none of the visible fields have a usable value.
    var isEmpty: Bool {
        cpuSummary == nil
            && ramSummary == nil
            && storageSummary == nil
            && modelName == nil
            && batterySummary == nil
    }

    private func humanReadable(megabytes: Int) -> String {
        if megabytes >= 1_048_576 {
            return String(format: "%.2f TB", Double(megabytes) / 1_048_576.0)
        }
        if megabytes >= 1024 {
            return String(format: "%.0f GB", Double(megabytes) / 1024.0)
        }
        return "\(megabytes) MB"
    }
}

/// OS-specific fields surfaced in the OS frame. Distinct from
/// `SupportHardwareSpecs` so the OS frame can render real data even when
/// hardware extraction returns nil.
nonisolated struct SupportOSInfo: Hashable, Sendable {
    let version: String?
    let build: String?
    let supplementalBuildVersion: String?
    let rapidSecurityResponseVersion: String?
    let osName: String?

    var isEmpty: Bool {
        version == nil && build == nil && supplementalBuildVersion == nil
            && rapidSecurityResponseVersion == nil && osName == nil
    }
}

/// Security posture surfaced in the Security frame.
nonisolated struct SupportSecurityProfile: Hashable, Sendable {
    let isEncrypted: Bool?
    let blockEncryptionCapable: Bool?
    let fileEncryptionCapable: Bool?
    let hardwareEncryptionSupported: Int?
    let dataProtected: Bool?
    let activationLockEnabled: Bool?
    let lostModeEnabled: Bool?
    let passcodePresent: Bool?
    let passcodeCompliant: Bool?
    let passcodeCompliantWithProfile: Bool?
    let supervised: Bool?
    let jailbroken: Bool?
    let fileVaultStatus: String?
    let recoveryKeyStatus: String?
    let recoveryLockEnabled: Bool?
    let firewallEnabled: Bool?
    let gatekeeperStatus: String?
    let sipStatus: String?
    let xprotectVersion: String?
    let secureBootLevel: String?
    let externalBootLevel: String?
    let autoLoginDisabled: Bool?
    let remoteDesktopEnabled: Bool?
    let bootstrapTokenAllowed: Bool?
    let bootstrapTokenEscrowedStatus: String?
    let attestationStatus: String?
    let lastSuccessfulAttestation: String?

    var isEmpty: Bool {
        isEncrypted == nil
            && blockEncryptionCapable == nil
            && activationLockEnabled == nil
            && lostModeEnabled == nil
            && passcodePresent == nil
            && passcodeCompliant == nil
            && supervised == nil
            && fileVaultStatus == nil
            && firewallEnabled == nil
            && gatekeeperStatus == nil
            && secureBootLevel == nil
            && autoLoginDisabled == nil
            && remoteDesktopEnabled == nil
    }
}

/// A single group membership entry surfaced in the Group frame.
nonisolated struct SupportDeviceGroup: Identifiable, Hashable, Sendable {
    let groupID: String
    let name: String
    let isSmart: Bool?

    var id: String { groupID.isEmpty ? name : groupID }
}

/// A single configuration profile assigned to the device.
nonisolated struct SupportDeviceProfile: Identifiable, Hashable, Sendable {
    let profileID: String
    let name: String
    let identifier: String?
    let scope: String?

    var id: String { profileID.isEmpty ? name : profileID }
}

/// A single tenant-wide policy entry surfaced in the Policy frame.
nonisolated struct SupportPolicy: Identifiable, Hashable, Sendable {
    let policyID: String
    let name: String
    let category: String?
    let enabled: Bool?
    let frequency: String?

    var id: String { policyID }
}

/// A single local user account on a Mac, surfaced in the User Accounts
/// frame. Sourced from the v2 inventory `localUserAccounts[]` array.
nonisolated struct SupportLocalUser: Identifiable, Hashable, Sendable {
    let uid: String?
    let username: String
    let fullName: String?
    let isAdmin: Bool?
    let fileVault2Enabled: Bool?
    let userAccountType: String?
    let homeDirectory: String?
    let homeDirectorySizeMb: Int?
    let azureActiveDirectoryId: String?

    var id: String { uid ?? username }
}

/// Network identifiers surfaced in the Network frame.
nonisolated struct SupportNetworkInfo: Hashable, Sendable {
    let ipAddress: String?
    let lastReportedIp: String?
    let lastReportedIpV4: String?
    let lastReportedIpV6: String?
    let connectionActive: Bool?
    let wifiMacAddress: String?
    let wifiEnabled: Bool?
    let ssid: String?
    let bluetoothMacAddress: String?
    let bluetoothEnabled: Bool?
    let hostname: String?
    let networkAdapterType: String?
    let alternateMacAddress: String?
    let alternateNetworkAdapterType: String?
    let nicSpeed: String?
    let bleCapable: Bool?
    let cellularCarrier: String?
    let cellularTechnology: String?
    let imei: String?
    let imei2: String?
    let meid: String?
    let iccid: String?
    let eid: String?
    let phoneNumber: String?
    let dataRoamingEnabled: Bool?
    let voiceRoamingEnabled: Bool?
    let roaming: Bool?
    let personalHotspotEnabled: Bool?

    var isEmpty: Bool {
        ipAddress == nil && lastReportedIp == nil && wifiMacAddress == nil
            && bluetoothMacAddress == nil && hostname == nil && cellularCarrier == nil
            && imei == nil && imei2 == nil && meid == nil && iccid == nil && eid == nil
            && networkAdapterType == nil && alternateNetworkAdapterType == nil
            && connectionActive == nil && wifiEnabled == nil && bluetoothEnabled == nil
            && ssid == nil
    }
}

// MARK: - Command lifecycle (Technician Module redesign)

/// The lifecycle state of an MDM command issued through the Technician
/// Module. The new Metal-rendered `CommandStatusIndicatorView` reads from
/// this state machine to animate the command's journey from issuance
/// through verification to completion or failure.
///
/// `sending` precedes the network call so the user sees motion the instant
/// they confirm. `queued` flips on a 2xx response from Jamf Pro. `verifying`
/// is entered for actions where ground-truth completion is reflected in
/// inventory (Restart, Shutdown, Erase, ClearPasscode, LogOut) — the
/// view-model polls `refreshSelectedDeviceDetail()` until `lastContactTime`
/// advances past the queue timestamp, then flips to `succeeded`. Terminal
/// states auto-dismiss to `idle` after a delay.
enum CommandLifecyclePhase: Equatable, Sendable {
    case idle
    case sending(action: SupportManagementAction, startedAt: Date)
    case queued(action: SupportManagementAction, queuedAt: Date)
    case verifying(action: SupportManagementAction, startedAt: Date, attempt: Int)
    case succeeded(action: SupportManagementAction, completedAt: Date)
    case failed(action: SupportManagementAction, errorDescription: String)
    case timedOut(action: SupportManagementAction)

    /// `true` for `.succeeded`, `.failed`, and `.timedOut`.
    var isTerminal: Bool {
        switch self {
        case .succeeded, .failed, .timedOut:
            return true
        default:
            return false
        }
    }

    /// `true` when the command is between issuance and a terminal state.
    var isInProgress: Bool {
        switch self {
        case .sending, .queued, .verifying:
            return true
        default:
            return false
        }
    }

    /// The action this lifecycle entry refers to, or `nil` for `.idle`.
    var action: SupportManagementAction? {
        switch self {
        case .idle:
            return nil
        case let .sending(action, _),
             let .queued(action, _),
             let .verifying(action, _, _),
             let .succeeded(action, _),
             let .failed(action, _),
             let .timedOut(action):
            return action
        }
    }

    /// 0...1 progress fraction used by the Metal shader's pulse position.
    /// `idle` returns 0; `succeeded` / `failed` / `timedOut` return 1.
    var progress: Double {
        switch self {
        case .idle:
            return 0.0
        case .sending:
            return 0.25
        case .queued:
            return 0.55
        case .verifying:
            return 0.75
        case .succeeded, .failed, .timedOut:
            return 1.0
        }
    }
}

// MARK: - Confirmation strength (Technician Module redesign)

/// Severity tier governing the confirmation UI shown before an MDM command
/// executes. `.none` means the command runs immediately; `.alertOnly` shows
/// a standard `.alert()`; `.typed` opens `SupportTypedConfirmationSheet`
/// requiring the technician to type the action's `requiredTypedPhrase`
/// before the Confirm button enables.
nonisolated enum ConfirmationStrength: Sendable {
    case none
    case alertOnly
    case typed
}

// MARK: - SupportManagementAction redesign extensions

extension SupportManagementAction {
    /// Resolves whether this action can be dispatched for the current device
    /// before the technician clicks it. Runtime privilege denials still flow
    /// through diagnostics because Jamf only confirms those on request.
    nonisolated func availability(for detail: SupportDeviceDetail) -> SupportActionAvailability {
        let assetType = detail.summary.assetType
        guard supports(assetType: assetType) else {
            return .unsupported("\(title) is not supported for \(assetType.title.lowercased()) records.")
        }

        guard detail.summary.inventoryID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            return .blocked("\(title) requires a Jamf inventory ID.")
        }

        if requiresManagementID(for: assetType),
           hasManagementID(in: detail) == false
        {
            return .blocked("\(title) requires a Jamf management ID. Refresh search/detail data or re-enroll the device.")
        }

        if requiresClientManagementID,
           hasClientManagementID(in: detail) == false
        {
            return .blocked("\(title) requires a Jamf client management ID for LAPS.")
        }

        if confirmationStrength == .typed {
            return .confirmationRequired("Requires typed confirmation before Jamf receives the command.")
        }

        if isCredentialRetrieval {
            return .permissionSensitive("Retrieves a protected value and requires the matching Jamf API privilege.")
        }

        return .available
    }

    /// The category frame whose footer hosts this action's button. Universal
    /// inventory commands (`refreshInventory`, `blankPush`, `discoverApplications`)
    /// also surface in the top toolbar — `isUniversalToolbarAction` controls that.
    nonisolated var primaryCategory: SupportDeviceCategory {
        switch self {
        case .refreshInventory, .blankPush, .discoverApplications, .settingsSync:
            return .general
        case .restartDevice, .shutDownDevice:
            // 3.22.9: Restart + Shutdown moved to the General frame so
            // technicians don't have to scroll past Hardware (which now
            // lives inside General as a sub-section anyway).
            return .general
        case .scheduleOSUpdate:
            return .os
        case .logOutUser,
             .clearPasscode,
             .clearRestrictionsPassword,
             .viewDeviceLockPIN,
             .viewLAPSAccountPassword,
             .viewJamfManagementAccountPassword,
             .rotateLAPSPassword:
            // 3.22.9: Account-related actions (logout, passcodes, LAPS,
            // device-lock PIN, jssmanage password) attached to the User
            // Accounts frame footer per the redesign.
            return .userAccounts
        case .sendDeviceLock,
             .eraseDevice,
             .viewFileVaultPersonalRecoveryKey,
             .viewRecoveryLockPassword,
             .enableLostMode,
             .disableLostMode,
             .playLostModeSound,
             .requestDeviceLocation,
             .enableFileVault,
             .redeployManagementFramework:
            return .security
        case .enableBluetooth,
             .disableBluetooth,
             .enableWifi,
             .disableWifi,
             .refreshCellularPlans:
            return .network
        }
    }

    /// Universal commands hosted in the top toolbar regardless of which
    /// frame the technician is scrolled to.
    nonisolated var isUniversalToolbarAction: Bool {
        switch self {
        case .refreshInventory, .blankPush, .discoverApplications:
            return true
        default:
            return false
        }
    }

    /// Confirmation tier. Destructive actions require typed "confirm" per
    /// the redesign spec. Credential-view actions skip confirmation but the
    /// underlying secret display has its own copy-to-clipboard affordance.
    nonisolated var confirmationStrength: ConfirmationStrength {
        switch self {
        case .refreshInventory,
             .blankPush,
             .discoverApplications,
             .viewFileVaultPersonalRecoveryKey,
             .viewRecoveryLockPassword,
             .viewDeviceLockPIN,
             .viewLAPSAccountPassword,
             .viewJamfManagementAccountPassword,
             .playLostModeSound,
             .requestDeviceLocation,
             .refreshCellularPlans,
             .settingsSync:
            return .none
        case .restartDevice,
             .shutDownDevice,
             .sendDeviceLock,
             .logOutUser,
             .clearPasscode,
             .eraseDevice,
             .rotateLAPSPassword,
             .enableBluetooth,
             .disableBluetooth,
             .enableWifi,
             .disableWifi,
             .enableLostMode,
             .disableLostMode,
             .clearRestrictionsPassword,
             .scheduleOSUpdate,
             .enableFileVault,
             .redeployManagementFramework:
            return .typed
        }
    }

    /// The exact phrase the technician must type into
    /// `SupportTypedConfirmationSheet`. The user requested a uniform
    /// lowercase "confirm" across every destructive action.
    nonisolated var requiredTypedPhrase: String? {
        confirmationStrength == .typed ? "confirm" : nil
    }

    /// `true` for actions whose ground-truth completion is reflected in
    /// device inventory state. The view model polls inventory after the
    /// command queues and flips the lifecycle to `.succeeded` when the
    /// expected change is observed.
    nonisolated var requiresInventoryVerification: Bool {
        switch self {
        case .restartDevice,
             .shutDownDevice,
             .eraseDevice,
             .clearPasscode,
             .logOutUser,
             .enableBluetooth,
             .disableBluetooth,
             .enableLostMode,
             .disableLostMode:
            return true
        default:
            return false
        }
    }

    private nonisolated func supports(assetType: SupportAssetType) -> Bool {
        switch self {
        case .logOutUser,
             .viewFileVaultPersonalRecoveryKey,
             .viewRecoveryLockPassword,
             .viewDeviceLockPIN,
             .viewLAPSAccountPassword,
             .rotateLAPSPassword,
             .enableFileVault,
             .redeployManagementFramework,
             .viewJamfManagementAccountPassword:
            return assetType == .computer
        case .clearPasscode,
             .enableLostMode,
             .disableLostMode,
             .playLostModeSound,
             .requestDeviceLocation,
             .clearRestrictionsPassword,
             .refreshCellularPlans:
            return assetType == .mobileDevice
        default:
            return true
        }
    }

    private nonisolated func requiresManagementID(for assetType: SupportAssetType) -> Bool {
        switch self {
        case .blankPush,
             .restartDevice,
             .shutDownDevice,
             .sendDeviceLock,
             .logOutUser,
             .clearPasscode,
             .enableLostMode,
             .disableLostMode,
             .playLostModeSound,
             .requestDeviceLocation,
             .clearRestrictionsPassword,
             .refreshCellularPlans,
             .scheduleOSUpdate,
             .settingsSync:
            return true
        case .discoverApplications,
             .eraseDevice:
            return assetType == .mobileDevice
        default:
            return false
        }
    }

    private nonisolated var requiresClientManagementID: Bool {
        switch self {
        case .viewLAPSAccountPassword,
             .rotateLAPSPassword,
             .viewJamfManagementAccountPassword:
            return true
        default:
            return false
        }
    }

    private nonisolated var isCredentialRetrieval: Bool {
        switch self {
        case .viewFileVaultPersonalRecoveryKey,
             .viewRecoveryLockPassword,
             .viewDeviceLockPIN,
             .viewLAPSAccountPassword,
             .viewJamfManagementAccountPassword:
            return true
        default:
            return false
        }
    }

    private nonisolated func hasManagementID(in detail: SupportDeviceDetail) -> Bool {
        if let managementID = detail.summary.managementID,
           managementID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        {
            return true
        }
        if let clientManagementID = detail.summary.clientManagementID,
           clientManagementID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        {
            return true
        }
        return false
    }

    private nonisolated func hasClientManagementID(in detail: SupportDeviceDetail) -> Bool {
        if let clientManagementID = detail.summary.clientManagementID,
           clientManagementID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        {
            return true
        }
        if let managementID = detail.summary.managementID,
           managementID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        {
            return true
        }
        return false
    }
}

// MARK: - MDM command history record

/// A single MDM command history entry surfaced in the Command History frame.
///
/// Constructed from either `GET /api/v2/mdm/commands?filter=clientManagementId==<uuid>`
/// (modern, computer + mobile) or the Classic
/// `GET /JSSResource/computerhistory/id/{id}` / `mobiledevicehistory/id/{id}`
/// endpoints (fallback when the v2 endpoint returns 403 on a restricted role).
/// `status` is the Jamf status string. The v2 endpoint commonly returns
/// `Pending`, `Acknowledged`, `Error`, `NotNow`; the Classic fallback
/// emits `Pending`, `Completed`, `Failed`; some tenants append a
/// parenthesized retry count or a hyphenated reason (`Acknowledged
/// (1 retries)`, `Error - device offline`), which is why bucketing
/// normalizes on the first keyword token rather than the full string.
nonisolated struct SupportMDMCommandRecord: Identifiable, Hashable, Sendable {
    let uuid: String
    let commandType: String
    let status: String
    let dateSent: String?
    let dateCompleted: String?
    let errorReasons: [String]
    let source: Source

    enum Source: String, Sendable {
        case modern   // /api/v2/mdm/commands
        case classic  // JSSResource history
    }

    var id: String { uuid.isEmpty ? "\(commandType):\(dateSent ?? "")" : uuid }

    /// Convenience bucket used by the Command History frame to count
    /// pending / completed / failed without re-string-matching at every
    /// rendering pass.
    ///
    /// Matching takes only the first word so verbose Jamf statuses like
    /// "Acknowledged (1 retries)" or "Error - device offline" still
    /// land in the right bucket instead of falling through to `.other`,
    /// which is what made the colored bucket boxes read zero even when
    /// the records list was populated.
    var bucket: Bucket {
        let trimmed = status.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        // NotNow variants first — Jamf serializes this as "NotNow",
        // "Not Now", or "NOT_NOW" depending on endpoint/version. The
        // space-separated form would otherwise split into "not"/"now"
        // and miss the keyword match below.
        if lower.hasPrefix("notnow") || lower.hasPrefix("not_now") || lower.hasPrefix("not now") {
            return .notNow
        }

        let firstWord = lower
            .split(whereSeparator: { ch in
                ch.isWhitespace || ch == "-" || ch == "(" || ch == ":" || ch == ","
            })
            .first
            .map(String.init) ?? lower

        switch firstWord {
        case "pending", "queued", "scheduled", "sent", "issued", "sending", "idle", "active":
            return .pending
        case "acknowledged", "completed", "succeeded", "ack":
            return .completed
        case "error", "failed", "expired", "cancelled", "canceled":
            return .failed
        default:
            return .other
        }
    }

    enum Bucket: String, Sendable {
        case pending
        case completed
        case failed
        case notNow
        case other

        var displayName: String {
            switch self {
            case .pending:   return "Pending"
            case .completed: return "Completed"
            case .failed:    return "Failed"
            case .notNow:    return "NotNow"
            case .other:     return "Other"
            }
        }
    }
}

/// Verbose error payload surfaced as an `.alert` popup when an MDM
/// command fails. Built by the view model from the API error so the
/// technician sees the action they tried, what specifically failed, the
/// suggested next step (privilege name when known), and the raw Jamf
/// response body for advanced debugging.
nonisolated struct SupportActionFailure: Identifiable, Hashable, Sendable {
    let id: UUID
    let actionTitle: String
    let summary: String
    let suggestion: String?
    let likelyPrivilege: String?
    let rawDetail: String?
    let isPrivilegeDenial: Bool

    /// Composed alert message body — title is supplied by the view.
    ///
    /// Strict UX policy: only graceful, action-oriented text reaches
    /// the user. Raw Jamf response bodies, error JSON dumps, stack
    /// frames, and other technical detail are not part of this string
    /// — they live exclusively in the framework's diagnostics export
    /// (`reportError` writes them to the persistent log; the operator
    /// retrieves them via Diagnostics → Export when needed).
    ///
    /// Prior versions of this property concatenated `rawDetail` under
    /// a "Raw Jamf response (first 400 chars):" header. That violated
    /// the project's "graceful messages only" policy by surfacing
    /// internal API error text inside the action popup. The
    /// `rawDetail` field is still carried on the struct so future
    /// surfaces (e.g. a "Show technical detail" disclosure inside a
    /// dedicated debug sheet) can opt in; the default alert body
    /// stays clean.
    var alertBody: String {
        var lines: [String] = [summary]
        if let likelyPrivilege {
            lines.append("\nLikely missing privilege:\n  • \(likelyPrivilege)")
        }
        if let suggestion {
            lines.append("\nWhat to do:\n\(suggestion)")
        }
        return lines.joined(separator: "\n")
    }

    init(
        actionTitle: String,
        summary: String,
        suggestion: String? = nil,
        likelyPrivilege: String? = nil,
        rawDetail: String? = nil,
        isPrivilegeDenial: Bool = false
    ) {
        self.id = UUID()
        self.actionTitle = actionTitle
        self.summary = summary
        self.suggestion = suggestion
        self.likelyPrivilege = likelyPrivilege
        self.rawDetail = rawDetail
        self.isPrivilegeDenial = isPrivilegeDenial
    }
}

/// Container holding the most recent command history fetch — usually 50
/// records — plus a `fetchedAt` stamp the view uses to render a "Refreshed
/// N seconds ago" caption.
nonisolated struct SupportMDMCommandHistory: Hashable, Sendable {
    let records: [SupportMDMCommandRecord]
    let fetchedAt: Date
    let source: SupportMDMCommandRecord.Source

    static let empty = SupportMDMCommandHistory(
        records: [],
        fetchedAt: Date(timeIntervalSince1970: 0),
        source: .modern
    )

    /// Returns the count of records in a given bucket.
    func count(in bucket: SupportMDMCommandRecord.Bucket) -> Int {
        records.filter { $0.bucket == bucket }.count
    }
}

//endofline
