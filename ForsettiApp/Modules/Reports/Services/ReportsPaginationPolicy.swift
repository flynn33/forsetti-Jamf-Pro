import Foundation

enum ReportsPaginationPolicy {
    nonisolated static let defaultPageSize = 200
    nonisolated static let safetyPageLimit = 50

    nonisolated static func shouldStop(pageRecordCount: Int, page: Int, pageSize: Int = defaultPageSize, totalCount: Int? = nil, accumulatedCount: Int? = nil) -> Bool {
        if pageRecordCount == 0 || pageRecordCount < pageSize {
            return true
        }
        if let totalCount, let accumulatedCount, accumulatedCount >= totalCount {
            return true
        }
        return page + 1 >= safetyPageLimit
    }
}
