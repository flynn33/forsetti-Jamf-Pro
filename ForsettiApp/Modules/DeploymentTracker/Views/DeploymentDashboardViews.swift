import SwiftUI

// MARK: - Deployment Dashboard
//
// Dashboard views render projections only. They do not calculate operational
// totals themselves; DeploymentKPIProjectionService prepares those values so the
// dashboard remains a presentation layer with predictable refresh behavior.
struct DeploymentDashboardKPIView: View {
    let projection: DeploymentDashboardProjection

    var body: some View {
        VStack(alignment: .leading, spacing: ForsettiTheme.Spacing.section) {
            HStack(alignment: .firstTextBaseline) {
                Label("Dashboard", systemImage: "chart.xyaxis.line")
                    .font(.headline)
                Spacer()
                Text("KPI projections")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 148), spacing: ForsettiTheme.Spacing.item)],
                alignment: .leading,
                spacing: ForsettiTheme.Spacing.item
            ) {
                ForEach(projection.operationalTotals) { kpi in
                    DeploymentMetricTile(projection: kpi)
                }
            }

            HStack(alignment: .top, spacing: ForsettiTheme.Spacing.section) {
                DeploymentRingGroup(title: "Integration Health", projections: projection.integrationHealth)
                DeploymentStatusIndicatorList(projections: projection.statusIndicators)
                DeploymentDeviceTypeDistributionView(projections: projection.deviceTypeDistribution)
            }
        }
        .padding(16)
        .forsettiCardSurface()
    }
}

// Task cards provide intent-driven entry points into the tracker workflows. Some
// cards navigate to a workspace, while others execute a safe view-model action
// such as validation or export generation.
struct DeploymentDashboardTaskCardsView: View {
    @ObservedObject var viewModel: DeploymentTrackerViewModel

    // Keep the Dashboard action list local to the Dashboard so new technician
    // workflows can be added without changing workspace routing or persistence
    // code.
    private let tasks: [DeploymentDashboardTask] = [
        DeploymentDashboardTask(
            title: "Work Demo Devices",
            description: "Open the Workbench to review, edit, validate, and run simulated actions on Demo rows.",
            iconSystemName: "tablecells",
            guideTopicID: "workbench",
            action: .workspace(.inProgress)
        ),
        DeploymentDashboardTask(
            title: "Create Demo Project",
            description: "Create or review a Demo project that groups devices and workflow context.",
            iconSystemName: "folder.badge.plus",
            guideTopicID: "projects",
            action: .workspace(.projects)
        ),
        DeploymentDashboardTask(
            title: "Add or Import Demo Devices",
            description: "Create Demo device records manually or preview incoming Demo import data.",
            iconSystemName: "tray.and.arrow.down",
            guideTopicID: "imports",
            action: .workspace(.intakeImports)
        ),
        DeploymentDashboardTask(
            title: "Preview Demo Jamf Preload Validation",
            description: "Check selected Demo devices for required fields. Dummy data only. No live Jamf actions.",
            iconSystemName: "checklist",
            guideTopicID: "exceptions-validation",
            action: .validatePreload
        ),
        DeploymentDashboardTask(
            title: "Simulate Jamf Preload Submission",
            description: "Run a Demo Inventory Preload simulation. No live Jamf actions.",
            iconSystemName: "paperplane",
            guideTopicID: "jamf-preload",
            action: .sendPreload
        ),
        DeploymentDashboardTask(
            title: "Preview Demo Preload Update",
            description: "Build a Demo update batch so matching serial data can be reviewed before production enablement.",
            iconSystemName: "arrow.triangle.2.circlepath",
            guideTopicID: "preload-updates",
            action: .createPreloadUpdate
        ),
        DeploymentDashboardTask(
            title: "Run Demo ABM Verification",
            description: "Queue read-only Demo Apple Business verification and local exception review. No ABM data changed.",
            iconSystemName: "checkmark.shield",
            guideTopicID: "abm-verification",
            action: .runABMVerification
        ),
        DeploymentDashboardTask(
            title: "Generate Demo SD+ Export Preview",
            description: "Generate a Demo ServiceDesk Plus CSV preview and record Demo export history.",
            iconSystemName: "square.and.arrow.up",
            guideTopicID: "sdplus-export",
            action: .generateSDPlus
        ),
        DeploymentDashboardTask(
            title: "Track Demo Shipments",
            description: "Review seeded outbound, delivered, returned, and blocked Demo shipment states.",
            iconSystemName: "shippingbox",
            guideTopicID: "shipments",
            action: .workspace(.shipments)
        ),
        DeploymentDashboardTask(
            title: "Open Demo Records Management",
            description: "Preview archive-first governance, records export, and controlled deletion eligibility with Demo data.",
            iconSystemName: "archivebox",
            guideTopicID: "records-management",
            action: .workspace(.recordsManagement)
        )
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: ForsettiTheme.Spacing.item) {
            HStack(alignment: .firstTextBaseline) {
                Label("What do you want to do?", systemImage: "bolt.circle")
                    .font(.headline)
                Spacer()
                Button {
                    viewModel.openGuide(topicID: "dashboard", sourceWorkspace: .dashboard)
                } label: {
                    Label("Guide", systemImage: "questionmark.circle")
                }
                .help("Open Dashboard guide")
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 260), spacing: ForsettiTheme.Spacing.item)],
                alignment: .leading,
                spacing: ForsettiTheme.Spacing.item
            ) {
                ForEach(tasks) { task in
                    DeploymentDashboardTaskCard(task: task, viewModel: viewModel)
                }
            }
        }
        .padding(16)
        .forsettiCardSurface()
    }
}

