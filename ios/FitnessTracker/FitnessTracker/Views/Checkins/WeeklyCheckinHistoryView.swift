import SwiftUI

/// Everything a past weekly check-in recorded, reachable from Settings ->
/// Weekly Check-In -> Check-In History. This is purely a browse/review
/// screen (nothing here is editable) - the check-in itself is only ever
/// created through `WeeklyCheckinFlow`.
struct WeeklyCheckinHistoryView: View {
    @State private var checkins: [WeeklyCheckin] = []
    @State private var errorMessage: String?
    @State private var isLoading = false

    private let repository = WeeklyCheckinRepository()

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            ForEach(checkins) { checkin in
                NavigationLink {
                    WeeklyCheckinDetailView(checkin: checkin)
                } label: {
                    row(for: checkin)
                }
            }
        }
        .overlay {
            if isLoading && checkins.isEmpty {
                ProgressView()
            } else if !isLoading && checkins.isEmpty && errorMessage == nil {
                ContentUnavailableView("No Check-Ins Yet", systemImage: "calendar.badge.clock", description: Text("Your weekly check-ins will show up here once you complete one."))
            }
        }
        .navigationTitle("Check-In History")
        .task { await load() }
    }

    @ViewBuilder
    private func row(for checkin: WeeklyCheckin) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(formattedDate(checkin.checkinDate))
                .font(.headline)
            HStack(spacing: 12) {
                if let weight = checkin.weightKg {
                    Text(String(format: "%.1f kg", weight))
                }
                if let weekNumber = checkin.weekNumber {
                    Text("Week \(weekNumber)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            checkins = try await repository.fetchRecent()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func formattedDate(_ isoDate: String) -> String {
        guard let date = DateFormatting.date(fromISODate: isoDate) else { return isoDate }
        return date.formatted(date: .abbreviated, time: .omitted)
    }
}

/// One check-in's full record: the weight/week it was logged with, any
/// measurements and photos captured against it (via
/// `MeasurementsPhotosCaptureView` at the end of the flow), and - for an
/// older check-in from before the survey was retired - its old subjective
/// answers, reusing the same `WeeklyCheckinSummary` Weekly Insights shows.
struct WeeklyCheckinDetailView: View {
    let checkin: WeeklyCheckin

    @State private var measurements: [BodyMeasurement] = []
    @State private var photos: [ProgressPhoto] = []
    @State private var photoURLs: [UUID: URL] = [:]
    @State private var errorMessage: String?

    private let measurementRepository = BodyMeasurementRepository()
    private let photoRepository = ProgressPhotoRepository()

    var body: some View {
        Form {
            Section("This Check-In") {
                if let weight = checkin.weightKg {
                    LabeledContent("Weight", value: String(format: "%.1f kg", weight))
                }
                if let weekNumber = checkin.weekNumber {
                    LabeledContent("Week", value: "\(weekNumber)")
                }
            }

            if !measurements.isEmpty {
                Section("Measurements") {
                    ForEach(measurements) { measurement in
                        VStack(alignment: .leading, spacing: 4) {
                            if let waist = measurement.waistCm {
                                LabeledContent("Waist", value: String(format: "%.1f cm", waist))
                            }
                            if let left = measurement.leftBicepCm {
                                LabeledContent("Left Bicep", value: String(format: "%.1f cm", left))
                            }
                            if let right = measurement.rightBicepCm {
                                LabeledContent("Right Bicep", value: String(format: "%.1f cm", right))
                            }
                        }
                    }
                }
            }

            if checkin.hasSurveyContent {
                Section("Notes From This Week") {
                    WeeklyCheckinSummary(checkin: checkin)
                }
            }

            if !photos.isEmpty {
                Section("Photos") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(photos) { photo in
                                photoThumbnail(photo)
                            }
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                }
            }

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        .navigationTitle(formattedDate(checkin.checkinDate))
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    @ViewBuilder
    private func photoThumbnail(_ photo: ProgressPhoto) -> some View {
        Group {
            if let url = photoURLs[photo.id] {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        Image(systemName: "photo").foregroundStyle(.secondary)
                    default:
                        ProgressView()
                    }
                }
            } else {
                ProgressView()
            }
        }
        .frame(width: 120, height: 160)
        .background(.quaternary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func load() async {
        do {
            async let measurementsResult = measurementRepository.fetchForWeeklyCheckin(checkin.id)
            async let photosResult = photoRepository.fetchForWeeklyCheckin(checkin.id)
            measurements = try await measurementsResult
            photos = try await photosResult
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        // Signed URLs are fetched one at a time, after the photo rows
        // themselves are already showing (each thumbnail shows its own
        // spinner until its URL resolves) rather than blocking the whole
        // screen on every URL coming back together.
        for photo in photos {
            if let url = try? await photoRepository.signedURL(path: photo.storagePath) {
                photoURLs[photo.id] = url
            }
        }
    }

    private func formattedDate(_ isoDate: String) -> String {
        guard let date = DateFormatting.date(fromISODate: isoDate) else { return isoDate }
        return date.formatted(date: .long, time: .omitted)
    }
}
