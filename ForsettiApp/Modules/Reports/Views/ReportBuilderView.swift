import SwiftUI

struct ReportBuilderView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ReportRequest.blankBuilder
    @State private var validationErrors: [String] = []

    let isGenerating: Bool
    let onGenerate: (ReportRequest) async -> Void

    // The builder follows the same `List` + `.forsettiInsetGroupedListStyle()` +
    // sticky `.forsettiBottomBarSurface()` bottom bar pattern that `Advanced
    // Search` (and the other complex modal sheets in the app) already use.
    // Form gave the picker labels and the multi-line Frames toggles a
    // cramped, asymmetric layout on macOS; List with the standard inset-
    // grouped style renders cleanly on both platforms and the bottom bar
    // keeps the Generate Report action persistently visible without
    // competing with the form content for vertical space.
    var body: some View {
        NavigationStack {
            List {
                reportSection
                framesSection
                criteriaSection
            }
            .forsettiInsetGroupedListStyle()
            .navigationTitle("New Report")
            .forsettiInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .forsettiTopBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomBar
            }
        }
#if os(macOS)
        // Matches the established sheet sizing used by `AdvancedSearchView`,
        // `AdvancedFieldPickerView`, and the field-catalog sheets. List +
        // sticky bottom bar is space-efficient on macOS, so these numbers
        // are comfortable without being oversized; operators can drag the
        // sheet larger if they like.
        .frame(minWidth: 760, idealWidth: 880, minHeight: 660, idealHeight: 780)
#endif
    }

    // MARK: - Sections

    @ViewBuilder
    private var reportSection: some View {
        Section("Report") {
            TextField("Report name", text: $draft.name)
            Picker("Device Domain", selection: $draft.domain) {
                ForEach(ReportDeviceDomain.allCases) { domain in
                    Text(domain.displayName).tag(domain)
                }
            }
            Picker("Group By", selection: $draft.grouping) {
                ForEach(ReportGrouping.allCases) { grouping in
                    Text(grouping.displayName).tag(grouping)
                }
            }
            Picker("Visual", selection: $draft.chartPreference) {
                ForEach(ReportChartPreference.allCases) { preference in
                    Text(preference.displayName).tag(preference)
                }
            }
        }
    }

    @ViewBuilder
    private var framesSection: some View {
        Section {
            ForEach(ReportFrame.displayOrder) { frame in
                Toggle(isOn: frameBinding(for: frame)) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(frame.displayName)
                        Text(frame.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Frames")
        } footer: {
            Text("Selected frames appear on the generated report page. Storage and Battery are off by default.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var criteriaSection: some View {
        Section {
            if draft.criteria.isEmpty {
                Text("No criteria selected.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach($draft.criteria) { $criterion in
                    ReportCriterionEditorRow(
                        criterion: $criterion,
                        availableFields: ReportsFieldCatalog.fields(for: draft.domain)
                    )
                }
                .onDelete { offsets in
                    draft.criteria.remove(atOffsets: offsets)
                }
            }

            Button {
                draft.criteria.append(
                    ReportCriterion(
                        fieldKey: ReportsFieldCatalog.fields(for: draft.domain).first?.key ?? "deviceType",
                        comparison: .equals,
                        value: ""
                    )
                )
            } label: {
                Label("Add Criteria", systemImage: "plus")
            }
        } header: {
            Text("Criteria")
        }
    }

    // MARK: - Sticky bottom bar

    /// The bottom bar carries any validation errors above the primary
    /// **Generate Report** action so the operator sees what failed without
    /// losing the button. Mirrors the pattern used by Advanced Search.
    @ViewBuilder
    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            if validationErrors.isEmpty == false {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(validationErrors, id: \.self) { error in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(error)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }

            Button {
                generate()
            } label: {
                HStack(spacing: 8) {
                    if isGenerating {
                        ProgressView()
                        Text("Generating Report\u{2026}")
                    } else {
                        Image(systemName: "chart.pie.fill")
                        Text("Generate Report")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.forsettiPrimary)
            .disabled(isGenerating)
        }
        .padding(16)
        .forsettiBottomBarSurface()
    }

    // MARK: - Helpers

    private func generate() {
        validationErrors = ReportsQueryPlanner.validate(draft)
        guard validationErrors.isEmpty else { return }
        Task { await onGenerate(draft) }
    }

    /// Bridges `draft.frames` (a `Set<ReportFrame>`) into the `Bool` API
    /// `Toggle` wants. Insert / remove keeps `draft.frames` minimal so the
    /// `Codable` round-trip stays small.
    private func frameBinding(for frame: ReportFrame) -> Binding<Bool> {
        Binding(
            get: { draft.frames.contains(frame) },
            set: { isOn in
                if isOn {
                    draft.frames.insert(frame)
                } else {
                    draft.frames.remove(frame)
                }
            }
        )
    }
}

private struct ReportCriterionEditorRow: View {
    @Binding var criterion: ReportCriterion
    let availableFields: [ReportField]

    private var selectedField: ReportField {
        ReportsFieldCatalog.field(for: criterion.fieldKey) ?? availableFields.first ?? ReportsFieldCatalog.fields[0]
    }

    private var comparisons: [ReportComparison] {
        ReportComparison.allCases.filter { $0.supports(selectedField.dataType) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Field", selection: $criterion.fieldKey) {
                ForEach(availableFields) { field in
                    Text(field.displayName).tag(field.key)
                }
            }

            Picker("Comparison", selection: $criterion.comparison) {
                ForEach(comparisons) { comparison in
                    Text(comparison.displayName).tag(comparison)
                }
            }

            if criterion.comparison.requiresValue {
                valueEditor
            }
        }
        .onChange(of: criterion.fieldKey) { _, _ in
            if criterion.comparison.supports(selectedField.dataType) == false {
                criterion.comparison = comparisons.first ?? .equals
            }
            criterion.value = defaultValue(for: selectedField)
        }
    }

    @ViewBuilder
    private var valueEditor: some View {
        switch selectedField.dataType {
        case .deviceType:
            Picker("Value", selection: $criterion.value) {
                ForEach(ReportDeviceType.displayOrder, id: \.self) { type in
                    Text(type.displayName).tag(type.displayName)
                }
            }
        case .bool:
            Picker("Value", selection: $criterion.value) {
                Text("True").tag("true")
                Text("False").tag("false")
            }
        default:
            TextField("Value", text: $criterion.value)
                .forsettiNoAutoCorrectionTextInput()
        }
    }

    private func defaultValue(for field: ReportField) -> String {
        switch field.dataType {
        case .deviceType: return ReportDeviceType.mac.displayName
        case .bool: return "true"
        case .integer, .decimal, .string: return ""
        }
    }
}
