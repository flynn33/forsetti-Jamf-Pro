import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ReportsVisualizationSnapshotRenderer {
    enum SnapshotError: Error {
        case contextCreationFailed
        case imageCreationFailed
        case encodingFailed
    }

    func pngData(for aggregate: ReportAggregate, size: CGSize = CGSize(width: 720, height: 360), scale: CGFloat = 2) throws -> Data {
        let width = max(1, Int(size.width * scale))
        let height = max(1, Int(size.height * scale))
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw SnapshotError.contextCreationFailed
        }

        context.scaleBy(x: scale, y: scale)
        context.clear(CGRect(origin: .zero, size: size))
        Self.drawGauge(
            aggregate: aggregate,
            in: CGRect(origin: .zero, size: size),
            context: context,
            includesCenterText: true
        )

        guard let image = context.makeImage() else {
            throw SnapshotError.imageCreationFailed
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            throw SnapshotError.encodingFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw SnapshotError.encodingFailed
        }
        return data as Data
    }

    static func drawGauge(
        aggregate: ReportAggregate,
        in rect: CGRect,
        context: CGContext,
        includesCenterText: Bool
    ) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) * 0.34
        let lineWidth = max(16, min(rect.width, rect.height) * 0.09)

        context.setLineWidth(lineWidth)
        context.setLineCap(.round)
        context.setStrokeColor(CGColor(red: 0.72, green: 0.75, blue: 0.80, alpha: 0.28))
        context.addArc(center: center, radius: radius, startAngle: 0, endAngle: Double.pi * 2, clockwise: false)
        context.strokePath()

        if aggregate.gaugeSegments.isEmpty {
            context.setStrokeColor(CGColor(red: 0.50, green: 0.52, blue: 0.58, alpha: 0.75))
            context.addArc(center: center, radius: radius, startAngle: -Double.pi / 2, endAngle: Double.pi * 1.5, clockwise: false)
            context.strokePath()
        } else {
            for segment in aggregate.gaugeSegments {
                context.setStrokeColor(CGColor(
                    red: segment.colorRGBA.red,
                    green: segment.colorRGBA.green,
                    blue: segment.colorRGBA.blue,
                    alpha: segment.colorRGBA.alpha
                ))
                context.addArc(
                    center: center,
                    radius: radius,
                    startAngle: segment.startAngle,
                    endAngle: segment.endAngle,
                    clockwise: false
                )
                context.strokePath()
            }
        }

        guard includesCenterText else { return }
        // CG bitmap context is Y-up: higher math y renders higher in the PNG.
        // Big number sits above the geometric center; "Total Devices" sits below.
        drawText(
            String(aggregate.totalCount),
            in: CGRect(x: center.x - 120, y: center.y + 4, width: 240, height: 36),
            context: context,
            fontSize: 34,
            color: CGColor(red: 0.12, green: 0.15, blue: 0.18, alpha: 1),
            alignment: .center
        )
        drawText(
            "Total Devices",
            in: CGRect(x: center.x - 120, y: center.y - 22, width: 240, height: 18),
            context: context,
            fontSize: 13,
            color: CGColor(red: 0.34, green: 0.37, blue: 0.42, alpha: 1),
            alignment: .center
        )
    }

    static func drawText(
        _ text: String,
        in rect: CGRect,
        context: CGContext,
        fontSize: CGFloat,
        color: CGColor,
        alignment: CTTextAlignment = .left
    ) {
        var textAlignment = alignment
        let paragraphStyle = withUnsafePointer(to: &textAlignment) { pointer in
            var setting = CTParagraphStyleSetting(
                spec: .alignment,
                valueSize: MemoryLayout<CTTextAlignment>.size,
                value: pointer
            )
            return CTParagraphStyleCreate(&setting, 1)
        }
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, fontSize, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraphStyle
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGMutablePath()
        path.addRect(rect)
        let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: 0, length: attributed.length), path, nil)
        CTFrameDraw(frame, context)
    }
}
