import CoreGraphics
import CoreText
import Foundation

struct ReportPDFRenderer: ReportExportRendering {
    enum PDFError: Error {
        case contextCreationFailed
    }

    func render(payload: ReportExportPayload) throws -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else {
            throw PDFError.contextCreationFailed
        }
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw PDFError.contextCreationFailed
        }

        context.beginPDFPage(nil)
        drawHeader(payload: payload, context: context, page: mediaBox)
        ReportsVisualizationSnapshotRenderer.drawGauge(
            aggregate: payload.aggregate,
            in: CGRect(x: 96, y: 360, width: 420, height: 240),
            context: context,
            includesCenterText: true
        )
        drawSummary(payload: payload, context: context, page: mediaBox)
        context.endPDFPage()

        var remaining = Array(payload.records.prefix(600))
        while remaining.isEmpty == false {
            context.beginPDFPage(nil)
            drawText("Device Details", x: 48, y: 730, context: context, size: 20, color: titleColor)
            let pageRecords = Array(remaining.prefix(28))
            drawTable(records: pageRecords, context: context)
            remaining.removeFirst(pageRecords.count)
            context.endPDFPage()
        }

        context.closePDF()
        return data as Data
    }

    private func drawHeader(payload: ReportExportPayload, context: CGContext, page: CGRect) {
        drawText(payload.request.resolvedName, x: 48, y: 730, context: context, size: 26, color: titleColor)
        let subtitle = "Generated \(dateFormatter.string(from: payload.generatedAt))" + (payload.serverLabel.map { " for \($0)" } ?? "")
        drawText(subtitle, x: 48, y: 704, context: context, size: 11, color: secondaryColor)
        context.setStrokeColor(CGColor(red: 0.78, green: 0.84, blue: 0.90, alpha: 1))
        context.setLineWidth(1)
        context.move(to: CGPoint(x: 48, y: 690))
        context.addLine(to: CGPoint(x: page.width - 48, y: 690))
        context.strokePath()
    }

    private func drawSummary(payload: ReportExportPayload, context: CGContext, page: CGRect) {
        let metrics: [(String, Int)] = [
            ("Total", payload.aggregate.totalCount),
            ("Mac", payload.aggregate.count(for: .mac)),
            ("iPad", payload.aggregate.count(for: .ipad)),
            ("iPhone", payload.aggregate.count(for: .iphone)),
            ("Unknown", payload.aggregate.count(for: .unknown))
        ]
        let cardWidth: CGFloat = 96
        for (index, metric) in metrics.enumerated() {
            let x = 48 + CGFloat(index) * (cardWidth + 8)
            let rect = CGRect(x: x, y: 628, width: cardWidth, height: 48)
            context.setFillColor(CGColor(red: 0.94, green: 0.97, blue: 1.0, alpha: 1))
            context.fill(rect)
            context.setStrokeColor(CGColor(red: 0.74, green: 0.82, blue: 0.90, alpha: 1))
            context.stroke(rect)
            drawText(metric.0, x: x + 8, y: 660, context: context, size: 10, color: secondaryColor)
            drawText(String(metric.1), x: x + 8, y: 638, context: context, size: 18, color: titleColor)
        }

        drawText("Device Type Counts", x: 48, y: 322, context: context, size: 16, color: titleColor)
        var y: CGFloat = 298
        for item in payload.aggregate.orderedTypeCounts {
            let color = item.type.rgba
            context.setFillColor(CGColor(red: color.red, green: color.green, blue: color.blue, alpha: 1))
            context.fill(CGRect(x: 52, y: y - 2, width: 10, height: 10))
            drawText("\(item.type.displayName): \(item.count)", x: 70, y: y - 4, context: context, size: 11, color: bodyColor)
            y -= 18
        }

        if payload.aggregate.inferredCount > 0 || payload.aggregate.unknownCount > 0 {
            drawText(
                "Disclosure: \(payload.aggregate.inferredCount) inferred records, \(payload.aggregate.unknownCount) unknown records.",
                x: 48,
                y: 84,
                context: context,
                size: 10,
                color: secondaryColor
            )
        }
    }

    private func drawTable(records: [ReportDeviceRecord], context: CGContext) {
        let headers = ["Type", "Name", "Serial", "Model", "OS", "Enrolled", "Confidence"]
        // Rebalanced to keep the same total table width (554pt) with the added column.
        let widths: [CGFloat] = [50, 102, 80, 110, 50, 70, 92]
        var x: CGFloat = 48
        let headerY: CGFloat = 694
        context.setFillColor(CGColor(red: 0.93, green: 0.96, blue: 1, alpha: 1))
        context.fill(CGRect(x: 48, y: headerY - 6, width: widths.reduce(0, +), height: 22))
        for (index, header) in headers.enumerated() {
            drawText(header, x: x + 3, y: headerY, context: context, size: 9, color: titleColor)
            x += widths[index]
        }

        var y = headerY - 24
        for record in records {
            x = 48
            let values = [
                record.deviceType.displayName,
                record.displayName ?? "",
                record.serialNumber ?? "",
                record.identity.marketingName ?? record.model ?? "",
                record.osVersion ?? "",
                record.value(for: "enrollmentDate") ?? "",
                record.identity.confidence.displayName
            ]
            for (index, value) in values.enumerated() {
                drawText(value, x: x + 3, y: y, context: context, size: 8, color: bodyColor)
                x += widths[index]
            }
            context.setStrokeColor(CGColor(red: 0.86, green: 0.89, blue: 0.92, alpha: 1))
            context.move(to: CGPoint(x: 48, y: y - 7))
            context.addLine(to: CGPoint(x: 48 + widths.reduce(0, +), y: y - 7))
            context.strokePath()
            y -= 21
        }
    }

    private func drawText(_ text: String, x: CGFloat, y: CGFloat, context: CGContext, size: CGFloat, color: CGColor) {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, size, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let line = CTLineCreateWithAttributedString(attributed)
        context.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, context)
    }

    private let titleColor = CGColor(red: 0.08, green: 0.20, blue: 0.36, alpha: 1)
    private let bodyColor = CGColor(red: 0.15, green: 0.18, blue: 0.22, alpha: 1)
    private let secondaryColor = CGColor(red: 0.34, green: 0.39, blue: 0.45, alpha: 1)

    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}
