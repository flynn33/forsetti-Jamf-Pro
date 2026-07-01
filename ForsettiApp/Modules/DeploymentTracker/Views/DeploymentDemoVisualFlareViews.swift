import SwiftUI

struct DeploymentDemoMetalHeroView: View {
    let deviceCount: Int
    let projectCount: Int
    let blockedCount: Int
    let readyForPreloadCount: Int
    let startGuidedDemo: () -> Void
    let resetDemo: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            DashboardMetalBackgroundView()
                .opacity(reduceMotion ? 0.18 : 0.34)

            if !reduceMotion {
                DeploymentDemoSignalFlowMetalView(activeWorkspace: .dashboard, activeScenario: nil)
                    .opacity(0.62)
            }

            VStack(alignment: .leading, spacing: DashboardTheme.Spacing.item) {
                DeploymentDemoRibbonView()

                HStack(alignment: .top, spacing: DashboardTheme.Spacing.section) {
                    VStack(alignment: .leading, spacing: DashboardTheme.Spacing.compact) {
                        Text("Deployment Tracker Demo")
                            .font(.system(.title, design: .rounded).weight(.bold))
                        Text("COMING SOON interactive preview with deterministic Dummy data only, simulated Jamf Inventory Preload, read-only ABM review, SD+ preview, shipments, records, and guided scenarios.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: DashboardTheme.Spacing.item)
                    VStack(alignment: .trailing, spacing: DashboardTheme.Spacing.compact) {
                        Button {
                            startGuidedDemo()
                        } label: {
                            Label("Start Guided Demo", systemImage: "play.circle")
                        }
                        .buttonStyle(.borderedProminent)
                        Button {
                            resetDemo()
                        } label: {
                            Label("Reset Demo", systemImage: "arrow.counterclockwise")
                        }
                    }
                }

                HStack(spacing: DashboardTheme.Spacing.compact) {
                    metric("Devices", deviceCount, "macbook.and.iphone")
                    metric("Projects", projectCount, "folder")
                    metric("Preload Ready", readyForPreloadCount, "arrow.up.doc")
                    metric("Blocked", blockedCount, "exclamationmark.triangle")
                }
            }
            .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DashboardTheme.border, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
    }

    private func metric(_ label: String, _ value: Int, _ icon: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(value)")
                    .font(.headline)
                Text(label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: icon)
                .foregroundStyle(DashboardTheme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(DashboardTheme.surface.opacity(0.78))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct DeploymentDemoSignalFlowMetalView: View {
    var activeWorkspace: DeploymentTrackerWorkspace
    var activeScenario: DeploymentDemoScenario?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 1.0 : 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let phase = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                drawFlow(context: &context, size: size, phase: phase)
            }
        }
        .frame(minHeight: 112)
        .accessibilityHidden(true)
    }

    private func drawFlow(context: inout GraphicsContext, size: CGSize, phase: TimeInterval) {
        let y = size.height * 0.5
        let nodes: [CGPoint] = [
            CGPoint(x: size.width * 0.12, y: y),
            CGPoint(x: size.width * 0.34, y: y - 24),
            CGPoint(x: size.width * 0.56, y: y + 18),
            CGPoint(x: size.width * 0.78, y: y - 10),
            CGPoint(x: size.width * 0.92, y: y + 12)
        ]

        var path = Path()
        if let first = nodes.first {
            path.move(to: first)
            for node in nodes.dropFirst() {
                path.addLine(to: node)
            }
        }
        context.stroke(path, with: .color(DashboardTheme.accent.opacity(0.22)), lineWidth: 3)

        for (index, node) in nodes.enumerated() {
            let pulse = reduceMotion ? 0.4 : 0.35 + 0.25 * sin(phase * 1.8 + Double(index))
            let rect = CGRect(x: node.x - 7, y: node.y - 7, width: 14, height: 14)
            context.fill(Path(ellipseIn: rect), with: .color(DashboardTheme.accent.opacity(pulse)))
            context.stroke(Path(ellipseIn: rect.insetBy(dx: -4, dy: -4)), with: .color(.white.opacity(0.22)), lineWidth: 1)
        }

        if let activeScenario {
            let text = Text(activeScenario.title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            context.draw(context.resolve(text), at: CGPoint(x: size.width * 0.5, y: size.height - 18), anchor: .center)
        }
    }
}

struct DeploymentDemoScenarioProgressRailView: View {
    let scenario: DeploymentDemoScenario
    let currentStepIndex: Int
    let isPaused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DashboardTheme.Spacing.compact) {
            HStack {
                Text(isPaused ? "Guided Demo paused" : "Guided Demo progress")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(min(currentStepIndex + 1, scenario.steps.count))/\(scenario.steps.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DashboardTheme.accent)
            }

            ForEach(Array(scenario.steps.enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .top, spacing: DashboardTheme.Spacing.compact) {
                    Image(systemName: index == currentStepIndex ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(index == currentStepIndex ? DashboardTheme.accent : .secondary)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.title)
                            .font(.caption.weight(index == currentStepIndex ? .semibold : .regular))
                            .foregroundStyle(index == currentStepIndex ? .primary : .secondary)
                        if index == currentStepIndex {
                            Text(step.body)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}

struct DeploymentDemoWorkspaceAccentStripView: View {
    var workspace: DeploymentTrackerWorkspace?
    var scenario: DeploymentDemoScenario?
    var isPaused: Bool

    var body: some View {
        HStack(spacing: DashboardTheme.Spacing.compact) {
            Image(systemName: workspace?.iconSystemName ?? "sparkles")
                .foregroundStyle(DashboardTheme.accent)
            Text(workspace?.displayName ?? "Deployment Tracker Demo")
                .font(.caption.weight(.semibold))
            if let scenario {
                Text(scenario.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(isPaused ? "PAUSED" : "DUMMY DATA ONLY")
                .font(.caption2.weight(.bold))
                .foregroundStyle(DashboardTheme.accent)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(DashboardTheme.accent.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
