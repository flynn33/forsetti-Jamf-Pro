import SwiftUI

/// Imperative commands the panel sends to the diagram (fit to content / reset to 100%).
enum PermissionGraphDiagramCommand: Equatable { case fit, reset }

// The premium, deterministic tiered diagram — the default Visual Hierarchy view.
//
// Renders the two-track hierarchy (Selected → privilege groups → privileges, and
// Selected → endpoint families → endpoints) as aligned premium cards joined by
// crisp connectors. Pure native SwiftUI: sharp at any scale, no Metal, no floating
// projected labels. Works identically on macOS and iOS/iPadOS. Pan via the scroll
// view, zoom via pinch / trackpad magnify, Fit/Reset via the toolbar.
//
// The layout is computed by the panel (cheap, deterministic) and passed in, so
// gesture/hover-driven body passes never rebuild it.
struct PermissionGraphDiagramView: View {
    let snapshot: PermissionGraphSceneSnapshot
    let layout: PermissionGraphDiagramLayout
    @Binding var selectedNodeID: String?
    var showRuntime: Bool
    @Binding var command: PermissionGraphDiagramCommand?
    /// When false (the diagram is embedded in a page that scrolls vertically, e.g.
    /// stacked iPad-portrait / iPhone), the diagram's own scrolling is disabled so it
    /// never competes with the page for the drag gesture. The diagram still fits its
    /// box and supports tap-select + pinch-zoom.
    var scrollEnabled: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var zoom: CGFloat = 1
    @State private var didUserZoom = false
    @State private var hoveredID: String?
    @State private var lastViewportWidth: CGFloat = 0
    @GestureState private var pinch: CGFloat = 1

    private let minZoom: CGFloat = 0.35
    private let maxZoom: CGFloat = 2.5

    var body: some View {
        let scale = clampedZoom(zoom * pinch)
        let content = layout.contentSize

        GeometryReader { proxy in
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                diagramContent
                    .frame(width: content.width, height: content.height, alignment: .topLeading)
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: content.width * scale, height: content.height * scale, alignment: .topLeading)
                    .frame(minWidth: proxy.size.width, minHeight: proxy.size.height, alignment: .center)
                    .dynamicTypeSize(...DynamicTypeSize.xLarge)
            }
            .scrollDisabled(scrollEnabled == false)
            .scrollClipDisabled()
            .gesture(magnify)
            .accessibilityLabel("Permission hierarchy diagram")
            .accessibilityHint("Scroll to pan, pinch or magnify to zoom. Fit and Reset are in the toolbar.")
            .onAppear {
                lastViewportWidth = proxy.size.width
                applyFit(content: content, viewport: proxy.size)
            }
            .onChange(of: proxy.size) { _, newValue in
                // Only re-fit on a real width change — incidental height reflow (detail
                // content growing/shrinking next to the diagram) must not re-snap the zoom.
                let widthChanged = abs(newValue.width - lastViewportWidth) > 1
                lastViewportWidth = newValue.width
                if didUserZoom { zoom = clampedZoom(zoom) }
                else if widthChanged { zoom = fitZoom(content: content, viewport: newValue) }
            }
            .onChange(of: command) { _, newValue in
                guard let newValue else { return }
                switch newValue {
                case .fit: applyFit(content: content, viewport: proxy.size)
                case .reset: applyReset()
                }
                command = nil
            }
        }
    }

    // MARK: - Content

    private var diagramContent: some View {
        let selectedPath = snapshot.selectedPathNodeIDs
        return ZStack(alignment: .topLeading) {
            DiagramGrid()
                .frame(width: layout.contentSize.width, height: layout.contentSize.height)

            ForEach(layout.bands) { band in
                bandBackdrop(band, contentSize: layout.contentSize)
            }

            DiagramConnectors(connectors: layout.connectors, showRuntime: showRuntime)
                .frame(width: layout.contentSize.width, height: layout.contentSize.height)
                .allowsHitTesting(false)

            ForEach(layout.cards) { card in
                if let node = snapshot.node(id: card.id) {
                    let isSelected = selectedNodeID == node.id
                    PermissionGraphDiagramCard(
                        node: node,
                        column: card.column,
                        showRuntime: showRuntime,
                        isSelected: isSelected,
                        isOnSelectedPath: selectedPath.contains(node.id),
                        isHovered: hoveredID == node.id
                    )
                    .frame(width: card.frame.width, height: card.frame.height)
                    .position(x: card.frame.midX, y: card.frame.midY)
                    .onHover { hovering in
                        if hovering { hoveredID = node.id }
                        else if hoveredID == node.id { hoveredID = nil }
                    }
                    .onTapGesture { toggle(node.id) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(node.accessibilityLabel.isEmpty ? node.title : node.accessibilityLabel)
                    .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                    .accessibilityAction { toggle(node.id) }
                    .accessibilitySortPriority(Double(10 - card.column * 3))
                }
            }
        }
        .frame(width: layout.contentSize.width, height: layout.contentSize.height, alignment: .topLeading)
    }

    private func bandBackdrop(_ band: PermissionGraphDiagramLayout.Band, contentSize: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.025))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
                )
                .frame(width: band.frame.width, height: band.frame.height)
                .offset(x: band.frame.minX, y: band.frame.minY)

            // Left-anchored at the header origin — the OS lays out the real text width,
            // so it never drifts under Dynamic Type / localization.
            Label(band.title.uppercased(), systemImage: band.symbolName)
                .font(.caption2.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
                .fixedSize()
                .offset(x: band.headerOrigin.x, y: band.headerOrigin.y + 2)
        }
        .frame(width: contentSize.width, height: contentSize.height, alignment: .topLeading)
    }

    private func toggle(_ id: String) {
        selectedNodeID = (selectedNodeID == id) ? nil : id
    }

    // MARK: - Zoom helpers

    private func clampedZoom(_ value: CGFloat) -> CGFloat { min(max(value, minZoom), maxZoom) }

    private func fitZoom(content: CGSize, viewport: CGSize) -> CGFloat {
        guard content.width > 1, content.height > 1, viewport.width > 1, viewport.height > 1 else { return 1 }
        let inset: CGFloat = 24
        let sx = (viewport.width - inset) / content.width
        let sy = (viewport.height - inset) / content.height
        return min(max(min(sx, sy), minZoom), 1.25)
    }

    private func applyFit(content: CGSize, viewport: CGSize) {
        didUserZoom = false
        animate { zoom = fitZoom(content: content, viewport: viewport) }
    }

    private func applyReset() {
        didUserZoom = true   // an explicit user choice; survives later resizes
        animate { zoom = 1 }
    }

    private func animate(_ change: () -> Void) {
        if reduceMotion { change() }
        else { withAnimation(.easeInOut(duration: 0.25), change) }
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .updating($pinch) { value, state, _ in state = value.magnification }
            .onEnded { value in
                zoom = clampedZoom(zoom * value.magnification)
                didUserZoom = true
            }
    }
}

