import SwiftUI

enum ForsettiWorkspaceShellBackgroundStyle {
    case none
    case staticBackdrop
    case animatedBackdrop
}

enum ForsettiWorkspaceNavigationPlacement {
    case side
    case top
}

private struct ForsettiWorkspaceNavigationPlacementKey: EnvironmentKey {
    static let defaultValue: ForsettiWorkspaceNavigationPlacement = .side
}

extension EnvironmentValues {
    var forsettiWorkspaceNavigationPlacement: ForsettiWorkspaceNavigationPlacement {
        get { self[ForsettiWorkspaceNavigationPlacementKey.self] }
        set { self[ForsettiWorkspaceNavigationPlacementKey.self] = newValue }
    }
}

private enum ForsettiWorkspaceShellBreakpoint {
    static let compactWidth: CGFloat = 960
    static let sideInspectorContentWidth: CGFloat = 1_080
}

/// Shared retail workspace frame for Forsetti screens.
struct ForsettiWorkspaceShell<Navigation: View, CommandActivity: View, Header: View, Content: View, Inspector: View, BottomDrawer: View>: View {
    private let navigation: Navigation
    private let commandActivityBar: CommandActivity
    private let header: Header
    private let content: Content
    private let inspector: Inspector
    private let bottomDrawer: BottomDrawer
    private let showsInspector: Bool
    private let showsBottomDrawer: Bool
    private let backgroundStyle: ForsettiWorkspaceShellBackgroundStyle

