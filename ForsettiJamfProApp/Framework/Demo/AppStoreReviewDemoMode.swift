import Combine
import Foundation

/// Thread-safe persistence and messaging for the App Store Review demo runtime.
///
/// This mode exists so Apple App Review can exercise Mac and iOS builds without a
/// live Jamf Pro tenant. When enabled, all Jamf networking is served from local
/// fixtures; no external host is contacted and no production data can change.
enum AppStoreReviewDemoMode: Sendable {
    nonisolated static let storageKey = "com.forsetti.jamfpro.appStoreReviewDemo.enabled"

    /// Banner shown while demo mode is active.
    nonisolated static let ribbonMessage =
        "APP STORE DEMO — SAMPLE DATA ONLY — NO LIVE JAMF PRO CONNECTION"

    /// Short safety copy for settings and credentials screens.
    nonisolated static let safetyMessage =
        "Sample data only. No live Jamf Pro server is contacted and no production data can change."

    /// Suggested text for App Store Connect Review Notes.
    nonisolated static let appReviewNotes =
        """
        App Store Review Demo Mode

        No Jamf Pro server, API client, username, or password is required.

        On first launch:
        1. Open Settings (gear) from the Command Center, or open Jamf Credentials.
        2. Tap or click “Explore App Store Demo”.
        3. An orange demo banner appears. All modules use built-in sample data.

        Suggested paths:
        • Computer Search — search “MacBook” or leave blank and run Search
        • Mobile Device Search — search “iPad” or leave blank and run Search
        • Support Technician — search field is pre-filled with C02DEMO0001; run Search,
          open Reviewer MacBook Pro, browse Hardware / Security / Applications /
          Command History, then run Refresh Inventory or Blank Push (simulated only).
          Mobile serial for a second pass: F9FDEMO0001.
        • Prestage Director, Reports, and Permissions Matrix — open and browse

        Exit demo: Settings → App Store Demo Mode → Exit Demo Mode
        (or the same control on the credentials screen).

        Live credentials remain optional and are never required for review.
        """

    /// Stable fake server URL used only for UI labels while demo is on.
    nonisolated static let demoServerURLString = "https://app-store-demo.forsetti.local"

    /// Support Technician search field prefill for App Review (Reviewer MacBook Pro).
    nonisolated static let supportTechnicianPrefillQuery = "C02DEMO0001"

    private static let lock = NSLock()

    /// Whether App Store Review demo mode is currently enabled.
    nonisolated static var isEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return UserDefaults.standard.bool(forKey: storageKey)
    }

    /// Enables or disables demo mode. Does not touch Keychain credentials.
    nonisolated static func setEnabled(_ enabled: Bool) {
        lock.lock()
        defer { lock.unlock() }
        UserDefaults.standard.set(enabled, forKey: storageKey)
    }
}

/// Main-actor observable façade so SwiftUI can react to demo enable/disable.
@MainActor
final class AppStoreReviewDemoController: ObservableObject {
    static let shared = AppStoreReviewDemoController()

    @Published private(set) var isEnabled: Bool

    private init() {
        isEnabled = AppStoreReviewDemoMode.isEnabled
    }

    /// Turns on demo mode for App Review. Real Keychain credentials are left intact
    /// but unused until demo is exited.
    func enable() {
        AppStoreReviewDemoMode.setEnabled(true)
        isEnabled = true
    }

    /// Returns the app to live Jamf Pro mode. Existing saved credentials (if any)
    /// become active again; if none are saved, live modules stay blocked until setup.
    func disable() {
        AppStoreReviewDemoMode.setEnabled(false)
        isEnabled = false
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            enable()
        } else {
            disable()
        }
    }
}

/// Shared readiness check: live credentials **or** App Store demo mode.
@MainActor
enum JamfSessionAvailability {
    static func isAvailable(credentialsStore: JamfCredentialsStore) -> Bool {
        credentialsStore.hasStoredCredentials || AppStoreReviewDemoController.shared.isEnabled
    }
}
