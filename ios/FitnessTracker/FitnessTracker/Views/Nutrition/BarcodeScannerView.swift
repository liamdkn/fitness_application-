import AVFoundation
import SwiftUI

/// Thin AVFoundation wrapper - live camera preview + barcode detection. No
/// dedup/cooldown logic lives here - `BarcodeScannerView` guards
/// re-entrancy on its own `isLookingUp` flag, so a code sitting in frame
/// just keeps calling back into a no-op while a lookup is in flight.
private final class BarcodeScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((String) -> Void)?
    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else { return }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.ean8, .ean13, .upce, .code128]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.addSublayer(preview)
        previewLayer = preview
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task.detached { [session] in session.startRunning() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        session.stopRunning()
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue
        else { return }
        onScan?(value)
    }
}

private struct BarcodeScannerRepresentable: UIViewControllerRepresentable {
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> BarcodeScannerController {
        let controller = BarcodeScannerController()
        controller.onScan = onScan
        return controller
    }

    func updateUIViewController(_ uiViewController: BarcodeScannerController, context: Context) {}
}

/// Barcode → food, in order: the local `foods.barcode` cache-hit path,
/// then an Open Food Facts lookup (inserted as a new shared row so the
/// next scan of the same product is a cache hit), then a "not found"
/// message pointing back at search/manual entry.
struct BarcodeScannerView: View {
    let onFound: (Food) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isLookingUp = false
    @State private var errorMessage: String?
    private let foodRepository = FoodRepository()

    var body: some View {
        NavigationStack {
            ZStack {
                BarcodeScannerRepresentable { barcode in
                    Task { await handleScan(barcode) }
                }
                .ignoresSafeArea()

                if isLookingUp {
                    ProgressView("Looking up...")
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                if let errorMessage {
                    VStack {
                        Spacer()
                        Text(errorMessage)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white)
                            .padding()
                            .background(.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
                            .padding(.bottom, 40)
                    }
                }
            }
            .navigationTitle("Scan Barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func handleScan(_ barcode: String) async {
        guard !isLookingUp else { return }
        isLookingUp = true
        errorMessage = nil
        defer { isLookingUp = false }
        do {
            if let existing = try await foodRepository.fetchByBarcode(barcode) {
                onFound(existing)
                dismiss()
                return
            }
            guard let lookup = try await OpenFoodFactsService.lookup(barcode: barcode) else {
                errorMessage = "No food found for that barcode. Try search or add it manually."
                return
            }
            let inserted = try await foodRepository.insertFromOpenFoodFacts(barcode: barcode, lookup: lookup)
            onFound(inserted)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
