import SwiftUI

struct ForsettiNavigationItem: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String?
    let systemImage: String
}

struct ForsettiNavigationAction: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let action: () -> Void
}

enum ForsettiNavigationRailMode {
    case regular
    case compactTop
}

struct ForsettiWorkspaceShell<Navigation: View, Command: View, Content: View, Inspector: View, BottomDrawer: View>: View {
    @ViewBuilder let navigation: (Bool) -> Navigation
    @ViewBuilder let commandStream: () -> Command
    @ViewBuilder let content: () -> Content
    @ViewBuilder let inspector: () -> Inspector
    @ViewBuilder let bottomDrawer: () -> BottomDrawer

    var body: some View {
        GeometryReader { proxy in
            let isCompact = proxy.size.width < DashboardTheme.Layout.compactBreakpoint
            let showsInspector = proxy.size.width >= DashboardTheme.Layout.inspectorBreakpoint

            ZStack {
                DashboardTheme.appBackground()
                    .ignoresSafeArea()
                DashboardMetalBackgroundView()
                    .opacity(0.42)
                    .ignoresSafeArea()

                if isCompact {
                    compactLayout
                } else {
                    regularLayout(showsInspector: showsInspector)
                }
            }
        }
    }

    private func regularLayout(showsInspector: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            navigation(false)
                .frame(width: DashboardTheme.Layout.navigationRailWidth)

            VStack(spacing: DashboardTheme.Spacing.lg) {
                commandStream()

                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                bottomDrawer()
            }
            .padding(DashboardTheme.Spacing.screenPaddingRegular)

            if showsInspector {
                inspector()
                    .frame(width: DashboardTheme.Layout.rightInspectorWidth)
                    .padding(.vertical, DashboardTheme.Spacing.screenPaddingRegular)
                    .padding(.trailing, DashboardTheme.Spacing.screenPaddingRegular)
            }
        }
    }

    private var compactLayout: some View {
        VStack(spacing: DashboardTheme.Spacing.md) {
            navigation(true)
                .frame(maxWidth: .infinity)
                .frame(height: 52)

            commandStream()
                .padding(.horizontal, DashboardTheme.Spacing.screenPaddingCompact)

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, DashboardTheme.Spacing.screenPaddingCompact)

            inspector()
                .padding(.horizontal, DashboardTheme.Spacing.screenPaddingCompact)

            bottomDrawer()
                .padding(.horizontal, DashboardTheme.Spacing.screenPaddingCompact)
        }
        .padding(.vertical, DashboardTheme.Spacing.screenPaddingCompact)
    }
}

struct ForsettiNavigationRail: View {
    let appTitle: String
    let appSubtitle: String
    let items: [ForsettiNavigationItem]
    let activeItemID: String?
    let utilityActions: [ForsettiNavigationAction]
    let userLabel: String
    let tenantLabel: String
    var mode: ForsettiNavigationRailMode = .regular

