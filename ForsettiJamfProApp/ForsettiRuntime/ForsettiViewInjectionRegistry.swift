import SwiftUI

@MainActor
final class ForsettiViewInjectionRegistry {
    typealias Factory = @MainActor () -> AnyView

    private var factories: [String: Factory] = [:]

    func register<Content: View>(viewID: String, factory: @escaping @MainActor () -> Content) {
        factories[viewID] = { AnyView(factory()) }
    }

    func view(for viewID: String) -> AnyView? {
        factories[viewID]?()
    }

    var registeredViewIDs: [String] {
        factories.keys.sorted()
    }
}
