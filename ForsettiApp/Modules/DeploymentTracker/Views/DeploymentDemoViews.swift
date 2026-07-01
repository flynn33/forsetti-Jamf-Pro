import SwiftUI

struct DeploymentDemoSafetyNotice: View {
    var body: some View {
        HStack(alignment: .top, spacing: DashboardTheme.Spacing.compact) {
            Image(systemName: "lock.shield")
                .foregroundStyle(DashboardTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Dummy data only. No live Jamf actions.")
                    .font(.callout.weight(.semibold))
                Text("Simulation controls use deterministic Demo records and describe the production equivalent without changing Jamf, ABM, SD+, shipping, or production records.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(DashboardTheme.groupedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct DeploymentDemoHeroView: View {
    @ObservedObject var viewModel: DeploymentTrackerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: DashboardTheme.Spacing.item) {
            DeploymentDemoMetalHeroView(
                deviceCount: viewModel.devices.count,
                projectCount: viewModel.projects.count,
                blockedCount: viewModel.exceptions.count,
                readyForPreloadCount: viewModel.dashboardProjection.operationalTotals.first { $0.id == "ready-jamf-preload" }?.value ?? 0,
                startGuidedDemo: {
                    viewModel.startDemoScenario(id: "quick-start-tour")
                },
                resetDemo: {
                    viewModel.resetDemoData()
                }
            )
            DeploymentDemoSafetyNotice()
        }
        .padding(16)
        .dashboardCardSurface()
    }
}

struct DeploymentDemoScenarioLauncher: View {
    @ObservedObject var viewModel: DeploymentTrackerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: DashboardTheme.Spacing.item) {
            HStack {
                Label("Guided Demo Scenarios", systemImage: "rectangle.stack.badge.play")
                    .font(.headline)
                Spacer()
                Button {
                    viewModel.startDemoScenario(id: "quick-start-tour")
                } label: {
                    Label("Start Guided Demo", systemImage: "play.circle")
                }
                .buttonStyle(.borderedProminent)
            }

            if let scenario = viewModel.activeDemoScenario,
               let step = viewModel.activeDemoScenarioStepText {
                Text("\(scenario.title): \(step)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 250), spacing: DashboardTheme.Spacing.item)],
                alignment: .leading,
                spacing: DashboardTheme.Spacing.item
            ) {
                ForEach(DeploymentDemoScenarioCatalog.scenarios) { scenario in
                    Button {
                        viewModel.startDemoScenario(scenario)
                    } label: {
                        VStack(alignment: .leading, spacing: DashboardTheme.Spacing.compact) {
                            Label(scenario.title, systemImage: scenario.systemImage)
                                .font(.callout.weight(.semibold))
                            Text(scenario.summary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                                .lineLimit(3)
                            HStack {
                                Text("\(scenario.steps.count) guided steps")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("Run Demo")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(DashboardTheme.accent)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 142, alignment: .topLeading)
                        .padding(12)
                        .background(DashboardTheme.groupedSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(DashboardTheme.border, lineWidth: 1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            if viewModel.activeDemoScenario != nil {
                DeploymentDemoSimulationTimelineView(viewModel: viewModel)
            }
        }
        .padding(16)
        .dashboardCardSurface()
    }
}

struct DeploymentDemoSimulationTimelineView: View {
    @ObservedObject var viewModel: DeploymentTrackerViewModel

    var body: some View {
        if let scenario = viewModel.activeDemoScenario {
            VStack(alignment: .leading, spacing: DashboardTheme.Spacing.compact) {
                Label("Demo Timeline", systemImage: "timeline.selection")
                    .font(.subheadline.weight(.semibold))
                // Controls scroll horizontally so the seven actions never crush or
                // clip on iPhone / iPad portrait.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DashboardTheme.Spacing.compact) {
                    Button {
                        viewModel.rewindDemoScenarioStep()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .help("Previous Demo step")
                    Button {
                        viewModel.advanceDemoScenarioStep()
                    } label: {
                        Label("Next", systemImage: "chevron.right")
                    }
                    .help("Next Demo step")
                    Button {
                        viewModel.isDemoScenarioPaused ? viewModel.resumeDemoScenario() : viewModel.pauseDemoScenario()
                    } label: {
                        Label(viewModel.isDemoScenarioPaused ? "Resume" : "Pause", systemImage: viewModel.isDemoScenarioPaused ? "play" : "pause")
                    }
                    Button {
                        viewModel.openActiveDemoScenarioGuide()
                    } label: {
                        Label("Open Guide", systemImage: "questionmark.circle")
                    }
                    Button {
                        viewModel.runActiveDemoScenarioAction()
                    } label: {
                        Label("Run Demo", systemImage: "play.rectangle")
                    }
                    Button {
                        viewModel.finishDemoScenario()
                    } label: {
                        Label("Finish", systemImage: "checkmark.circle")
                    }
                    Button {
                        viewModel.skipDemoScenario()
                    } label: {
                        Label("Skip", systemImage: "xmark.circle")
                    }
                    }
                    .padding(.vertical, 2)
                }
                DeploymentDemoScenarioProgressRailView(
                    scenario: scenario,
                    currentStepIndex: viewModel.activeDemoScenarioStepIndex,
                    isPaused: viewModel.isDemoScenarioPaused
                )
            }
            .padding(12)
            .background(DashboardTheme.groupedSurface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

struct DeploymentDemoSimulationResultCard: View {
    let result: DeploymentDemoSimulationResult

    var body: some View {
        VStack(alignment: .leading, spacing: DashboardTheme.Spacing.compact) {
            DeploymentDemoRibbonView()
            Label(result.title, systemImage: result.externalDataChanged ? "exclamationmark.triangle" : "checkmark.seal")
                .font(.headline)
            Text(result.summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: DashboardTheme.Spacing.item) {
                DeploymentDemoFact(label: "System", value: result.simulatedSystem)
                DeploymentDemoFact(label: "Demo records", value: "\(result.affectedDemoRecordCount)")
                DeploymentDemoFact(label: "External changed", value: result.externalDataChanged ? "Yes" : "No")
            }
            Text("Production equivalent: \(result.productionEquivalent)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let next = result.nextRecommendedDemoAction {
                Text("Next Demo action: \(next)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DashboardTheme.accent)
            }
        }
        .padding(16)
        .dashboardCardSurface()
    }
}

struct DeploymentDemoScenarioOverlayView: View {
    @ObservedObject var viewModel: DeploymentTrackerViewModel

    var body: some View {
        if let scenario = viewModel.activeDemoScenario,
           let step = viewModel.activeDemoScenarioStep {
            VStack(alignment: .leading, spacing: DashboardTheme.Spacing.item) {
                HStack(alignment: .top, spacing: DashboardTheme.Spacing.compact) {
                    Label(scenario.title, systemImage: scenario.systemImage)
                        .font(.headline)
                    Spacer()
                    Text("\(viewModel.activeDemoScenarioStepIndex + 1)/\(scenario.steps.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                DeploymentDemoCoachMarkView(step: step, isPaused: viewModel.isDemoScenarioPaused)

                HStack(spacing: DashboardTheme.Spacing.compact) {
                    Button {
                        viewModel.rewindDemoScenarioStep()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .disabled(viewModel.activeDemoScenarioStepIndex == 0)

                    Button {
                        viewModel.advanceDemoScenarioStep()
                    } label: {
                        Label("Next", systemImage: "chevron.right")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        viewModel.skipDemoScenario()
                    } label: {
                        Label("Skip", systemImage: "xmark.circle")
                    }

                    Button {
                        viewModel.finishDemoScenario()
                    } label: {
                        Label("Finish", systemImage: "checkmark.circle")
                    }
                }

                HStack(spacing: DashboardTheme.Spacing.compact) {
                    Button {
                        viewModel.isDemoScenarioPaused ? viewModel.resumeDemoScenario() : viewModel.pauseDemoScenario()
                    } label: {
                        Label(viewModel.isDemoScenarioPaused ? "Resume" : "Pause", systemImage: viewModel.isDemoScenarioPaused ? "play" : "pause")
                    }

                    Button {
                        viewModel.openActiveDemoScenarioGuide()
                    } label: {
                        Label("Open Guide", systemImage: "questionmark.circle")
                    }

                    Button {
                        viewModel.runActiveDemoScenarioAction()
                    } label: {
                        Label("Run Demo", systemImage: "play.rectangle")
                    }
                }
            }
            .padding(14)
            // maxWidth (not a hard width) so the coach-mark shrinks to fit narrow
            // iPhones instead of overflowing off-screen as a bottom-trailing overlay.
            .frame(maxWidth: 380, alignment: .leading)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(DashboardTheme.border, lineWidth: 1)
            }
            .shadow(radius: 12, y: 4)
            .padding(DashboardTheme.Spacing.section)
        }
    }
}

struct DeploymentDemoCoachMarkView: View {
    let step: DeploymentDemoStep
    let isPaused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DashboardTheme.Spacing.compact) {
            HStack {
                Label(step.title, systemImage: iconName)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if isPaused {
                    Text("Paused")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Text(step.body)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Expected: \(step.expectedResult)")
                .font(.caption)
                .foregroundStyle(DashboardTheme.accent)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(DashboardTheme.groupedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var iconName: String {
        switch step.actionKind {
        case .navigate: return "arrow.turn.down.right"
        case .inspect: return "magnifyingglass"
        case .preview: return "doc.text.magnifyingglass"
        case .simulate: return "play.rectangle"
        case .validate: return "checklist.checked"
        case .export: return "square.and.arrow.up"
        case .configure: return "slider.horizontal.3"
        case .guide: return "questionmark.circle"
        case .complete: return "checkmark.seal"
        }
    }
}

struct DeploymentDemoCompletionCardView: View {
    let scenario: DeploymentDemoScenario
    let close: () -> Void
    let openGuide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DashboardTheme.Spacing.compact) {
            DeploymentDemoRibbonView(compact: true)
            Label("Demo Complete", systemImage: "checkmark.seal")
                .font(.headline)
            Text(scenario.expectedResult)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Dummy data only. No live Jamf actions. External data changed: No.")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DashboardTheme.accent)
            HStack {
                Button {
                    openGuide()
                } label: {
                    Label("Open Guide", systemImage: "questionmark.circle")
                }
                Button {
                    close()
                } label: {
                    Label("Close", systemImage: "xmark")
                }
            }
        }
        .padding(14)
        // maxWidth so the completion card shrinks on narrow iPhones rather than
        // overflowing as a bottom-trailing overlay.
        .frame(maxWidth: 340, alignment: .leading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DashboardTheme.border, lineWidth: 1)
        }
        .shadow(radius: 12, y: 4)
        .padding(DashboardTheme.Spacing.section)
    }
}

private struct DeploymentDemoFact: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(DashboardTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
