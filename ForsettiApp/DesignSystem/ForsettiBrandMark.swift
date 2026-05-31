import SwiftUI

struct ForsettiBrandMark: View {
    var body: some View {
        HStack(spacing: ForsettiTheme.Spacing.item) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 32, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(ForsettiTheme.accent)
                .accessibilityHidden(true)

            Text(ForsettiAppIdentity.displayName)
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(.primary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(ForsettiAppIdentity.displayName)
    }
}
