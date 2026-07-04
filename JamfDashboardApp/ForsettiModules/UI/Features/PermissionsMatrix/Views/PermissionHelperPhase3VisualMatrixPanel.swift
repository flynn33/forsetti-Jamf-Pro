import SwiftUI

// Visual Hierarchy panel.
//
// A crisp, deterministic, native-SwiftUI tiered flow diagram: the selected item and
// its two tracks (privilege groups → privileges, and endpoint families → endpoints)
// laid out as premium cards joined by clean connectors. Sharp at any zoom. Mounted
// to the right of the permissions column on the command and privilege screens.
struct PermissionHelperPhase3VisualMatrixPanel: View {
    @ObservedObject var viewModel: PermissionsMatrixViewModel
    /// Explicit diagram height for stacked, scrolling layouts (iPhone / iPad
    /// portrait), where the panel lives inside a vertical ScrollView and must not
    /// be greedy. When `nil` the diagram fills the available height (wide
    /// side-by-side layouts), bounded by its row.
    var diagramHeight: CGFloat? = nil

    @State private var showEndpoints = true
    @State private var showRuntime = true
    @State private var diagramCommand: PermissionGraphDiagramCommand?

    private var snapshot: PermissionGraphSceneSnapshot? {
        viewModel.graphSnapshot.map(filtered)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: PHMetrics.gap) {
            header
            warningsBanner
            graphFrame
            legendBar
        }
    }

    // MARK: - Header / control bar

    /// Title + controls on one row when there's room; otherwise the controls wrap
    /// onto their own row below the title. `ViewThatFits` keys off the panel's
    /// actual width, so this is correct at any size class / orientation.
    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 12) {
                titleBlock
                Spacer(minLength: 8)
                controlBar.fixedSize()
            }
            VStack(alignment: .leading, spacing: 8) {
                titleBlock
                controlBar
            }
        }
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("Visual Hierarchy").font(.headline)
            Text("Selected item → privilege groups → privileges → endpoint families → endpoints.")
                .font(.caption).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.85)
        }
    }

    /// All controls share `.bordered` + `.controlSize(.small)` so heights/baselines
    /// match exactly. Laid out with `FlowLayout` so the row wraps on narrow widths
    /// (compact / iPhone) instead of clipping.
    private var controlBar: some View {
        FlowLayout(spacing: 6, rowSpacing: 6) {
            PHToggleChip(label: "Endpoints", systemImage: "network", isOn: $showEndpoints)
            PHToggleChip(label: "Runtime", systemImage: "checkmark.shield", isOn: $showRuntime)
            PHIconButton(label: "Fit", systemImage: "arrow.up.left.and.arrow.down.right", action: fit)
            PHIconButton(label: "Reset", systemImage: "arrow.counterclockwise", action: reset)
            PHIconButton(label: "Copy selected", systemImage: "doc.on.doc", action: copySelected)
                .disabled(viewModel.selectedGraphNodeID == nil)
        }
        .disabled(viewModel.graphSnapshot == nil)
    }

    // MARK: - Warnings banner

    @ViewBuilder
    private var warningsBanner: some View {
        if let warnings = viewModel.graphSnapshot?.warnings, warnings.isEmpty == false {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(PermissionGraphStyle.riskAmber)
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(warnings) { warning in
                        VStack(alignment: .leading, spacing: 0) {
                            Text(warning.title).font(.caption2.weight(.semibold)).foregroundStyle(.primary)
                            Text(warning.detail).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(PermissionGraphStyle.riskAmber.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(PermissionGraphStyle.riskAmber.opacity(0.35), lineWidth: 1)
            )
        }
    }

    // MARK: - Graph frame

    private var graphFrame: some View {
        ZStack {
            frameBackground
            if let snapshot {
                PermissionGraphDiagramView(
                    snapshot: snapshot,
                    layout: PermissionGraphDiagramLayout.make(snapshot, showRuntime: showRuntime),
                    selectedNodeID: $viewModel.selectedGraphNodeID,
                    showRuntime: showRuntime,
                    command: $diagramCommand,
                    // In a stacked, fixed-height embed the page owns vertical scrolling.
                    scrollEnabled: diagramHeight == nil
                )
            } else {
                emptyState
            }
        }
        // Fill the available height when laid out side-by-side (diagramHeight nil),
        // or take a definite height when embedded in a stacked scroll. Never both
        // greedy + min-height, which is what let the panel overflow on iPad.
        .frame(maxWidth: .infinity, maxHeight: diagramHeight == nil ? .infinity : nil)
        .frame(height: diagramHeight)
        .clipShape(RoundedRectangle(cornerRadius: DashboardTheme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DashboardTheme.Radius.card, style: .continuous)
                .strokeBorder(DashboardColors.blueSecondary.opacity(0.35), lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) { inspector.padding(12) }
        // The diagram surfaces are intentionally dark gradients — pin the subtree to
        // dark so adaptive text stays legible in Light Mode too.
        .environment(\.colorScheme, .dark)
        .onChange(of: viewModel.graphSnapshot?.selectedItemID) { _, _ in diagramCommand = .fit }
        .onChange(of: showEndpoints) { _, _ in pruneSelectionIfFiltered(); diagramCommand = .fit }
        .onChange(of: showRuntime) { _, _ in pruneSelectionIfFiltered(); diagramCommand = .fit }
    }

    private var frameBackground: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.07, blue: 0.12), Color(red: 0.02, green: 0.03, blue: 0.06)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [DashboardColors.bluePrimary.opacity(0.12), .clear],
                center: .topLeading, startRadius: 8, endRadius: 520
            )
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.largeTitle).foregroundStyle(.secondary)
            Text("Select a command, endpoint, or privilege").font(.headline)
            Text("The visual hierarchy maps its privilege groups, privileges, endpoint families, endpoints, and runtime state.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspector: some View {
        if let snap = snapshot, let id = viewModel.selectedGraphNodeID, let node = snap.node(id: id) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: PermissionGraphStyle.symbol(kind: node.kind))
                        .foregroundStyle(PermissionGraphStyle.color(status: node.runtimeStatus, kind: node.kind))
                    Text(node.title).font(.callout.weight(.semibold)).lineLimit(2)
                }
                HStack(spacing: 6) {
                    Text(PermissionGraphStyle.kindLabel(node.kind))
                        .font(.caption2).foregroundStyle(.secondary)
                    if node.runtimeStatus != .notChecked {
                        Label(PermissionGraphStyle.statusLabel(node.runtimeStatus),
                              systemImage: PermissionGraphStyle.statusSymbol(node.runtimeStatus))
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(PermissionGraphStyle.color(status: node.runtimeStatus, kind: node.kind))
                    }
                }
                if let detail = node.detail, detail != node.title {
                    Text(detail).font(.caption.monospaced()).textSelection(.enabled)
                        .foregroundStyle(.secondary).lineLimit(3)
                }
                Button { DashboardClipboard.copy(node.detail ?? node.title) } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderless).controlSize(.small)
            }
            .padding(12)
            .frame(maxWidth: 300, alignment: .leading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(DashboardColors.blueSecondary.opacity(0.3), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 10, y: 4)
        }
    }

    // MARK: - Legend + runtime summary

    private var legendBar: some View {
        HStack(spacing: 12) {
            if let entries = viewModel.graphSnapshot?.legend, entries.isEmpty == false {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(entries) { entry in
                            HStack(spacing: 4) {
                                Image(systemName: entry.symbolName).font(.caption2)
                                    .foregroundStyle(entry.runtimeStatus.map { PermissionGraphStyle.color(status: $0, kind: .privilege) } ?? .secondary)
                                Text(entry.label).font(.caption2).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule(style: .continuous).fill(Color.primary.opacity(0.06)))
                        }
                    }
                }
            }
            Spacer()
            if let summary = viewModel.graphSnapshot?.runtimeSummary, summary.hasLiveData {
                HStack(spacing: 10) {
                    summaryChip("checkmark.circle.fill", summary.available, PermissionGraphStyle.color(status: .available, kind: .privilege))
                    summaryChip("xmark.octagon.fill", summary.missing, PermissionGraphStyle.color(status: .missing, kind: .privilege))
                    summaryChip("questionmark.circle", summary.unknown, PermissionGraphStyle.color(status: .unknown, kind: .privilege))
                }
            }
        }
    }

    private func summaryChip(_ symbol: String, _ count: Int, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: symbol).font(.caption2)
            Text("\(count)").font(.caption2.weight(.semibold).monospacedDigit())
        }
        .foregroundStyle(color)
    }

    // MARK: - Actions

    private func fit() { diagramCommand = .fit }

    private func reset() {
        viewModel.selectedGraphNodeID = nil
        diagramCommand = .reset
    }

    private func copySelected() {
        guard let id = viewModel.selectedGraphNodeID, let node = viewModel.graphSnapshot?.node(id: id) else { return }
        DashboardClipboard.copy(node.detail ?? node.title)
    }

    /// Clear the selection if the toolbar toggles filtered the selected node out of
    /// the diagram, so the inspector never describes a node that is no longer shown.
    private func pruneSelectionIfFiltered() {
        guard let id = viewModel.selectedGraphNodeID else { return }
        if snapshot?.node(id: id) == nil { viewModel.selectedGraphNodeID = nil }
    }

    /// Apply the endpoint / runtime toolbar toggles by dropping those node kinds.
    private func filtered(_ snapshot: PermissionGraphSceneSnapshot) -> PermissionGraphSceneSnapshot {
        if showEndpoints && showRuntime { return snapshot }
        var dropKinds: Set<PermissionGraphNodeKind> = []
        if showEndpoints == false { dropKinds.formUnion([.endpoint, .endpoint_family, .command_overlay]) }
        if showRuntime == false { dropKinds.formUnion([.runtime_status, .risk_flag]) }
        var s = snapshot
        let keep = Set(s.nodes.filter { dropKinds.contains($0.kind) == false }.map(\.id))
        s.nodes = s.nodes.filter { keep.contains($0.id) }
        s.edges = s.edges.filter { keep.contains($0.fromNodeID) && keep.contains($0.toNodeID) }
        return s
    }
}
