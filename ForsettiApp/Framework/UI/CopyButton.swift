import SwiftUI

/// A compact "copy to clipboard" button. Shows a `doc.on.doc` icon; tapping copies `value`
/// to the system pasteboard and briefly swaps the icon to a `checkmark` for confirmation.
/// Uses a borderless button style so its tap is isolated from any enclosing row or
/// `NavigationLink`.
struct CopyButton: View {

    /// The string copied to the clipboard when tapped.
    let value: String

    /// VoiceOver label; defaults to a generic "Copy".
    var accessibilityLabel: String = "Copy"

    /// Drives the transient checkmark confirmation.
    @State private var didCopy = false

    /// Reverts the checkmark after the confirmation interval.
    @State private var resetTask: Task<Void, Never>?

    var body: some View {
        Button {
            DashboardClipboard.copy(value)
            showConfirmation()
        } label: {
            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                .font(.callout)
                .foregroundStyle(didCopy ? DashboardColors.greenPrimary : Color.secondary)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(didCopy ? "Copied" : accessibilityLabel)
    }

    /// Flips to the checkmark, then restores the copy icon after ~1 second.
    private func showConfirmation() {
        didCopy = true
        resetTask?.cancel()
        resetTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if Task.isCancelled == false { didCopy = false }
        }
    }
}

//endofline
