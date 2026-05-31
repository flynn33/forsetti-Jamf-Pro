import SwiftUI

// MARK: - SwiftUI KPI ring fallback
//
// Used when MetalKit is unavailable or Metal initialization fails. The fallback
// intentionally mirrors the Metal ring's fraction and color semantics so the
// Dashboard remains readable on every platform.
struct DeploymentKPIRingFallbackView: View {
    let projection: DeploymentKPIProjection

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.18), lineWidth: 12)

            Circle()
                .trim(from: 0, to: projection.fraction)
                .stroke(
                    color,
                    style: StrokeStyle(lineWidth: 12, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
    }

    private var color: Color {
        Color(
            red: projection.color.red,
            green: projection.color.green,
            blue: projection.color.blue,
            opacity: projection.color.alpha
        )
    }
}
