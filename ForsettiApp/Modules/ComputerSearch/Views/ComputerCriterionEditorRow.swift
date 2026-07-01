import SwiftUI

// "End of Line"

/// One editable row in the computer Advanced Search builder: a field picker,
/// an operator picker, and a typed value control.
///
/// The value control switches based on the field's `dataType` AND the chosen
/// operator (between → two date pickers, isTrue/isFalse → no value, etc.).
/// Mutations are pushed back to the parent view model via `onChange`, which
/// updates the criterion in place and triggers RSQL preview regeneration.
///
/// Computer-side analogue of `CriterionEditorRow` (mobile); the only
/// difference is the field/data-type metadata type it reads.
struct ComputerCriterionEditorRow: View {
    let criterion: AdvancedQueryCriterion
    let fieldLookup: [String: ComputerField]
    let availableFields: [ComputerField]
    let onChange: (AdvancedQueryCriterion) -> Void
    let onRemove: () -> Void
    let defaultValueProvider: (ComputerFieldDataType, RSQLOperator) -> AdvancedQueryValue

    @State private var isFieldPickerPresented: Bool = false

    private var field: ComputerField? {
        fieldLookup[criterion.fieldKey]
    }

    private var dataType: ComputerFieldDataType {
        field?.dataType ?? .string
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                // Field picker — opens ComputerAdvancedFieldPickerView via sheet
                // so the search-and-group experience matches the FieldCatalog.
                Button {
                    isFieldPickerPresented = true
                } label: {
                    HStack {
                        Text(field?.displayName ?? criterion.fieldKey)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(DashboardTheme.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(role: .destructive) {
                    onRemove()
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove criterion")
            }

            // Operator + value row.
            HStack(spacing: 8) {
                operatorPicker
                valueControl
            }
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $isFieldPickerPresented) {
            ComputerAdvancedFieldPickerView(
                availableFields: availableFields,
                onSelect: { newField in
                    var updated = criterion
                    updated.fieldKey = newField.key

                    // If the current operator isn't valid for the new field's
                    // data type, fall back to the first supported operator.
                    let supported = newField.dataType.supportedOperators
                    if supported.contains(updated.op) == false {
                        updated.op = supported.first ?? .equals
                    }

                    // Reset the value if its case no longer matches the field's
                    // dataType — keeps the editor from sitting in unparseable
                    // state while the user is mid-edit.
                    if shouldResetValue(for: newField.dataType, value: updated.value) {
                        updated.value = defaultValueProvider(newField.dataType, updated.op)
                    }
                    onChange(updated)
                }
            )
        }
    }

    // MARK: - Operator picker

    @ViewBuilder
    private var operatorPicker: some View {
        let supported = dataType.supportedOperators
        Picker("Operator", selection: Binding(
            get: { criterion.op },
            set: { newOp in
                var updated = criterion
                updated.op = newOp

                // If switching operator changed the required value type
                // (e.g. equals -> between), reset to the appropriate default.
                if shouldResetValue(forOp: newOp, value: updated.value) {
                    updated.value = defaultValueProvider(dataType, newOp)
                }
                onChange(updated)
            }
        )) {
            ForEach(supported, id: \.self) { op in
                Text(op.displayName).tag(op)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(maxWidth: 180, alignment: .leading)
    }

    // MARK: - Value control

    @ViewBuilder
    private var valueControl: some View {
        if criterion.op.requiresValue == false {
            // Bool isTrue/isFalse have no editable value.
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

    @ViewBuilder
    private var numericTextField: some View {
        TextField("Number", text: Binding(
            get: {
                switch criterion.value {
                case .int(let n): return String(n)
                case .double(let n): return String(n)
                case .string(let s): return s
                default: return ""
                }
            },
            set: { newValue in
                var updated = criterion
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if dataType == .integer, let intValue = Int(trimmed) {
                    updated.value = .int(intValue)
                } else if dataType == .double, let dblValue = Double(trimmed) {
                    updated.value = .double(dblValue)
                } else {
                    // Keep the raw string while the user is typing — the
                    // composer treats unparseable numerics as nil and the
                    // criterion drops out of the RSQL output until valid.
                    updated.value = .string(trimmed)
                }
                onChange(updated)
            }
        ))
        .textFieldStyle(.roundedBorder)
#if os(iOS)
        .keyboardType(dataType == .integer ? .numberPad : .decimalPad)
#endif
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
        // Comma-separated input — splits into a string list that the composer
        // expands to the proper RSQL OR / AND chain. Keeps the editor compact;
        // a future pass could swap this for a chips / token field.
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

    // MARK: - Reset helpers

    /// Whether switching to `dataType` makes the current value case
    /// incompatible (e.g. moving from a string field to a date field while
    /// holding a `.string` value).
    private func shouldResetValue(for dataType: ComputerFieldDataType, value: AdvancedQueryValue) -> Bool {
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

    /// Whether switching to operator `newOp` requires a different value
    /// shape (e.g. moving to `.between` requires `.dateRange`).
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
            return false  // value is irrelevant
        default:
            return false
        }
    }
}

//endofline
