import SwiftUI

/// This is the executable entry point for the native SwiftUI application.
/// The `@main` attribute below tells Swift to start the process here, build
/// the app's root scene, create the shared framework container once, and pass
/// that container into the dashboard so each module uses the same credential,
/// networking, diagnostics, and module-registry services.
///
/// Keep ownership and launch-time wiring in this file intentionally small:
/// feature behavior belongs inside the individual modules, while cross-module
/// services belong in `ForsettiFrameworkContainer`.
/// The main entry point for the Forsetti application.
///
/// This struct conforms to the `App` protocol and serves as the root of the SwiftUI
/// application lifecycle. It creates and owns the `ForsettiFrameworkContainer` as a
/// `@StateObject`, ensuring the framework services persist across view updates.
/// The container is injected into `DashboardView` where it powers all module
/// and framework interactions.
@main
struct ForsettiApp: App {

    /// The central framework container that owns all shared services (API gateway,
    /// credentials store, diagnostics, module registry). Created once at app launch
    /// and retained for the lifetime of the application.
    @StateObject private var container = ForsettiFrameworkContainer()

    var body: some Scene {
        WindowGroup {
            // Root view — renders the module dashboard grid and injects
            // the framework container for dependency access throughout the view hierarchy.
            DashboardView(container: container)
                .tint(ForsettiTheme.accent)             // Apply Forsetti brand tint globally
                .forsettiRoundedTypography()             // Use rounded system font design
                .forsettiAppBackground()                 // Apply branded gradient backdrop
                .preferredColorScheme(.dark)             // Use the fixed retail dark theme
#if os(macOS)
                .frame(minWidth: 860, minHeight: 620) // Support compact Mac workspaces with app-level scrolling
#endif
        }
#if os(macOS)
        .defaultSize(width: 1360, height: 860) // Default Mac window dimensions
#endif
    }
}

//endofline
