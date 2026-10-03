import CoreLocation
import Foundation

/// One point of a run's GPS route: where, and how many seconds into the run.
/// Stored (and encoded) as a bare `[lat, lon, t]` array rather than a keyed
/// object - a route is hundreds of these, and the short form keeps the JSON
/// a third the size.
struct RoutePoint: Codable, Hashable {
    let lat: Double
    let lon: Double
    /// Seconds since the first point.
    let t: Double

    init(lat: Double, lon: Double, t: Double) {
        self.lat = lat
        self.lon = lon
        self.t = t
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        lat = try container.decode(Double.self)
        lon = try container.decode(Double.self)
        t = try container.decode(Double.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(lat)
        try container.encode(lon)
        try container.encode(t)
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    func meters(to other: RoutePoint) -> Double {
        CLLocation(latitude: lat, longitude: lon).distance(from: CLLocation(latitude: other.lat, longitude: other.lon))
    }
}

/// Pure maths over a run's route, kept apart from the views.
enum RouteMath {
    /// At most `maxPoints` evenly spaced points, always keeping the last, with
    /// coordinates rounded to ~1 m (5 decimal places).
    static func downsample(_ locations: [CLLocation], maxPoints: Int = 300) -> [RoutePoint] {
        guard let first = locations.first else { return [] }
        let stride = max(1, Int((Double(locations.count) / Double(maxPoints)).rounded(.up)))
        var points: [RoutePoint] = []
        for (index, location) in locations.enumerated() where index % stride == 0 || index == locations.count - 1 {
            points.append(RoutePoint(
                lat: (location.coordinate.latitude * 100_000).rounded() / 100_000,
                lon: (location.coordinate.longitude * 100_000).rounded() / 100_000,
                t: location.timestamp.timeIntervalSince(first.timestamp)
            ))
        }
        return points
    }

    static func totalMeters(_ points: [RoutePoint]) -> Double {
        zip(points, points.dropFirst()).reduce(0) { $0 + $1.0.meters(to: $1.1) }
    }

    struct Split: Identifiable {
        let index: Int
        let distanceKm: Double
        let seconds: Double
        var id: Int { index }

        /// "5:31" per km, scaled up when the split is shorter than a full km.
        var pace: String {
            guard distanceKm > 0 else { return "-" }
            let perKm = Int((seconds / distanceKm).rounded())
            return String(format: "%d:%02d", perKm / 60, perKm % 60)
        }
    }

    /// Per-kilometre splits. Thinning a route cuts corners, so the summed
    /// point-to-point distance comes out a little short of the distance the
    /// Watch recorded - `totalMeters` (the Watch figure) rescales it so the
    /// splits add up to the real run.
    static func splits(_ points: [RoutePoint], totalMeters watchMeters: Double) -> [Split] {
        guard points.count > 1 else { return [] }
        let routeMeters = totalMeters(points)
        guard routeMeters > 0 else { return [] }
        let scale = watchMeters > 0 ? watchMeters / routeMeters : 1

        var splits: [Split] = []
        var cumulative = 0.0
        var nextKm = 1
        var lastSplitTime = 0.0
        for (a, b) in zip(points, points.dropFirst()) {
            let segment = a.meters(to: b) * scale
            guard segment > 0 else { continue }
            while cumulative + segment >= Double(nextKm) * 1000 {
                let fraction = (Double(nextKm) * 1000 - cumulative) / segment
                let crossing = a.t + (b.t - a.t) * fraction
                splits.append(Split(index: nextKm, distanceKm: 1, seconds: crossing - lastSplitTime))
                lastSplitTime = crossing
                nextKm += 1
            }
            cumulative += segment
        }
        // Whatever's left past the last whole km.
        let remainder = (cumulative - Double(nextKm - 1) * 1000) / 1000
        if remainder >= 0.05, let end = points.last {
            splits.append(Split(index: nextKm, distanceKm: remainder, seconds: end.t - lastSplitTime))
        }
        return splits
    }

    struct Segment: Identifiable {
        let id: Int
        let from: CLLocationCoordinate2D
        let to: CLLocationCoordinate2D
        /// 0 = slowest part of this run, 1 = fastest - colour, not a pace.
        let relativeSpeed: Double
    }

    /// Route cut into short segments, each tagged with how fast it was
    /// relative to the rest of the run (smoothed over a few neighbours so GPS
    /// jitter doesn't flicker the colours) - the map's pace colouring.
    static func segments(_ points: [RoutePoint]) -> [Segment] {
        guard points.count > 1 else { return [] }
        var speeds: [Double] = []
        for (a, b) in zip(points, points.dropFirst()) {
            let dt = b.t - a.t
            speeds.append(dt > 0 ? a.meters(to: b) / dt : 0)
        }
        let window = 4
        let smoothed = speeds.indices.map { index -> Double in
            let lower = max(0, index - window), upper = min(speeds.count - 1, index + window)
            let slice = speeds[lower...upper]
            return slice.reduce(0, +) / Double(slice.count)
        }
        // 10th-90th percentile, so one slow stop or sprint doesn't flatten
        // the whole gradient.
        let sorted = smoothed.sorted()
        let low = sorted[Int(Double(sorted.count - 1) * 0.1)]
        let high = sorted[Int(Double(sorted.count - 1) * 0.9)]
        let span = max(high - low, 0.01)
        return smoothed.indices.map { index in
            Segment(
                id: index,
                from: points[index].coordinate,
                to: points[index + 1].coordinate,
                relativeSpeed: min(1, max(0, (smoothed[index] - low) / span))
            )
        }
    }
}
