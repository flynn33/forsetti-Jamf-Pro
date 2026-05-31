import SwiftUI
import UniformTypeIdentifiers

/// A `FileDocument` that wraps pre-rendered diagnostics bytes for SwiftUI's
/// `.fileExporter` modifier. The content type (JSON or plain text) is carried
/// alongside the data so the same document type can back any of the four
/// export artifacts (JSON report, Markdown report, error log NDJSON, telemetry
/// log NDJSON) through one exporter.
struct DiagnosticsExportDocument: FileDocument {
    var data: Data
    var contentType: UTType

    static var readableContentTypes: [UTType] { [.json, .text, .plainText] }
    static var writableContentTypes: [UTType] { [.json, .text, .plainText] }

    init(data: Data, contentType: UTType) {
        self.data = data
        self.contentType = contentType
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
        self.contentType = configuration.contentType
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// A full-screen view that presents diagnostic events recorded by the framework.
///
/// The `.fileExporter` state lives entirely in this view as plain `@State`.
/// The view model is asked to prepare the bytes (which it does asynchronously),
/// the returned document is placed in `@State`, and ONLY THEN is
/// `isExporterPresented` flipped to `true`. Presentation parameters are stable
/// at the moment SwiftUI reads them, with no cross-actor binding in the path.
/// This eliminates the crash class where a `@Published` document reference on
/// the view model could mutate between presentation and completion callbacks.
///
/// A single `.fileExporter` serves all four flows (JSON / Markdown / error log
/// / telemetry log). Stacking multiple `.fileExporter` modifiers on the same
/// view hierarchy is a known SwiftUI footgun — only the first one presents.
struct DiagnosticsView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel: DiagnosticsViewModel

    // MARK: - Export state (owned entirely by this view)

    /// The document currently armed for export. Non-nil implies
    /// `isExporterPresented` is (about to be) true. Set atomically with
    /// `exportFilename`, `exportContentType`, and `exportDescription` before
    /// presentation.
    @State private var exportDocument: DiagnosticsExportDocument?
    /// Default filename for the save panel.
    @State private var exportFilename: String = ForsettiAppIdentity.diagnosticsFilePrefix
    /// Declared content type for the save panel's file filter.
    @State private var exportContentType: UTType = .plainText
    /// Short label used in the completion status message.
    @State private var exportDescription: String = "export"
    /// Flips true when all the above are ready, which SwiftUI observes to
    /// present the file exporter.
    @State private var isExporterPresented: Bool = false

    init(viewModel: DiagnosticsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Actions") {
                    VStack(spacing: ForsettiTheme.Spacing.item) {
                        Button {
                            Task { await viewModel.refresh() }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.forsettiSecondary)

                        Button {
                            triggerExport { await viewModel.prepareJSONExport() }
                        } label: {
                            Label("Export JSON…", systemImage: "square.and.arrow.down")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.forsettiPrimary)

                        Button {
                            triggerExport { await viewModel.prepareMarkdownExport() }
                        } label: {
                            Label("Export Markdown…", systemImage: "doc.richtext")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.forsettiSecondary)

                        if viewModel.canCheckTokenPrivileges {
                            Button {
                                Task { await viewModel.checkTokenPrivileges() }
                            } label: {
                                Label(
                                    viewModel.isCheckingTokenPrivileges ? "Checking…" : "Check Token Privileges",
                                    systemImage: "key.viewfinder"
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.forsettiSecondary)
                            .disabled(viewModel.isCheckingTokenPrivileges)
                        }

                        Button(role: .destructive) {
                            Task { await viewModel.clearLog() }
                        } label: {
                            Label("Clear Log", systemImage: "trash")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.forsettiDanger)
                    }
                    .padding(.vertical, 4)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowBackground(Color.clear)
                }

                if let statusMessage = viewModel.statusMessage {
                    Section {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if let logURL = viewModel.persistentLogFileURL {
                    Section("Persistent Log") {
                        // Every reported event is appended to this
                        // NDJSON file as it happens — survives app
                        // quits and crashes. 10 MB size cap with three
                        // rotated generations kept.
                        VStack(alignment: .leading, spacing: 4) {
                            Text("File:")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(logURL.path)
                                .font(.caption2.monospaced())
                                .textSelection(.enabled)
                        }

                        ShareLink(item: logURL) {
                            Label("Share Persistent Log", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.forsettiSecondary)

                        // Unified-log fallback for cross-session
                        // context beyond what the NDJSON file holds.
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Command-line access (unified log):")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("log show --subsystem \(ForsettiAppIdentity.diagnosticsSubsystem) --info --last 1d")
                                .font(.caption2.monospaced())
                                .textSelection(.enabled)
                        }
                    }
                }

                if viewModel.tokenPrivileges.isEmpty == false {
                    Section {
                        ForEach(viewModel.tokenPrivileges, id: \.self) { privilege in
                            Text(privilege)
                                .font(.caption)
                                .textSelection(.enabled)
                        }
                    } header: {
                        HStack {
                            Text("Token Privileges (\(viewModel.tokenPrivileges.count))")
                            Spacer()
                            if let checkedAt = viewModel.tokenPrivilegesCheckedAt {
                                Text(checkedAt, style: .time)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .textCase(nil)
                            }
                        }
                    }
                }

                Section("Diagnostic Entries") {
                    if viewModel.entries.isEmpty {
                        Text("No diagnostic events recorded.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.entries) { entry in
                            DiagnosticEntryRow(entry: entry)
                        }
                    }
                }
            }
            .forsettiInsetGroupedListStyle()
            .navigationTitle("Diagnostics")
            .forsettiInlineNavigationTitle()
            .toolbar {
                // Apple HIG semantic sheet dismiss — .confirmationAction is
                // the placement Apple's modal dismiss buttons use in Mail,
                // Calendar, Settings, Notes. Renders as blue primary (macOS,
                // Enter-activated) / bold trailing (iOS).
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await viewModel.refresh()
            }
            .alert(
                "Diagnostics Error",
                isPresented: Binding(
                    get: { viewModel.errorMessage != nil },
                    set: { isPresented in
                        if isPresented == false {
                            viewModel.errorMessage = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.errorMessage ?? "Unknown error")
            }
            // Single `.fileExporter` bound to pure `@State` values owned by
            // this view. At the moment SwiftUI reads these during
            // presentation, they are guaranteed non-nil and internally
            // consistent — `triggerExport` sets them all then flips the bool.
            // The completion handler clears them in the same order.
            .fileExporter(
                isPresented: $isExporterPresented,
                document: exportDocument,
                contentType: exportContentType,
                defaultFilename: exportFilename
            ) { result in
                let description = exportDescription
                // Clear the document reference promptly so the next export
                // can be armed fresh. The other fields are reset the next
                // time `triggerExport` runs.
                exportDocument = nil
                viewModel.recordExportCompletion(result: result, description: description)
            }
        }
    }

    /// Runs the given async preparer on the view model, then atomically sets
    /// the four export state fields and flips `isExporterPresented` so
    /// SwiftUI presents the save panel.
    ///
    /// All state writes happen synchronously on the main actor after the
    /// async preparer returns, so `.fileExporter` sees a consistent
    /// (document + filename + contentType) tuple during presentation.
    private func triggerExport(prepare: @escaping () async -> DiagnosticsViewModel.PreparedExport?) {
        Task { @MainActor in
            guard let prepared = await prepare() else {
                // The VM has already set errorMessage; nothing more to do.
                return
            }
            exportDocument = DiagnosticsExportDocument(
                data: prepared.data,
                contentType: prepared.contentType
            )
            exportFilename = prepared.filename
            exportContentType = prepared.contentType
            exportDescription = prepared.description
            isExporterPresented = true
        }
    }
}

private struct DiagnosticEntryRow: View {
    let entry: DiagnosticEvent

    private var severityColor: Color {
        switch entry.severity {
        case .info:    return ForsettiColors.bluePrimary
        case .warning: return .orange
        case .error:   return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.severity.rawValue.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(severityColor)

                Spacer()

                Text(entry.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(entry.message)
                .font(.subheadline)

            Text("\(entry.source) • \(entry.category)")
                .font(.caption)
                .foregroundStyle(.secondary)

            if entry.metadata.isEmpty == false {
                ForEach(entry.metadata.keys.sorted(), id: \.self) { key in
                    if let value = entry.metadata[key] {
                        Text("\(key): \(value)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

//endofline
