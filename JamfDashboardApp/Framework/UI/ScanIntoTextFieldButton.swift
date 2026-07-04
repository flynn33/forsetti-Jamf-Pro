import SwiftUI

/// A button that presents a barcode/QR code scanner sheet and writes the scanned
/// value into a bound text field. Optionally calls an additional callback after scanning.
/// Typically placed alongside a `TextField` to let users populate it by scanning a code.
struct ScanIntoTextFieldButton: View {
    /// Two-way binding to the text field that receives the scanned barcode value.
    @Binding var text: String
    /// Optional additional callback invoked after the scanned value is written to `text`.
    let onScanned: ((String) -> Void)?

    /// Controls presentation of the `CodeScannerSheet` modal.
    @State private var isScannerPresented = false

    /// Creates a scan button bound to a text field.
    /// - Parameters:
    ///   - text: Binding to the text field that will receive the scanned value.
    ///   - onScanned: Optional closure called with the scanned string after it is assigned.
    init(
        text: Binding<String>,
        onScanned: ((String) -> Void)? = nil
    ) {
        _text = text
        self.onScanned = onScanned
    }


    var body: some View {
        Button {
            isScannerPresented = true
        } label: {
            Image(systemName: "camera.viewfinder")
                .font(.body.weight(.semibold))
        }
        .buttonStyle(.dashboardSecondary)
        .accessibilityLabel("Scan Barcode or QR")
        .sheet(isPresented: $isScannerPresented) {
            CodeScannerSheet { scannedValue in
                // Write the scanned payload directly into the bound text field
                text = scannedValue
                onScanned?(scannedValue)
            }
        }
    }
}

//endofline
