import SwiftUI

@main
struct ForsettiApp: App {
    @StateObject private var bootstrap = ForsettiRuntimeBootstrap()

    var body: some Scene {
        WindowGroup {
            ForsettiProductionRootView(bootstrap: bootstrap)
                .task {
                    await bootstrap.bootForProduction()
                }
                .tint(ForsettiTheme.accent)
                .forsettiRoundedTypography()
                .forsettiAppBackground()
                .preferredColorScheme(.dark)
#if os(macOS)
                .frame(minWidth: 860, minHeight: 620)
#endif
        }
#if os(macOS)
        .defaultSize(width: 1360, height: 860)
#endif
    }
}

@MainActor
struct ForsettiProductionRootView: View {
    @ObservedObject var bootstrap: ForsettiRuntimeBootstrap

    var body: some View {
        switch bootstrap.bootState {
        case .notStarted, .booting:
            ForsettiBootProgressView()
        case .ready:
            DashboardView(
                container: bootstrap.appServices.dashboardContainer
            )
        case let .failed(error):
            ForsettiBootFailureView(error: error) {
                Task {
                    await bootstrap.bootForProduction()
                }
            }
        }
    }
}

private struct ForsettiBootProgressView: View {
    var body: some View {
        VStack(spacing: ForsettiTheme.Spacing.item) {
            ProgressView()
                .controlSize(.large)
            Text("Starting Forsetti")
                .font(.headline)
            Text("Preparing runtime modules")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(ForsettiTheme.Spacing.section)
    }
}

private struct ForsettiBootFailureView: View {
    let error: any Error
    let retry: () -> Void

    private var message: String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    var body: some View {
        ContentUnavailableView {
            Label("Forsetti Could Not Start", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Retry", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(ForsettiTheme.Spacing.section)
    }
}
