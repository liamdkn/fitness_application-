import PhotosUI
import SwiftUI

struct MeasurementsPhotosCaptureView: View {
    let onSaveMeasurement: (_ waistCm: Double?, _ leftBicepCm: Double?, _ rightBicepCm: Double?) async -> Void
    let onSavePhoto: (Data) async -> Void

    @State private var waistText = ""
    @State private var leftBicepText = ""
    @State private var rightBicepText = ""
    @State private var isSavingMeasurement = false
    @State private var selectedPhotoItems: [PhotosPickerItem] = []
    @State private var isUploadingPhotos = false
    @State private var errorMessage: String?

    private var hasMeasurementInput: Bool {
        !waistText.isEmpty || !leftBicepText.isEmpty || !rightBicepText.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Measurements")
                .font(.headline)

            measurementField(label: "Waist", text: $waistText, unit: "cm")
            measurementField(label: "Left Bicep", text: $leftBicepText, unit: "cm")
            measurementField(label: "Right Bicep", text: $rightBicepText, unit: "cm")

            Button {
                Task { await saveMeasurement() }
            } label: {
                if isSavingMeasurement {
                    ProgressView()
                } else {
                    Text("Save Measurements")
                }
            }
            .disabled(!hasMeasurementInput || isSavingMeasurement)

            Divider()

            Text("Progress Photos")
                .font(.headline)

            PhotosPicker(selection: $selectedPhotoItems, maxSelectionCount: 4, matching: .images) {
                Label("Select Photos", systemImage: "photo.on.rectangle")
            }
            .onChange(of: selectedPhotoItems) { _, newItems in
                Task { await uploadPhotos(newItems) }
            }

            if isUploadingPhotos {
                ProgressView("Uploading...")
            }

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func measurementField(label: String, text: Binding<String>, unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("-", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
            Text(unit).foregroundStyle(.secondary).font(.caption)
        }
    }

    private func saveMeasurement() async {
        isSavingMeasurement = true
        defer { isSavingMeasurement = false }
        await onSaveMeasurement(Double(waistText), Double(leftBicepText), Double(rightBicepText))
    }

    private func uploadPhotos(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        isUploadingPhotos = true
        defer {
            isUploadingPhotos = false
            selectedPhotoItems = []
        }
        for item in items {
            do {
                guard
                    let data = try await item.loadTransferable(type: Data.self),
                    let compressed = ImageCompression.compress(data)
                else { continue }
                await onSavePhoto(compressed)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

enum ImageCompression {
    static func compress(_ data: Data, maxDimension: CGFloat = 1600, quality: CGFloat = 0.7) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}
