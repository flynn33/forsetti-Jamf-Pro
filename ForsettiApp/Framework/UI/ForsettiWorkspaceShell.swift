import SwiftUI

enum ForsettiWorkspaceShellBackgroundStyle {
    case none
    case staticBackdrop
    case animatedBackdrop
}

private enum ForsettiWorkspaceShellBreakpoint {
    static let compactWidth: CGFloat = 760
    static let collapsedRailWidth: CGFloat = 920
    static let sideInspectorWidth: CGFloat = 1120
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
            let showsSideInspector = showsSideInspector(for: width)
            let railWidth = navigationRailWidth(for: width)

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

    private func showsSideInspector(for width: CGFloat) -> Bool {
        showsInspector && width >= ForsettiWorkspaceShellBreakpoint.sideInspectorWidth
    }

    private func navigationRailWidth(for width: CGFloat) -> CGFloat {
        width < ForsettiWorkspaceShellBreakpoint.collapsedRailWidth
            ? ForsettiTheme.Layout.navigationRailCollapsedWidth
            : ForsettiTheme.Layout.navigationRailWidth
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: ForsettiTheme.Spacing.item) {
            navigation
                .frame(maxWidth: .infinity, minHeight: ForsettiTheme.Layout.commandActivityBarHeight, alignment: .leading)
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

            HStack(alignment: .top, spacing: ForsettiTheme.Spacing.item) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                if showsSideInspector {
                    inspector
                        .frame(width: ForsettiTheme.Layout.rightInspectorWidth)
                }
            }

            if showsInspector && !showsSideInspector {
                inspector
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if showsBottomDrawer {
                bottomDrawer
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(ForsettiTheme.Spacing.section)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