// Small value type that describes one Dashboard task card. The action enum keeps
// command execution explicit and prevents strings from driving behavior.
private struct DeploymentDashboardTask: Identifiable {
    var id: String { title }
    let title: String
    let description: String
    let iconSystemName: String
    let guideTopicID: String
    let action: DeploymentDashboardTaskAction
}

// Actions that a Dashboard task can perform. Workspace navigation and direct
// service-backed commands are separate cases so each button path stays obvious.
private enum DeploymentDashboardTaskAction {
    case workspace(DeploymentTrackerWorkspace)
    case validatePreload
    case sendPreload
    case createPreloadUpdate
    case runABMVerification
    case generateSDPlus
}

// Individual task card. The card intentionally exposes both a primary action
// and a guide action so a technician can either start work immediately or open
// the matching procedure.
private struct DeploymentDashboardTaskCard: View {
    let task: DeploymentDashboardTask
    @ObservedObject var viewModel: DeploymentTrackerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: ForsettiTheme.Spacing.compact) {
            Label(task.title, systemImage: task.iconSystemName)
                .font(.callout.weight(.semibold))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Text(task.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: ForsettiTheme.Spacing.compact)

            HStack {
                Button {
                    runPrimaryAction()
                } label: {
                    Label("Start", systemImage: "arrow.right.circle")
                }
                Button {
                    viewModel.openGuide(topicID: task.guideTopicID, sourceWorkspace: .dashboard)
                } label: {
                    Label("Guide me", systemImage: "questionmark.circle")
                }
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .padding(12)
        .background(ForsettiTheme.groupedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(ForsettiTheme.border, lineWidth: 1)
        }
    }

    private func runPrimaryAction() {
        // Route all actions through the view model. This gives each action the
        // same validation, diagnostics, and projection refresh behavior as the
        // Workbench toolbar.
        switch task.action {
        case .workspace(let workspace):
            viewModel.selectWorkspace(workspace)
        case .validatePreload:
            viewModel.selectWorkspace(.inProgress)
            viewModel.validateSelectedForPreload()
        case .sendPreload:
            viewModel.selectWorkspace(.jamfPreload)
            viewModel.sendSelectedInventoryPreload()
        case .createPreloadUpdate:
            viewModel.selectWorkspace(.jamfPreload)
            viewModel.createPreloadUpdateBatch()
        case .runABMVerification:
            viewModel.selectWorkspace(.abmVerification)
            viewModel.verifySelectedWithABM()
        case .generateSDPlus:
            viewModel.selectWorkspace(.sdPlusExport)
            viewModel.generateSDPlusExport()
        }
    }
}