// MARK: - Faint blueprint grid

private struct DiagramGrid: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 30
            var path = Path()
            var x: CGFloat = 0
            while x <= size.width { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)); x += step }
            var y: CGFloat = 0
            while y <= size.height { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)); y += step }
            context.stroke(path, with: .color(.white.opacity(0.035)), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Connectors

private struct DiagramConnectors: View {
    let connectors: [PermissionGraphDiagramLayout.Connector]
    let showRuntime: Bool

    var body: some View {
        Canvas { context, _ in
            // Soft glow under selected-path connectors (two passes for a real glow).
            for c in connectors where c.isSelectedPath {
                context.stroke(path(for: c), with: .color(DashboardColors.bluePrimary.opacity(0.16)), lineWidth: 10)
                context.stroke(path(for: c), with: .color(DashboardColors.bluePrimary.opacity(0.30)), lineWidth: 6)
            }
            for c in connectors {
                let color = strokeColor(for: c)
                context.stroke(path(for: c), with: .color(color), style: strokeStyle(for: c))
                // Anchor dots at both ends so connectors meet cards cleanly.
                for point in [c.from, c.to] {
                    let dot = Path(ellipseIn: CGRect(x: point.x - 2.5, y: point.y - 2.5, width: 5, height: 5))
                    context.fill(dot, with: .color(color.opacity(0.95)))
                }
            }
        }
    }

    private func path(for c: PermissionGraphDiagramLayout.Connector) -> Path {
        var p = Path()
        p.move(to: c.from)
        switch c.orientation {
        case .horizontal:
            let dx = (c.to.x - c.from.x) * 0.5
            p.addCurve(to: c.to,
                       control1: CGPoint(x: c.from.x + dx, y: c.from.y),
                       control2: CGPoint(x: c.to.x - dx, y: c.to.y))
        case .vertical:
            let dy = (c.to.y - c.from.y) * 0.5
            p.addCurve(to: c.to,
                       control1: CGPoint(x: c.from.x, y: c.from.y + dy),
                       control2: CGPoint(x: c.to.x, y: c.to.y - dy))
        }
        return p
    }

    private func strokeColor(for c: PermissionGraphDiagramLayout.Connector) -> Color {
        if c.isSelectedPath { return DashboardColors.bluePrimary.opacity(0.95) }
        if showRuntime, c.runtimeStatus != .notChecked {
            return PermissionGraphStyle.color(status: c.runtimeStatus, kind: .privilege).opacity(0.7)
        }
        if c.kind == .fallback_to { return Color(red: 0.78, green: 0.62, blue: 0.44).opacity(0.7) }
        return DashboardColors.blueSecondary.opacity(0.5)
    }

    private func strokeStyle(for c: PermissionGraphDiagramLayout.Connector) -> StrokeStyle {
        let width: CGFloat = c.isSelectedPath ? 2.6 : 1.6
        if c.kind == .fallback_to {
            return StrokeStyle(lineWidth: width, lineCap: .round, dash: [5, 4])
        }
        return StrokeStyle(lineWidth: width, lineCap: .round)
    }
}

// MARK: - Card

private struct PermissionGraphDiagramCard: View {
    let node: PermissionGraphNode
    let column: Int
    let showRuntime: Bool
    let isSelected: Bool
    let isOnSelectedPath: Bool
    let isHovered: Bool

    private var accent: Color { PermissionGraphStyle.color(status: node.runtimeStatus, kind: node.kind) }
    private var kindTint: Color { PermissionGraphStyle.color(status: .notChecked, kind: node.kind) }
    private var isHero: Bool { node.kind == .selected_item }
    private var isMono: Bool { node.kind == .endpoint }
    private var radius: CGFloat { isHero ? 16 : 13 }

    var body: some View {
        HStack(spacing: 10) {
            iconBadge
            VStack(alignment: .leading, spacing: 3) {
                Text(node.title)
                    .font(isHero ? .subheadline.weight(.bold) : .caption.weight(.semibold))
                    .fontDesign(isMono ? .monospaced : .default)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .truncationMode(isMono ? .middle : .tail)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle = node.subtitle, subtitle.isEmpty == false {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if showRuntime, node.runtimeStatus != .notChecked {
                    statusPill
                }
            }
            Spacer(minLength: 0)
            if riskSymbols.isEmpty == false {
                VStack(spacing: 4) {
                    ForEach(Array(riskSymbols.prefix(2)), id: \.self) { symbol in
                        Image(systemName: symbol)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(PermissionGraphStyle.riskAmber)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(PermissionGraphStyle.riskAmber.opacity(0.16)))
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, isHero ? 12 : 9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(cardBackground)
        .overlay(cardBorder)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .shadow(color: .black.opacity(isSelected ? 0.35 : 0.22),
                radius: isSelected ? 12 : 6, x: 0, y: isSelected ? 5 : 3)
        .shadow(color: isSelected ? accent.opacity(0.4) : .clear, radius: 14)
        .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }

    private var iconBadge: some View {
        RoundedRectangle(cornerRadius: isHero ? 11 : 9, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [kindTint.opacity(0.45), kindTint.opacity(0.18)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: isHero ? 11 : 9, style: .continuous)
                    .strokeBorder(kindTint.opacity(0.6), lineWidth: 1)
            )
            .frame(width: isHero ? 40 : 32, height: isHero ? 40 : 32)
            .overlay(
                Image(systemName: PermissionGraphStyle.symbol(kind: node.kind))
                    .font(isHero ? .body.weight(.semibold) : .caption.weight(.semibold))
                    .foregroundStyle(kindTint)
            )
    }

    private var statusPill: some View {
        HStack(spacing: 3) {
            Image(systemName: PermissionGraphStyle.statusSymbol(node.runtimeStatus))
                .font(.system(size: 9, weight: .bold))
            Text(PermissionGraphStyle.statusLabel(node.runtimeStatus))
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(accent)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Capsule(style: .continuous).fill(accent.opacity(0.18)))
        .overlay(Capsule(style: .continuous).strokeBorder(accent.opacity(0.5), lineWidth: 0.75))
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(
                LinearGradient(
                    colors: isHero
                        ? [Color(red: 0.13, green: 0.18, blue: 0.30), Color(red: 0.08, green: 0.11, blue: 0.19)]
                        : [Color(red: 0.11, green: 0.14, blue: 0.21), Color(red: 0.07, green: 0.09, blue: 0.15)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [kindTint.opacity(0.14), .clear],
                            startPoint: .top, endPoint: .center
                        )
                    )
            )
    }

    private var cardBorder: some View {
        let color: Color
        let width: CGFloat
        if isSelected { color = accent; width = 2 }
        else if isOnSelectedPath { color = DashboardColors.bluePrimary.opacity(0.65); width = 1.5 }
        else if isHovered { color = accent.opacity(0.7); width = 1.3 }
        else { color = accent.opacity(0.32); width = 1 }
        return RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(color, lineWidth: width)
    }

    private var riskSymbols: [String] {
        node.riskFlags.compactMap { flag in
            switch flag {
            case .destructive: return "trash.fill"
            case .security_sensitive: return "lock.fill"
            case .deprecated: return "clock.badge.exclamationmark"
            case .tenant_verify: return "exclamationmark.triangle.fill"
            case .legacy_fallback: return "arrow.triangle.branch"
            case .classic_api: return "building.columns"
            case .read_only: return nil
            }
        }
    }
}
