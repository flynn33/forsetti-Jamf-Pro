import SwiftUI
#if os(iOS)
import AVFoundation
import Vision
import VisionKit
import UIKit
#endif

// "Klatu-barada-Nikto"

/// Represents the current readiness state of the barcode/QR scanner hardware and permissions.
/// The sheet checks device support, camera availability, and authorization status before
/// transitioning to the `.ready` state that presents the live camera feed.
private enum ScannerPresentationState {
    /// Initial state while the scanner checks device capabilities and camera permissions.
    case checking
    /// The scanner hardware is supported, available, and authorized -- ready to scan.
    case ready
    /// The device hardware does not support live barcode scanning (e.g. Simulator or Mac).
    case unsupported
    /// The scanner is temporarily unavailable even though the hardware supports it.
    case unavailable
    /// The user has denied or restricted camera access in system Settings.
    case permissionDenied
}

/// A modal sheet that presents a live camera-based barcode and QR code scanner.
///
/// On iOS devices with a supported camera, the sheet uses `DataScannerViewController`
/// to recognize barcodes in real time. On unsupported platforms or when permissions are
/// missing, it shows a descriptive status card with an optional link to system Settings.
///
/// - Parameter onScanned: Closure invoked with the decoded string payload when a code is recognized.
struct CodeScannerSheet: View {
    /// Dismiss action provided by the SwiftUI environment to close this sheet.
    @Environment(\.dismiss) private var dismiss

    /// Callback that delivers the scanned barcode or QR payload string to the caller.
    let onScanned: (String) -> Void

    /// Tracks the current scanner readiness; starts at `.checking` and resolves asynchronously.
    @State private var state: ScannerPresentationState = .checking
    /// Holds an error message string when the scanner encounters a runtime failure.
    @State private var scannerErrorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                switch state {
                case .checking:
                    // Show a spinner while we verify hardware support and camera authorization
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Preparing camera scanner...")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .ready:
#if os(iOS)
                    // Present the live camera scanner using the UIKit representable bridge
                    BarcodeScannerRepresentable(
                        onScanned: { value in
                            onScanned(value)
                            dismiss()
                        },
                        onError: { message in
                            scannerErrorMessage = message
                        }
                    )
                    .ignoresSafeArea(edges: .bottom)
#else
                    ScannerStatusView(
                        title: "Scanner Unsupported",
                        message: "Barcode and QR scanning is only available on iOS."
                    )
#endif

                case .unsupported:
                    ScannerStatusView(
                        title: "Scanner Unsupported",
                        message: "This device does not support live barcode and QR scanning."
                    )

                case .unavailable:
                    ScannerStatusView(
                        title: "Scanner Unavailable",
                        message: "Camera scanning is currently unavailable. Try again in a moment."
                    )

                case .permissionDenied:
                    ScannerStatusView(
                        title: "Camera Access Required",
                        message: "Enable camera access in Settings to scan barcode and QR data."
                    ) {
                        openSystemSettings()
                    }
                }
            }
            .navigationTitle("Scan Code")
            .dashboardInlineNavigationTitle()
            .toolbar {
                // Apple HIG: Cancel uses the semantic .cancellationAction
                // placement — leading on both iOS and macOS, rendered as the
                // secondary (Escape-activated) button on macOS.
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .task {
                // Kick off the async permission and availability check on first appearance
                await configureScannerAvailability()
            }
            .alert(
                "Scanner Error",
                isPresented: Binding(
                    get: { scannerErrorMessage != nil },
                    set: { isPresented in
                        if isPresented == false {
                            scannerErrorMessage = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(scannerErrorMessage ?? "Unknown scanner failure.")
            }
        }
    }

    /// Checks device hardware support and camera authorization, then transitions `state`
    /// to the appropriate value so the UI can show either the live scanner or a status message.
    ///
    /// On iOS this inspects `DataScannerViewController.isSupported`, requests camera access
    /// if not yet determined, and finally checks `.isAvailable`. On non-iOS platforms it
    /// immediately sets the state to `.unsupported`.
    private func configureScannerAvailability() async {
#if os(iOS)
        // First gate: does the hardware support VisionKit data scanning at all?
        guard DataScannerViewController.isSupported else {
            state = .unsupported
            return
        }

        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            // Already authorized -- check runtime availability (camera not in use by another app, etc.)
            state = DataScannerViewController.isAvailable ? .ready : .unavailable
        case .notDetermined:
            // Prompt the user for camera permission using a checked continuation bridge
            let granted = await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .video) { accessGranted in
                    continuation.resume(returning: accessGranted)
                }
            }

            if granted {
                state = DataScannerViewController.isAvailable ? .ready : .unavailable
            } else {
                state = .permissionDenied
            }
        case .restricted, .denied:
            state = .permissionDenied
        @unknown default:
            state = .unavailable
        }
#else
        state = .unsupported
#endif
    }

    /// Opens the iOS system Settings app so the user can grant camera permission.
    /// This is a no-op on non-iOS platforms.
    private func openSystemSettings() {
#if os(iOS)
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }

        UIApplication.shared.open(url)
#endif
    }
}

// "Would you like to play a game?"

