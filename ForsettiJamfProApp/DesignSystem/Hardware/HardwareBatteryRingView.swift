import SwiftUI

// "End of Line"

/// Pure-SwiftUI battery indicator that pairs with the storage gauge in the
/// hardware card. Renders a circular progress ring plus a centered percentage
/// label. Color shifts from green (>50%) to yellow (21-50%) to red (≤20%) so
/// drained devices stand out at a glance.
///
/// Implemented in SwiftUI (no Metal) because rings animate fine with
/// `.trim(from:to:)` and there's nothing about the visualization that benefits
/// from GPU shaders. Reserves Metal for the storage gauge where the wave +
/// flowing-light pass justify it.
struct HardwareBatteryRingView: View {
    /// Battery percentage 0-100. Values outside the range are clamped before
    /// rendering. `nil` is the caller's job to handle (don't render the view).
    let percent: Int

    /// Diameter of the ring in points. Default keeps the ring proportional to
    /// the storage gauge in `HardwareInfoCard`.
    var diameter: CGFloat = 88

    private var clampedPercent: Int {
        max(0, min(100, percent))
    }

    private var fraction: Double {
        Double(clampedPercent) / 100.0
    }

    private var ringColor: Color {
        switch clampedPercent {
        case ..<21: return Color(red: 0.92, green: 0.30, blue: 0.30)
        case 21...50: return Color(red: 0.95, green: 0.78, blue: 0.20)
        default: return Color(red: 0.18, green: 0.72, blue: 0.40)
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(ringColor.opacity(0.18), lineWidth: 8)

            Circle()
                .trim(from: 0, to: fraction)
                .stroke(ringColor, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.35), value: fraction)

            VStack(spacing: 2) {
                Text("\(clampedPercent)%")
                    .font(.system(size: diameter * 0.26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text("Battery")
                    .font(.system(size: diameter * 0.13))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Battery \(clampedPercent) percent")
    }
}

//endofline
