import SwiftUI

struct ComputerAdvancedSearchView: View {
    @StateObject var viewModel: ComputerAdvancedSearchViewModel

    let onSearch: (JamfRSQLComposer.ComputerComposeResult, Set<String>) -> Void
    let onSaveSmartFilter: (SmartFilter) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.query.groups) { group in
                    groupSection(group: group)
                }

                Section {
                    Button {
                        viewModel.addGroup()
                    } label: {
                        Label("Add group", systemImage: "plus.rectangle.on.rectangle")
                    }

                    if viewModel.query.groups.count > 1 {
                        Picker("Join groups with", selection: Binding(
                            get: { viewModel.query.outerCombinator },
                            set: { viewModel.query.outerCombinator = $0 }
                        )) {
                            ForEach(LogicalCombinator.allCases, id: \.self) { combinator in
                                Text(combinator.displayName).tag(combinator)
                            }
                        }
                    }
                }
            }
            .forsettiInsetGroupedListStyle()
            .navigationTitle("Advanced Search")
            .forsettiInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .forsettiTopBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .forsettiTopBarTrailing) {
                    Button("Save Filter") {
                        viewModel.pendingSmartFilterName = ""
                        viewModel.isSaveSmartFilterPromptPresented = true
                    }
                    .disabled(viewModel.query.isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) {
                bottomBar
            }
        }
        .alert("Save Smart Filter", isPresented: $viewModel.isSaveSmartFilterPromptPresented) {
            TextField("Filter name", text: $viewModel.pendingSmartFilterName)
            Button("Cancel", role: .cancel) { }
            Button("Save") {
                if let snapshot = viewModel.snapshotForSaving() {
                    onSaveSmartFilter(snapshot)
                }
            }
        } message: {
            Text("Saved filters appear in the Smart Filters list.")
        }
        #if os(macOS)
        .frame(minWidth: 720, idealWidth: 820, minHeight: 600, idealHeight: 720)
        #endif
    }

    @ViewBuilder
    private func groupSection(group: AdvancedQueryGroup) -> some View {
        Section {
            ForEach(group.criteria) { criterion in
                ComputerCriterionEditorRow(
                    criterion: criterion,
                    fieldLookup: viewModel.fieldLookup,
                    availableFields: viewModel.availableFields,
                    onChange: viewModel.updateCriterion,
                    onRemove: { viewModel.removeCriterion(id: criterion.id) },
                    defaultValueProvider: viewModel.defaultValue
                )
            }

            HStack {
                Button {
                    viewModel.addCriterion(toGroup: group.id)
                } label: {
                    Label("Add criterion", systemImage: "plus.circle")
                }
                Spacer()
                if viewModel.query.groups.count > 1 {
                    Button(role: .destructive) {
                        viewModel.removeGroup(id: group.id)
                    } label: {
                        Label("Remove group", systemImage: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }
        } header: {
            HStack {
                Text("Match")
                Picker("Combinator", selection: Binding(
                    get: { group.combinator },
                    set: { newValue in
                        guard let index = viewModel.query.groups.firstIndex(where: { $0.id == group.id }) else { return }
                        viewModel.query.groups[index].combinator = newValue
                    }
                )) {
                    ForEach(LogicalCombinator.allCases, id: \.self) { combinator in
                        Text(combinator.displayName).tag(combinator)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 160)
                Text("of these conditions")
            }
            .font(.subheadline)
            .textCase(nil)
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let validation = viewModel.validationMessage {
                Text(validation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button {
                onSearch(viewModel.compose(), viewModel.selectedFieldKeys)
            } label: {
                Label("Search", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.forsettiPrimary)
            .disabled(viewModel.query.isEmpty || viewModel.isSearching)
        }
        .padding(16)
        .forsettiBottomBarSurface()
    }
}

private struct ComputerCriterionEditorRow: View {
    let criterion: AdvancedQueryCriterion
    let fieldLookup: [String: ComputerField]
    let availableFields: [ComputerField]
    let onChange: (AdvancedQueryCriterion) -> Void
    let onRemove: () -> Void
    let defaultValueProvider: (MobileDeviceFieldDataType, RSQLOperator) -> AdvancedQueryValue

    private var field: ComputerField? {
        fieldLookup[criterion.fieldKey]
    }

    private var dataType: MobileDeviceFieldDataType {
        field?.dataType ?? .string
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Picker("Field", selection: Binding(
                    get: { criterion.fieldKey },
                    set: updateField
                )) {
                    ForEach(availableFields.filter(\.isFilterable)) { field in
                        Text(field.displayName).tag(field.key)
                    }
                }
                .pickerStyle(.menu)

                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove criterion")
            }

            HStack(spacing: 8) {
                operatorPicker
                valueControl
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var operatorPicker: some View {
        Picker("Operator", selection: Binding(
            get: { criterion.op },
            set: { newOp in
                var updated = criterion
                updated.op = newOp
                if shouldResetValue(forOp: newOp, value: updated.value) {
                    updated.value = defaultValueProvider(dataType, newOp)
                }
                onChange(updated)
            }
        )) {
            ForEach(dataType.supportedOperators, id: \.self) { op in
                Text(op.displayName).tag(op)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(maxWidth: 180, alignment: .leading)
    }

    @ViewBuilder
    private var valueControl: some View {
        if criterion.op.requiresValue == false {
            Text(criterion.op == .isTrue ? "true" : "false")
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            switch criterion.op {
            case .between:
                dateRangeFields
            case .before, .after, .on:
                dateField
            case .includedIn, .excludedFrom:
                listField
            default:
                switch dataType {
                case .integer, .double:
                    numericTextField
                case .bool:
                    Toggle("", isOn: Binding(
                        get: {
                            if case .bool(let value) = criterion.value { return value }
                            return false
                        },
                        set: { newValue in
                            var updated = criterion
                            updated.value = .bool(newValue)
                            onChange(updated)
                        }
                    ))
                    .labelsHidden()
                default:
                    stringTextField
                }
            }
        }
    }

    @ViewBuilder
    private var stringTextField: some View {
        if let allowedValues = field?.allowedValues, allowedValues.isEmpty == false {
            Picker("Value", selection: Binding(
                get: {
                    if case .string(let value) = criterion.value { return value }
                    return allowedValues.first ?? ""
                },
                set: { newValue in
                    var updated = criterion
                    updated.value = .string(newValue)
                    onChange(updated)
                }
            )) {
                ForEach(allowedValues, id: \.self) { value in
                    Text(value).tag(value)
                }
            }
            .pickerStyle(.menu)
        } else {
            TextField("Value", text: Binding(
                get: {
                    if case .string(let value) = criterion.value { return value }
                    return ""
                },
                set: { newValue in
                    var updated = criterion
                    updated.value = .string(newValue)
                    onChange(updated)
                }
            ))
            .textFieldStyle(.roundedBorder)
        }
    }

    @ViewBuilder
    private var numericTextField: some View {
        TextField("Number", text: Binding(
            get: {
                switch criterion.value {
                case .int(let value): return String(value)
                case .double(let value): return String(value)
                case .string(let value): return value
                default: return ""
                }
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                var updated = criterion
                if dataType == .integer, let value = Int(trimmed) {
                    updated.value = .int(value)
                } else if dataType == .double, let value = Double(trimmed) {
                    updated.value = .double(value)
                } else {
                    updated.value = .string(trimmed)
                }
                onChange(updated)
            }
        ))
        .textFieldStyle(.roundedBorder)
    }

    @ViewBuilder
    private var dateField: some View {
        DatePicker(
            "",
            selection: Binding(
                get: {
                    if case .date(let value) = criterion.value { return value }
                    return Date()
                },
                set: { newValue in
                    var updated = criterion
                    updated.value = .date(newValue)
                    onChange(updated)
                }
            ),
            displayedComponents: [.date]
        )
        .labelsHidden()
    }

    @ViewBuilder
    private var dateRangeFields: some View {
        let initialStart: Date = {
            if case .dateRange(let start, _) = criterion.value { return start }
            return Date().addingTimeInterval(-86_400)
        }()
        let initialEnd: Date = {
            if case .dateRange(_, let end) = criterion.value { return end }
            return Date()
        }()

        VStack(alignment: .leading, spacing: 6) {
            DatePicker("From", selection: Binding(
                get: { initialStart },
                set: { newStart in
                    var updated = criterion
                    updated.value = .dateRange(newStart, initialEnd)
                    onChange(updated)
                }
            ), displayedComponents: [.date])

            DatePicker("To", selection: Binding(
                get: { initialEnd },
                set: { newEnd in
                    var updated = criterion
                    updated.value = .dateRange(initialStart, newEnd)
                    onChange(updated)
                }
            ), displayedComponents: [.date])
        }
    }

    @ViewBuilder
    private var listField: some View {
        TextField("Comma-separated values", text: Binding(
            get: {
                if case .list(let values) = criterion.value {
                    return values.joined(separator: ", ")
                }
                return ""
            },
            set: { newValue in
                let parts = newValue
                    .split(separator: ",", omittingEmptySubsequences: false)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                var updated = criterion
                updated.value = .list(parts)
                onChange(updated)
            }
        ))
        .textFieldStyle(.roundedBorder)
    }

    private func updateField(_ key: String) {
        guard let newField = fieldLookup[key] else { return }
        var updated = criterion
        updated.fieldKey = newField.key
        let supported = newField.dataType.supportedOperators
        if supported.contains(updated.op) == false {
            updated.op = supported.first ?? .equals
        }
        if shouldResetValue(for: newField.dataType, value: updated.value) {
            updated.value = defaultValueProvider(newField.dataType, updated.op)
        }
        onChange(updated)
    }

    private func shouldResetValue(for dataType: MobileDeviceFieldDataType, value: AdvancedQueryValue) -> Bool {
        switch (dataType, value) {
        case (.string, .string), (.enumeration, .string):
            return false
        case (.integer, .int), (.integer, .string):
            return false
        case (.double, .double), (.double, .string), (.double, .int):
            return false
        case (.bool, .bool):
            return false
        case (.date, .date), (.date, .dateRange):
            return false
        default:
            return true
        }
    }

    private func shouldResetValue(forOp newOp: RSQLOperator, value: AdvancedQueryValue) -> Bool {
        switch newOp {
        case .between:
            if case .dateRange = value { return false }
            return true
        case .before, .after, .on:
            if case .date = value { return false }
            return true
        case .includedIn, .excludedFrom:
            if case .list = value { return false }
            return true
        case .isTrue, .isFalse:
            return false
        default:
            return false
        }
    }
}