/// A card-style view that displays a scanner status icon, title, message, and an optional action button.
/// Used when the scanner cannot be presented (unsupported hardware, no permission, etc.).
private struct ScannerStatusView: View {
    /// The bold headline text shown below the icon (e.g. "Scanner Unsupported").
    let title: String
    /// A longer explanatory message displayed below the title.
    let message: String
    /// An optional closure executed when the user taps "Open Settings". When nil, the button is hidden.
    let action: (() -> Void)?

    /// Creates a scanner status card with an optional action button.
    /// - Parameters:
    ///   - title: Bold headline text for the status card.
    ///   - message: Explanatory body text.
    ///   - action: Optional closure invoked when the user taps the settings button.
    init(
        title: String,
        message: String,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.action = action
    }

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "camera.viewfinder")
                .font(.largeTitle)
                .foregroundStyle(DashboardColors.bluePrimary)

            Text(title)
                .font(.headline)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            // Only show the action button when a callback is provided
            if let action {
                Button("Open Settings") {
                    action()
                }
                .buttonStyle(.dashboardPrimary)
            }
        }
        .padding(20)
        .background(DashboardTheme.groupedSurface)
        .clipShape(RoundedRectangle(cornerRadius: DashboardTheme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DashboardTheme.Radius.card, style: .continuous)
                .stroke(DashboardTheme.border, lineWidth: 1)
        )
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A `UIViewControllerRepresentable` that wraps `DataScannerViewController` from VisionKit,
/// bridging it into SwiftUI. It configures the scanner for barcode recognition across a wide
/// range of symbologies and delivers scanned payloads through a callback closure.
#if os(iOS)
private struct BarcodeScannerRepresentable: UIViewControllerRepresentable {
    /// Callback invoked with the decoded barcode string when a valid code is recognized.
    let onScanned: (String) -> Void
    /// Callback invoked with an error description if the scanner encounters a problem.
    let onError: (String) -> Void

    /// Creates the coordinator that acts as the `DataScannerViewControllerDelegate`.
    func makeCoordinator() -> Coordinator {
        Coordinator(onScanned: onScanned, onError: onError)
    }

    /// Instantiates and configures a `DataScannerViewController` with balanced quality,
    /// pinch-to-zoom, guidance overlay, and highlighting enabled. Scanning starts immediately.
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: Self.supportedSymbologies)],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: true,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )

        scanner.delegate = context.coordinator

        do {
            try scanner.startScanning()
        } catch {
            onError(error.localizedDescription)
        }

        return scanner
    }

    /// No-op -- the scanner configuration does not change after initial creation.
    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) { }

    /// Stops the scanning session when the representable is torn down to release the camera.
    static func dismantleUIViewController(_ uiViewController: DataScannerViewController, coordinator: Coordinator) {
        uiViewController.stopScanning()
    }

    /// The full set of barcode symbologies the scanner will attempt to recognize,
    /// covering common 1D barcodes (Code 128, EAN-13, UPC-E, etc.) and 2D codes (QR, Aztec, Data Matrix, PDF417).
    static let supportedSymbologies: [VNBarcodeSymbology] = [
        .qr,
        .aztec,
        .code128,
        .code39,
        .code93,
        .ean8,
        .ean13,
        .itf14,
        .pdf417,
        .upce,
        .dataMatrix
    ]

    /// Coordinator that serves as the `DataScannerViewControllerDelegate`, forwarding
    /// recognized barcode payloads to the SwiftUI layer through closures. It ensures
    /// only the first valid barcode is captured to prevent duplicate callbacks.
    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        /// Closure that delivers the scanned barcode string payload.
        private let onScanned: (String) -> Void
        /// Closure that delivers scanner error descriptions.
        private let onError: (String) -> Void
        /// Guard flag to ensure only one barcode value is ever captured per scan session.
        private var hasCapturedValue = false

        /// Initializes the coordinator with scan result and error callbacks.
        /// - Parameters:
        ///   - onScanned: Closure called with the first valid barcode payload.
        ///   - onError: Closure called if the scanner becomes unavailable with an error.
        init(
            onScanned: @escaping (String) -> Void,
            onError: @escaping (String) -> Void
        ) {
            self.onScanned = onScanned
            self.onError = onError
        }

        /// Called when the user taps on a recognized barcode item in the viewfinder.
        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didTapOn item: RecognizedItem
        ) {
            process(items: [item])
        }

        /// Called when the scanner detects new barcode items entering the camera frame.
        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            process(items: addedItems)
        }

        /// Called when the scanner becomes unavailable due to a runtime error (e.g. camera interrupted).
        func dataScanner(
            _ dataScanner: DataScannerViewController,
            becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable
        ) {
            onError(error.localizedDescription)
        }

        /// Iterates through recognized items, extracts the first non-empty barcode payload,
        /// and fires the `onScanned` callback exactly once. Subsequent calls are ignored
        /// after `hasCapturedValue` is set to prevent duplicate scans.
        private func process(items: [RecognizedItem]) {
            // Only capture the very first valid barcode to avoid duplicate callbacks
            guard hasCapturedValue == false else {
                return
            }

            for item in items {
                if case let .barcode(barcode) = item,
                   let payload = barcode.payloadStringValue,
                   payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                    hasCapturedValue = true
                    onScanned(payload)
                    return
                }
            }
        }
    }
}
#endif

//endofline
