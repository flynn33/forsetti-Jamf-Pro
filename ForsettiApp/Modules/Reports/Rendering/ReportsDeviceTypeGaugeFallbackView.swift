import SwiftUI

struct ReportsDeviceTypeGaugeFallbackView: View {
    let segments: [ReportGaugeSegment]

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) * 0.36
            let lineWidth = max(14, min(size.width, size.height) * 0.08)

            var track = Path()
            track.addArc(
                center: center,
                radius: radius,
                startAngle: .degrees(0),
                endAngle: .degrees(360),
                clockwise: false
            )
            context.stroke(
                track,
                with: .color(.secondary.opacity(0.20)),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )

            if segments.isEmpty {
                return
            }

            for segment in segments {
                var path = Path()
                path.addArc(
                    center: center,
                    radius: radius,
                    startAngle: .radians(segment.startAngle),
                    endAngle: .radians(segment.endAngle),
                    clockwise: false
                )
                context.stroke(
                    path,
                    with: .color(ReportsChartPalette.color(from: segment.colorRGBA)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
            }
        }
    }
}
