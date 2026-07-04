import SwiftUI

enum ReportsChartPalette {
    static func color(for type: ReportDeviceType) -> Color {
        color(from: type.rgba)
    }

    static func color(from rgba: ReportRGBA) -> Color {
        Color(red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
    }
}
