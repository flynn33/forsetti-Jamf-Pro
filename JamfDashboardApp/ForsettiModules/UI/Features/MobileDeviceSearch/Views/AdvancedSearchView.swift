import SwiftUI

// "A robot may not injure a human being or, through inaction, allow a human being to come to harm.
//  A robot must obey the orders given it by human beings except where such orders would conflict with the First Law.
//  A robot must protect its own existence as long as such protection does not conflict with the First or Second Law."

/// Sheet that hosts the Advanced Search builder.
///
/// Layout: a List of group sections — each group has a combinator picker and
/// rows for its criteria — followed by an outer-combinator picker if there
/// is more than one group, and a sticky bottom bar with the live RSQL
/// preview plus the Search and Save Smart Filter actions.
struct AdvancedSearchView: View {
    @StateObject var viewModel: AdvancedSearchViewModel

    /// Called with the composed result when the user hits Search. The parent
    /// search view model handles the actual API call.
    let onSearch: (JamfRSQLComposer.ComposeResult, Set<String>) -> Void

    /// Called with the named smart filter when the user hits Save. The
    /// parent persists it via `SmartFilterStore`.
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
                                Text("\(combinator.displayName) (\(combinator == .and ? "AND" : "OR"))").tag(combinator)
                            }
                        }
                    }
                }
            }
            .dashboardInsetGroupedListStyle()
            .navigationTitle("Advanced Search")
            .dashboardInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .dashboardTopBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .dashboardTopBarTrailing) {
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

    // MARK: - Group section

    @ViewBuilder
    private func groupSection(group: AdvancedQueryGroup) -> some View {
        Section {
            ForEach(group.criteria) { criterion in
                CriterionEditorRow(
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

    // MARK: - Bottom bar

    @ViewBuilder
    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            // RSQL preview removed from the user-visible UI — keep validation
            // hints only. The composed query is still logged to Diagnostics
            // for support purposes; the bottom bar stays focused on the
            // Search action.

            if let validation = viewModel.validationMessage {
                Text(validation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Button {
                let result = viewModel.compose()
                onSearch(result, viewModel.selectedFieldKeys)
            } label: {
                Label("Search", systemImage: "magnifyingglass")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.dashboardPrimary)
            .disabled(viewModel.query.isEmpty || viewModel.isSearching)
        }
        .padding(16)
        .dashboardBottomBarSurface()
    }
}

//endofline
