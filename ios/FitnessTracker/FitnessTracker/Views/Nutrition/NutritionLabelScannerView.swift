import AVFoundation
import SwiftUI
import Vision

/// Continuously OCRs camera frames looking for nutrition-facts numbers.
/// iOS has no built-in Vision recognizer for a nutrition panel the way it
/// does for card numbers - this replicates the "credit card scanner"
/// technique by hand instead: live `VNRecognizeTextRequest` on a throttled
/// frame rate, each frame's recognized lines run through
/// `NutritionLabelParser`, with results merged into a running best guess
/// (see `ParsedNutritionLabel.merge`) rather than one single-shot capture.
private final class NutritionLabelScannerController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate {
    var onUpdate: ((ParsedNutritionLabel) -> Void)?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let textRequest = VNRecognizeTextRequest()
    private let processingQueue = DispatchQueue(label: "nutrition-label-ocr")
    /// Every frame's OCR is wasted CPU/battery for text that isn't
    /// moving - throttled to about 4 reads a second instead.
    private var lastProcessedAt = Date.distantPast
    private let minProcessingInterval: TimeInterval = 0.25

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        textRequest.recognitionLevel = .accurate
        // Label text is codes/numbers/short words, not prose - language
        // correction "fixing" a number is exactly the failure mode to
        // avoid here.
        textRequest.usesLanguageCorrection = false

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else { return }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        guard session.canAddOutput(output) else { return }
        output.setSampleBufferDelegate(self, queue: processingQueue)
        session.addOutput(output)

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

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        let now = Date()
        guard now.timeIntervalSince(lastProcessedAt) >= minProcessingInterval else { return }
        lastProcessedAt = now
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right)
        guard (try? handler.perform([textRequest])) != nil else { return }
        let lines = (textRequest.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        guard !lines.isEmpty else { return }

        let parsed = NutritionLabelParser.parse(lines)
        guard parsed.hasAnything else { return }
        DispatchQueue.main.async { [onUpdate] in onUpdate?(parsed) }
    }
}

private struct NutritionLabelScannerRepresentable: UIViewControllerRepresentable {
    let onUpdate: (ParsedNutritionLabel) -> Void

    func makeUIViewController(context: Context) -> NutritionLabelScannerController {
        let controller = NutritionLabelScannerController()
        controller.onUpdate = onUpdate
        return controller
    }

    func updateUIViewController(_ uiViewController: NutritionLabelScannerController, context: Context) {}
}

/// Point the camera at a nutrition facts panel - fields fill in live as
/// they're recognized (mirrors a credit-card scanner's UX per Liam's own
/// framing), then "Use These Values" hands off to `AddCustomFoodView`
/// pre-filled for review before saving - the same accuracy safety net a
/// manual add already has, since an OCR mis-read (a smudged "8" read as a
/// "3") needs a chance to be caught before it's saved, not after.
/// `barcode`, when this was opened after a failed barcode lookup, carries
/// through so the resulting food is a cache hit for anyone who scans the
/// same product next.
struct NutritionLabelScannerView: View {
    let barcode: String?
    let onConfirm: (ParsedNutritionLabel, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var parsed = ParsedNutritionLabel()

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                NutritionLabelScannerRepresentable { update in
                    parsed.merge(update)
                }
                .ignoresSafeArea()
                // The camera preview has nothing to tap on its own - without
                // this, its full-screen UIKit view sits in front of (or at
                // least intercepts touches meant for) the SwiftUI buttons
                // stacked on top of it, swallowing every tap on them.
                .allowsHitTesting(false)

                VStack(spacing: 16) {
                    fieldChecklist
                        .padding()
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .padding(.horizontal)

                    HStack(spacing: 12) {
                        // Only worth offering once there's something to
                        // clear - a misread field (that "8" OCR'd as a "3")
                        // is otherwise stuck once found, since `merge`
                        // deliberately never lets a later read overwrite an
                        // earlier one.
                        if parsed.hasAnything {
                            Button {
                                parsed = ParsedNutritionLabel()
                            } label: {
                                Text("Rescan")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .foregroundStyle(.blue)
                                    .background(.blue.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
                            }
                        }

                        Button {
                            onConfirm(parsed, barcode)
                            dismiss()
                        } label: {
                            Text(parsed.hasAnything ? "Use These Values" : "Enter Manually Instead")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .foregroundStyle(.white)
                                .background(.blue, in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Scan Nutrition Label")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var fieldChecklist: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Point the camera at the nutrition facts panel")
                .font(.caption)
                .foregroundStyle(.secondary)
            servingSizeRow
            fieldRow("Calories", value: parsed.caloriesKcal, unit: "kcal")
            fieldRow("Protein", value: parsed.proteinG, unit: "g")
            fieldRow("Carbs", value: parsed.carbsG, unit: "g")
            fieldRow("Fat", value: parsed.fatG, unit: "g")
            fieldRow("Fiber", value: parsed.fiberG, unit: "g", optional: true)
        }
    }

    /// Not covered by `fieldRow` since there's no fixed unit to show until
    /// one's actually found - defaults to "100 g" once nothing else has
    /// been read yet, matching `AddCustomFoodView`'s own fallback, so this
    /// row never looks unfilled even before a serving-size line is seen.
    private var servingSizeRow: some View {
        HStack {
            Image(systemName: parsed.servingSize != nil ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(parsed.servingSize != nil ? .green : .secondary)
            Text("Serving Size")
            Spacer()
            let size = parsed.servingSize ?? 100
            let unit = parsed.servingUnit ?? "g"
            Text("\(size == size.rounded() ? String(Int(size)) : String(format: "%.1f", size)) \(unit)")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func fieldRow(_ label: String, value: Double?, unit: String, optional: Bool = false) -> some View {
        HStack {
            Image(systemName: value != nil ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(value != nil ? .green : .secondary)
            Text(label)
            Spacer()
            if let value {
                Text("\(value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)) \(unit)")
                    .foregroundStyle(.secondary)
            } else if optional {
                Text("optional").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}
