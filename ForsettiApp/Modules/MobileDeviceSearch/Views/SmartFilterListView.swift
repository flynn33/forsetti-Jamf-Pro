import SwiftUI

/// Saved smart-filter section displayed inside `MobileDeviceSearchView`.
///
/// Mirrors the look of the existing Search Profiles section: each row shows
/// the filter name plus a one-line summary of how many criteria it carries.
/// Tapping loads the filter into the search view model. Swipe-to-delete is
/// supported via `onDelete`.
struct SmartFilterListView: View {
    let filters: [SmartFilter]
    let onSelect: (SmartFilter) -> Void
    let onDelete: (IndexSet) -> Void

    var body: some View {
        ForEach(filters) { filter in
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(filter.name)
                    Text(summary(for: filter))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onSelect(filter)
            }
        }
        .onDelete(perform: onDelete)
    }

    /// Concise summary: criterion count + column count. Avoids dumping the
    /// full RSQL into the row — the user can preview it in the Advanced sheet.
    private func summary(for filter: SmartFilter) -> String {
        let criterionCount = filter.query.groups.reduce(0) { $0 + $1.criteria.count }
        return "\(criterionCount) criteria · \(filter.fieldKeys.count) columns"
    }
}

//endofline
