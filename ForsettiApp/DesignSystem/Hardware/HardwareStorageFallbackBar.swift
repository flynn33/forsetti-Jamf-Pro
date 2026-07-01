import SwiftUI

// "End of Line"

/// Pure-SwiftUI rendering of the storage gauge for hosts without Metal.
///
/// Reached when `MTLCreateSystemDefaultDevice()` returns nil — chiefly older
/// macOS Intel hardware. Uses a `Capsule` mask with a green→yellow→red
/// gradient that animates implicitly when `usedFraction` changes. Numeric
/// labels live in the parent `HardwareStorageGaugeView`, not here, so the
/// fallback and Metal paths look identical from the outside.
struct HardwareStorageFallbackBar: View {
    let usedFraction: Double
    let style: HardwareStorageGaugeStyle

    private var clampedFraction: Double {
        max(0, min(1, usedFraction))
    }

    /// Color heatmap matched to the Metal fragment shader so the two paths
    /// agree on which value is "alarming." Anything < 0.5 blends green to
    /// yellow; ≥ 0.5 blends yellow to red.
    private var fillColor: Color {
        let t = clampedFraction
        if t < 0.5 {
            return Color.interpolate(.init(red: 0.18, green: 0.72, blue: 0.40),
                                     .init(red: 0.95, green: 0.78, blue: 0.20),
                                     t: t * 2.0)
        } else {
            return Color.interpolate(.init(red: 0.95, green: 0.78, blue: 0.20),
                                     .init(red: 0.92, green: 0.30, blue: 0.30),
                                     t: (t - 0.5) * 2.0)
        }
    }

    var body: some View {
        // Track + fill colors matched to the Metal shader so the visual is
        // identical regardless of which path runs (Metal-capable host vs.
        // SwiftUI-only fallback). Pill ends via `Capsule()`; SwiftUI rasterizes
        // capsules with native antialiasing so edges stay clean at any height.
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(red: 0.20, green: 0.22, blue: 0.28))

                Capsule()
                    .fill(fillColor)
                    .frame(width: max(0, proxy.size.width * clampedFraction))
                    .animation(.easeInOut(duration: style == .detail ? 0.35 : 0.18),
                               value: clampedFraction)
            }
        }
    }
}

private extension Color {
    /// Linear RGB interpolation between two colors.
    /// SwiftUI does not expose component-wise blending, so this is enough
    /// fidelity for the heatmap without pulling UIColor / NSColor in.
    static func interpolate(_ a: RGBComponents, _ b: RGBComponents, t: Double) -> Color {
        let clamped = max(0, min(1, t))
        return Color(
            red: a.red + (b.red - a.red) * clamped,
            green: a.green + (b.green - a.green) * clamped,
            blue: a.blue + (b.blue - a.blue) * clamped
        )
    }

    struct RGBComponents {
        let red: Double
        let green: Double
        let blue: Double
    }
}

//endofline
