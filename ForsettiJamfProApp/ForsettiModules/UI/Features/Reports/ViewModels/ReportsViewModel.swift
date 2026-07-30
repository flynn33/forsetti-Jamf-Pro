import Foundation
import Combine

@MainActor
final class ReportsViewModel: ObservableObject {
    @Published private(set) var defaultDataSet: ReportDataSet?
    @Published private(set) var aggregate: ReportAggregate = .empty
    @Published private(set) var isRefreshing = false
    @Published private(set) var isGenerating = false
    @Published var errorMessage: String?
    @Published var statusMessage: String?

    private let inventoryService: ReportsInventoryService
    private let credentialsStore: JamfCredentialsStore
    private let diagnosticsReporter: any DiagnosticsReporting
    private let exportCoordinator = ReportExportCoordinator()
    private let source = "module.reports"

    init(
        inventoryService: ReportsInventoryService,
        credentialsStore: JamfCredentialsStore,
        diagnosticsReporter: any DiagnosticsReporting
    ) {
        self.inventoryService = inventoryService
        self.credentialsStore = credentialsStore
        self.diagnosticsReporter = diagnosticsReporter
    }

    var hasCredentials: Bool {
        // Demo mode unlocks reports against sample inventory without live credentials.
        JamfSessionAvailability.isAvailable(credentialsStore: credentialsStore)
    }

    var lastRefreshDate: Date? {
        defaultDataSet?.generatedAt
    }

    var serverLabel: String? {
        defaultDataSet?.serverLabel
    }

    /// Refreshes the dashboard counts and (if requested) discards the
    /// inventory service's cached snapshot so the next load re-fetches
    /// from Jamf Pro.
    ///
    /// - Parameter forceCacheRebuild: When `true` the cache is dropped
    ///   before the load runs. The toolbar Refresh button passes `true`
    ///   so the user sees fresh data; the auto-load on first appear
    ///   passes `false` so the (empty) cache populates without a
    ///   redundant invalidation.
    func refreshDefaultCounts(forceCacheRebuild: Bool = true) async {
        guard hasCredentials else {
            aggregate = .empty
            errorMessage = "No Jamf Pro credentials are configured. Open Settings from the dashboard and save verified credentials."
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            if forceCacheRebuild {
                await inventoryService.invalidateCache()
            }
            let dataSet = try await inventoryService.loadDefaultData()
            defaultDataSet = dataSet
            aggregate = dataSet.aggregate
            errorMessage = nil
            statusMessage = forceCacheRebuild ? "Counts refreshed." : "Counts loaded."
        } catch {
            errorMessage = "Failed to load report counts. \(describe(error))"
            statusMessage = nil
        }
    }

    func generateReport(request: ReportRequest) async -> GeneratedReport? {
        let validationErrors = ReportsQueryPlanner.validate(request)
        guard validationErrors.isEmpty else {
            errorMessage = validationErrors.joined(separator: " ")
            return nil
        }
        guard hasCredentials else {
            errorMessage = "No Jamf Pro credentials are configured. Open Settings from the dashboard and save verified credentials."
            return nil
        }

        isGenerating = true
        defer { isGenerating = false }

        do {
            let dataSet = try await inventoryService.loadReport(request: request)
            errorMessage = nil
            statusMessage = "Generated \(request.resolvedName)."
            return GeneratedReport(request: request, dataSet: dataSet)
        } catch {
            errorMessage = "Failed to generate report. \(describe(error))"
            return nil
        }
    }

    func prepareExport(format: ReportExportFormat, report: GeneratedReport) async -> ReportExportResult? {
        do {
            let payload = ReportExportPayload(
                request: report.request,
                dataSet: report.dataSet,
                aggregate: report.aggregate
            )
            let result = try exportCoordinator.prepare(format: format, payload: payload)
            await diagnosticsReporter.report(
                source: source,
                category: "export",
                severity: .info,
                message: "Prepared report export.",
                metadata: [
                    "format": format.fileExtension,
                    "byte_count": String(result.data.count)
                ]
            )
            errorMessage = nil
            return result
        } catch {
            errorMessage = "Failed to prepare \(format.displayName) export. \(describe(error))"
            await diagnosticsReporter.reportError(
                source: source,
                category: "export",
                message: "Failed to prepare report export.",
                errorDescription: describe(error),
                metadata: ["format": format.fileExtension]
            )
            return nil
        }
    }

    func recordExportCompletion(result: Result<URL, Error>, description: String) {
        switch result {
        case .success(let url):
            statusMessage = "Saved \(description) to \(url.lastPathComponent)."
            errorMessage = nil
        case .failure(let error):
            if (error as? CocoaError)?.code == .userCancelled {
                return
            }
            statusMessage = nil
            errorMessage = "Failed to save \(description). \(describe(error))"
        }
    }

    private func describe(_ error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
