import SwiftUI

/// A single row in the mobile-device search results list.
///
/// Renders the device name, the active-profile fields with non-empty values,
/// and the Pre-Stage Enrollment composite when present. No graphic indicators
/// — gauges and visual hardware data are reserved for the dedicated detail
/// view that opens when the user taps a row.
struct MobileDeviceResultRow: View {
    let record: MobileDeviceRecord
    let fields: [MobileDeviceField]

    private let prestageFieldKey = "prestageEnrollmentProfile"

    private var displayTitle: String {
        record.value(for: "deviceName") ?? record.deviceName
    }

    private var prestageDisplayValue: String? {
        record.value(for: prestageFieldKey)
    }

    private var visibleFields: [MobileDeviceField] {
        fields.filter { field in
            guard field.key != "deviceName", field.key != prestageFieldKey else {
                return false
            }
            guard let value = record.value(for: field.key) else { return false }
            return value.isEmpty == false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(displayTitle)
                .font(ForsettiSearchResultTypography.headline())

            if visibleFields.isEmpty && prestageDisplayValue == nil {
                Text("Serial: \(record.serialNumber)")
                    .font(ForsettiSearchResultTypography.subheadline())
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visibleFields) { field in
                    if let value = record.value(for: field.key) {
                        Text("\(field.displayName): \(value)")
                            .font(ForsettiSearchResultTypography.caption())
                            .foregroundStyle(.secondary)
                    }
                }

                if let prestageDisplayValue {
                    Text("Pre-Stage Enrollment: \(prestageDisplayValue)")
                        .font(ForsettiSearchResultTypography.caption())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

//endofline
