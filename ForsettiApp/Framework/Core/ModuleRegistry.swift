import Foundation
import Combine

/// A centralized, observable registry of all available dashboard modules.
///
/// `ModuleRegistry` ensures every registered module has a unique `id` and keeps
/// the module list sorted alphabetically by title. Because it is `@MainActor`
/// and `ObservableObject`, SwiftUI views that observe it will automatically
/// refresh when modules are added or replaced.
@MainActor
final class ModuleRegistry: ObservableObject {

    /// The current list of registered modules, sorted alphabetically by title.
    /// Publishes changes to any observing SwiftUI views.
    @Published private(set) var modules: [any JamfModule] = []

    /// Replaces the entire module list with the provided array, de-duplicating
    /// by `id` (first occurrence wins) and sorting alphabetically by title.
    ///
    /// - Parameter modules: The complete set of modules to register.
    func setModules(_ modules: [any JamfModule]) {
        var uniqueModules: [any JamfModule] = []

        for module in modules {
            // Skip any module whose id was already seen earlier in the array
            guard uniqueModules.contains(where: { $0.id == module.id }) == false else {
                continue
            }
            uniqueModules.append(module)
        }

        self.modules = uniqueModules.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    /// Appends a single module to the registry if no module with the same `id`
    /// is already registered, then re-sorts the list.
    ///
    /// - Parameter module: The module to register.
    func register(_ module: any JamfModule) {
        // Prevent duplicate registrations
        guard modules.contains(where: { $0.id == module.id }) == false else {
            return
        }

        modules.append(module)
        modules.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// Looks up a registered module by its unique identifier.
    ///
    /// - Parameter id: The module identifier to search for.
    /// - Returns: The matching `JamfModule`, or `nil` if not found.
    func module(withID id: String) -> (any JamfModule)? {
        modules.first(where: { $0.id == id })
    }
}

//endofline