    init(
        showsInspector: Bool = true,
        showsBottomDrawer: Bool = true,
        backgroundStyle: ForsettiWorkspaceShellBackgroundStyle = .staticBackdrop,
        @ViewBuilder navigation: () -> Navigation,
        @ViewBuilder commandActivityBar: () -> CommandActivity,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content,
        @ViewBuilder inspector: () -> Inspector,
        @ViewBuilder bottomDrawer: () -> BottomDrawer
    ) {
        self.navigation = navigation()
        self.commandActivityBar = commandActivityBar()
        self.header = header()
        self.content = content()
        self.inspector = inspector()
        self.bottomDrawer = bottomDrawer()
        self.showsInspector = showsInspector
        self.showsBottomDrawer = showsBottomDrawer
        self.backgroundStyle = backgroundStyle
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let isCompact = isCompactWidth(width)
            let railWidth = navigationRailWidth
            let contentWidth = max(0, width - railWidth)
            let showsSideInspector = showsSideInspector(forContentWidth: contentWidth)

            if isCompact {
                compactLayout
            } else {
                regularLayout(railWidth: railWidth, showsSideInspector: showsSideInspector)
            }
        }
        .background {
            ForsettiRetailWorkspaceBackground(style: backgroundStyle)
        }
    }

    private func isCompactWidth(_ width: CGFloat) -> Bool {
        width < ForsettiWorkspaceShellBreakpoint.compactWidth
    }

    private func showsSideInspector(forContentWidth width: CGFloat) -> Bool {
        showsInspector && width >= ForsettiWorkspaceShellBreakpoint.sideInspectorContentWidth
    }

    private var navigationRailWidth: CGFloat {
        ForsettiTheme.Layout.navigationRailWidth
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: ForsettiTheme.Spacing.item) {
            navigation
                .frame(maxWidth: .infinity, minHeight: ForsettiTheme.Layout.commandActivityBarHeight, alignment: .leading)
                .environment(\.forsettiWorkspaceNavigationPlacement, .top)
                .background(ForsettiTheme.surface.opacity(0.92))
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(ForsettiTheme.border)
                        .frame(height: 1)
                }

            workspaceColumn(showsSideInspector: false)
        }
    }

    private func regularLayout(railWidth: CGFloat, showsSideInspector: Bool) -> some View {
        HStack(spacing: 0) {
            navigation
                .frame(width: railWidth)
                .frame(maxHeight: .infinity)
                .environment(\.forsettiWorkspaceNavigationPlacement, .side)
                .background(ForsettiTheme.surface.opacity(0.92))
                .overlay(alignment: .trailing) {
                    Rectangle()
                        .fill(ForsettiTheme.border)
                        .frame(width: 1)
                }

            workspaceColumn(showsSideInspector: showsSideInspector)
        }
    }

    private func workspaceColumn(showsSideInspector: Bool) -> some View {
        VStack(alignment: .leading, spacing: ForsettiTheme.Spacing.item) {
            commandActivityBar
                .frame(maxWidth: .infinity)

            header
                .frame(maxWidth: .infinity, alignment: .leading)

            GeometryReader { scrollProxy in
                let minimumWidth = scrollContentMinimumWidth(showsSideInspector: showsSideInspector)
                let contentWidth = max(scrollProxy.size.width, minimumWidth)
                let mainContentWidth = primaryContentWidth(
                    contentWidth: contentWidth,
                    showsSideInspector: showsSideInspector
                )
                let scrollAxes: Axis.Set = scrollProxy.size.width < minimumWidth ? [.horizontal, .vertical] : .vertical

                ScrollView(scrollAxes, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: ForsettiTheme.Spacing.section) {
                        if showsSideInspector {
                            HStack(alignment: .top, spacing: ForsettiTheme.Spacing.item) {
                                content
                                    .frame(width: mainContentWidth, alignment: .topLeading)

                                inspector
                                    .frame(width: ForsettiTheme.Layout.rightInspectorWidth, alignment: .topLeading)
                            }
                        } else {
                            content
                                .frame(width: contentWidth, alignment: .topLeading)

                            if showsInspector {
                                inspector
                                    .frame(width: contentWidth, alignment: .leading)
                            }
                        }

                        if showsBottomDrawer {
                            bottomDrawer
                                .frame(width: contentWidth, alignment: .leading)
                        }
                    }
                    .frame(width: contentWidth, alignment: .topLeading)
                }
                .scrollIndicators(.visible)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(ForsettiTheme.Spacing.section)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func scrollContentMinimumWidth(showsSideInspector: Bool) -> CGFloat {
        if showsSideInspector {
            return ForsettiTheme.Layout.dashboardContentMinimumWidth
                + ForsettiTheme.Spacing.item
                + ForsettiTheme.Layout.rightInspectorWidth
        }

        return ForsettiTheme.Layout.dashboardContentMinimumWidth
    }

    private func primaryContentWidth(contentWidth: CGFloat, showsSideInspector: Bool) -> CGFloat {
        guard showsSideInspector else { return contentWidth }

        let remainingWidth = contentWidth
            - ForsettiTheme.Spacing.item
            - ForsettiTheme.Layout.rightInspectorWidth
        return max(ForsettiTheme.Layout.dashboardContentMinimumWidth, remainingWidth)
    }
}

extension ForsettiWorkspaceShell where Inspector == EmptyView, BottomDrawer == EmptyView {
    init(
        @ViewBuilder navigation: () -> Navigation,
        @ViewBuilder commandActivityBar: () -> CommandActivity,
        @ViewBuilder header: () -> Header,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            showsInspector: false,
            showsBottomDrawer: false,
            navigation: navigation,
            commandActivityBar: commandActivityBar,
            header: header,
            content: content,
            inspector: { EmptyView() },
            bottomDrawer: { EmptyView() }
        )
    }
}

private struct ForsettiRetailWorkspaceBackground: View {
    let style: ForsettiWorkspaceShellBackgroundStyle

    init(style: ForsettiWorkspaceShellBackgroundStyle) {
        self.style = style
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            switch style {
            case .none:
                Color.clear
            case .staticBackdrop:
                ForsettiTheme.groupedSurface
                ForsettiTheme.appBackdropGradient.opacity(0.50)
            case .animatedBackdrop:
                ForsettiTheme.groupedSurface
                if scenePhase == .active && !reduceMotion {
                    ForsettiMetalBackgroundView()
                }
                ForsettiTheme.appBackdropGradient.opacity(0.50)
            }
        }
        .ignoresSafeArea()
    }
}