// Numeric KPI tile used for high-level operational counts. The color comes from
// the projection so the Dashboard can reuse the same semantic colors as rings
// and status lists.
private struct DeploymentMetricTile: View {
    let projection: DeploymentKPIProjection

    var body: some View {
        HStack(spacing: ForsettiTheme.Spacing.compact) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)

            VStack(alignment: .leading, spacing: 2) {
                Text(projection.value.formatted())
                    .font(.system(.title3, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                Text(projection.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
        .padding(10)
        .background(ForsettiTheme.groupedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(projection.accessibilitySummary))
    }

    private var color: Color {
        Color(red: projection.color.red, green: projection.color.green, blue: projection.color.blue, opacity: projection.color.alpha)
    }
}

// Ring group renders progress-style KPIs, backed by the Metal KPI ring where
// available and the fallback renderer where Metal cannot be used.
private struct DeploymentRingGroup: View {
    let title: String
    let projections: [DeploymentKPIProjection]

    var body: some View {
        VStack(alignment: .leading, spacing: ForsettiTheme.Spacing.compact) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 96), spacing: ForsettiTheme.Spacing.item)],
                spacing: ForsettiTheme.Spacing.item
            ) {
                ForEach(projections) { projection in
                    VStack(spacing: ForsettiTheme.Spacing.compact) {
                        DeploymentKPIRingView(projection: projection)
                            .frame(width: 88, height: 88)
                        Text(projection.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .frame(minHeight: 28)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

// Ordered status list for the most important workflow and exception counts.
// It uses compact colored dots for fast visual scanning.
private struct DeploymentStatusIndicatorList: View {
    let projections: [DeploymentKPIProjection]

    var body: some View {
        VStack(alignment: .leading, spacing: ForsettiTheme.Spacing.compact) {
            Text("Status Indicators")
                .font(.subheadline.weight(.semibold))

            if projections.isEmpty {
                Text("No active status counts")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(projections.prefix(8)) { projection in
                    HStack(spacing: ForsettiTheme.Spacing.compact) {
                        Circle()
                            .fill(color(for: projection))
                            .frame(width: 8, height: 8)
                        Text(projection.displayName)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Text(projection.value.formatted())
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func color(for projection: DeploymentKPIProjection) -> Color {
        Color(red: projection.color.red, green: projection.color.green, blue: projection.color.blue, opacity: projection.color.alpha)
    }
}

// Horizontal bar distribution for device type totals. The projection fraction
// is precomputed so this view only converts it into a capsule width.
private struct DeploymentDeviceTypeDistributionView: View {
    let projections: [DeploymentKPIProjection]

    var body: some View {
        VStack(alignment: .leading, spacing: ForsettiTheme.Spacing.compact) {
            Text("Device Types")
                .font(.subheadline.weight(.semibold))

            if projections.isEmpty {
                Text("No device type data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(projections.prefix(6)) { projection in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(projection.displayName)
                                .font(.caption)
                                .lineLimit(1)
                            Spacer()
                            Text(projection.value.formatted())
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                        }
                        GeometryReader { proxy in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.secondary.opacity(0.16))
                                Capsule()
                                    .fill(color(for: projection))
                                    .frame(width: proxy.size.width * projection.fraction)
                            }
                        }
                        .frame(height: 5)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(projection.accessibilitySummary))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func color(for projection: DeploymentKPIProjection) -> Color {
        Color(red: projection.color.red, green: projection.color.green, blue: projection.color.blue, opacity: projection.color.alpha)
    }
}
