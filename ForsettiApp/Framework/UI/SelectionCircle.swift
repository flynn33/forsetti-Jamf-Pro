import SwiftUI

/// Leading multi-select toggle used by list rows in selection mode. Renders an empty
/// `circle` when unselected and a filled `checkmark.circle.fill` (accent) when selected.
struct SelectionCircle: View {
    /// Whether the associated row is currently selected.
    let isSelected: Bool

    var body: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .foregroundStyle(isSelected ? DashboardColors.bluePrimary : Color.secondary)
            .accessibilityHidden(true)
    }
}

//endofline
