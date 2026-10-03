import MapKit
import SwiftUI

/// One run: its route on a map (coloured by pace - green where it was fast,
/// red where it slowed), the numbers the Watch recorded, and kilometre splits.
struct RunDetailView: View {
    let session: CardioTrackingSession

    @State private var route: [RoutePoint] = []
    @State private var camera: MapCameraPosition = .automatic
    @State private var isLoading = true
    private let repository = CardioSessionRepository()

    private var segments: [RouteMath.Segment] { RouteMath.segments(route) }
    private var splits: [RouteMath.Split] { RouteMath.splits(route, totalMeters: session.distanceMeters ?? 0) }
    private var duration: TimeInterval { session.elapsed() }

    var body: some View {
        List {
            if session.hasRoute {
                Section {
                    mapView
                        .frame(height: 300)
                        .listRowInsets(EdgeInsets())
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    if !route.isEmpty {
                        paceLegend
                    }
                }
                .listRowBackground(Color.clear)
            }

            Section {
                statsGrid
            }

            if !splits.isEmpty {
                Section("Splits") {
                    ForEach(splits) { split in
                        HStack {
                            Text(split.distanceKm >= 1 ? "\(split.index) km" : RunFormat.km(split.distanceKm))
                            Spacer()
                            Text("\(split.pace) /km")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(session.startedAt.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadRoute() }
    }

    private var mapView: some View {
        Map(position: $camera) {
            ForEach(segments) { segment in
                MapPolyline(coordinates: [segment.from, segment.to])
                    .stroke(color(for: segment.relativeSpeed), lineWidth: 5)
            }
            if let start = route.first {
                Annotation("Start", coordinate: start.coordinate) {
                    Circle().fill(.green).frame(width: 14, height: 14)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }
            if let end = route.last, route.count > 1 {
                Annotation("Finish", coordinate: end.coordinate) {
                    Circle().fill(.red).frame(width: 14, height: 14)
                        .overlay(Circle().stroke(.white, lineWidth: 2))
                }
            }
        }
        .mapStyle(.standard)
        .overlay {
            if isLoading {
                ProgressView()
            } else if route.isEmpty {
                Text("Route unavailable").foregroundStyle(.secondary)
            }
        }
    }

    private var paceLegend: some View {
        HStack(spacing: 8) {
            Text("Slower").font(.caption2).foregroundStyle(.secondary)
            LinearGradient(colors: [color(for: 0), color(for: 0.5), color(for: 1)], startPoint: .leading, endPoint: .trailing)
                .frame(height: 6)
                .clipShape(Capsule())
            Text("Faster").font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)], alignment: .leading, spacing: 16) {
            stat("Distance", session.distanceMeters.map { RunFormat.km($0 / 1000) }, color: .cyan)
            stat("Time", clock(duration), color: .yellow)
            stat("Avg pace", RunFormat.pace(seconds: duration, meters: session.distanceMeters ?? 0), color: .teal)
            stat("Avg heart rate", session.avgHeartRate.map { "\($0) bpm" }, color: .red)
            stat("Active calories", session.activeCalories.map { "\(Int($0)) cal" }, color: .pink)
            stat("Total calories", session.totalCalories.map { "\(Int($0)) cal" }, color: .pink)
            stat("Elevation gain", session.elevationGainM.map { "\(Int($0.rounded())) m" }, color: .green)
            stat("Avg power", session.avgPowerW.map { "\($0) W" }, color: .mint)
            stat("Avg cadence", session.avgCadenceSPM.map { "\($0) spm" }, color: .teal)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func stat(_ label: String, _ value: String?, color: Color) -> some View {
        if let value {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.title3.bold()).foregroundStyle(color)
            }
        }
    }

    /// Red (slow) through yellow to green (fast).
    private func color(for relativeSpeed: Double) -> Color {
        Color(hue: 0.0 + 0.36 * relativeSpeed, saturation: 0.85, brightness: 0.95)
    }

    private func clock(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        let (h, m, s) = (total / 3600, (total % 3600) / 60, total % 60)
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    private func loadRoute() async {
        defer { isLoading = false }
        guard session.hasRoute else { return }
        route = (try? await repository.fetchRoute(sessionId: session.id)) ?? []
        guard !route.isEmpty else { return }
        var rect = MKMapRect.null
        for point in route {
            let mapPoint = MKMapPoint(point.coordinate)
            rect = rect.union(MKMapRect(x: mapPoint.x, y: mapPoint.y, width: 0, height: 0))
        }
        // Pad so the route isn't jammed against the edges.
        camera = .rect(rect.insetBy(dx: -rect.width * 0.2 - 200, dy: -rect.height * 0.2 - 200))
    }
}