    var body: some View {
        Group {
            switch mode {
            case .regular:
                regularRail
            case .compactTop:
                compactTopRail
            }
        }
        .background(DashboardColors.railSurface.opacity(DashboardTheme.Opacity.railFill))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(DashboardColors.accentCyan.opacity(0.18))
                .frame(width: 1)
        }
    }

    private var regularRail: some View {
        VStack(alignment: .leading, spacing: DashboardTheme.Spacing.lg) {
            brandHeader

            VStack(spacing: DashboardTheme.Spacing.xs) {
                ForEach(items) { item in
                    NavigationLink(value: item.id) {
                        railRow(item)
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()
                .overlay(DashboardColors.separator.opacity(0.6))

            VStack(spacing: DashboardTheme.Spacing.xs) {
                ForEach(utilityActions) { action in
                    Button(action: action.action) {
                        utilityRow(action)
                    }
                    .buttonStyle(.plain)
                    .help(action.title)
                }
            }

            Spacer(minLength: DashboardTheme.Spacing.lg)
            tenantChip
        }
        .padding(DashboardTheme.Spacing.lg)
    }

    private var compactTopRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DashboardTheme.Spacing.sm) {
                Image(systemName: "shield.lefthalf.filled")
                    .foregroundStyle(DashboardColors.accentCyan)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(DashboardColors.accentCyan.opacity(0.14)))

                ForEach(items) { item in
                    NavigationLink(value: item.id) {
                        Label(item.title, systemImage: item.systemImage)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                    }
                    .buttonStyle(.bordered)
                    .tint(item.id == activeItemID ? DashboardColors.accentCyan : DashboardColors.textSecondary)
                }

                ForEach(utilityActions) { action in
                    Button(action: action.action) {
                        Image(systemName: action.systemImage)
                    }
                    .buttonStyle(.bordered)
                    .tint(DashboardColors.accentCyan)
                    .help(action.title)
                }
            }
            .padding(.horizontal, DashboardTheme.Spacing.lg)
            .padding(.vertical, DashboardTheme.Spacing.sm)
        }
    }

    private var brandHeader: some View {
        HStack(spacing: DashboardTheme.Spacing.md) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(DashboardColors.accentCyan)
                .frame(width: 42, height: 42)
                .background(RoundedRectangle(cornerRadius: DashboardTheme.Radius.medium, style: .continuous).fill(DashboardColors.accentCyan.opacity(0.14)))
                .overlay(RoundedRectangle(cornerRadius: DashboardTheme.Radius.medium, style: .continuous).stroke(DashboardColors.accentCyan.opacity(0.42), lineWidth: 1))

            VStack(alignment: .leading, spacing: 2) {
                Text(appTitle)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(DashboardColors.textPrimary)
                    .lineLimit(1)
                Text(appSubtitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DashboardColors.textTertiary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func railRow(_ item: ForsettiNavigationItem) -> some View {
        let isActive = item.id == activeItemID

        return HStack(spacing: DashboardTheme.Spacing.md) {
            Image(systemName: item.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isActive ? DashboardColors.accentCyan : DashboardColors.textSecondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isActive ? DashboardColors.textPrimary : DashboardColors.textSecondary)
                    .lineLimit(1)
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(DashboardColors.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, DashboardTheme.Spacing.md)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: DashboardTheme.Radius.medium, style: .continuous)
                .fill(isActive ? DashboardColors.accentCyan.opacity(DashboardTheme.Opacity.selectedFill) : Color.clear)
        )
        .overlay(alignment: .leading) {
            if isActive {
                RoundedRectangle(cornerRadius: 2)
                    .fill(DashboardColors.accentCyan)
                    .frame(width: 3)
                    .padding(.vertical, 7)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: DashboardTheme.Radius.medium, style: .continuous)
                .stroke(isActive ? DashboardColors.accentCyan.opacity(0.60) : Color.clear, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: DashboardTheme.Radius.medium, style: .continuous))
        .help(item.title)
    }

    private func utilityRow(_ action: ForsettiNavigationAction) -> some View {
        HStack(spacing: DashboardTheme.Spacing.md) {
            Image(systemName: action.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DashboardColors.textSecondary)
                .frame(width: 18)
            Text(action.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(DashboardColors.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DashboardTheme.Spacing.md)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: DashboardTheme.Radius.medium, style: .continuous).fill(DashboardColors.backgroundDepth.opacity(0.24)))
        .contentShape(RoundedRectangle(cornerRadius: DashboardTheme.Radius.medium, style: .continuous))
    }

    private var tenantChip: some View {
        VStack(alignment: .leading, spacing: DashboardTheme.Spacing.xs) {
            HStack(spacing: DashboardTheme.Spacing.sm) {
                Image(systemName: "person.crop.circle.fill")
                    .foregroundStyle(DashboardColors.accentViolet)
                Text(userLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DashboardColors.textPrimary)
                    .lineLimit(1)
            }
            Text(tenantLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(DashboardColors.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DashboardTheme.Spacing.md)
        .background(RoundedRectangle(cornerRadius: DashboardTheme.Radius.medium, style: .continuous).fill(DashboardColors.backgroundDepth.opacity(0.44)))
        .overlay(RoundedRectangle(cornerRadius: DashboardTheme.Radius.medium, style: .continuous).stroke(DashboardColors.separator.opacity(0.36), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}
