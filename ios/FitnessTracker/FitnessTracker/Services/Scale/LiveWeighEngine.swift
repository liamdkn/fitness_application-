import Foundation

/// Turns a stream of scale readings into "this much was just added".
///
/// A scale reports a number many times a second while the weight settles. The
/// engine waits for the number to hold still, then compares it with the weight
/// it has already accounted for: more means something was added (by the
/// difference), a drop to nothing means the bowl was taken off or the scale
/// tared, so counting starts again from zero. Nothing is reported while
/// pouring, so "50 g of oats" arrives once, when the pour stops.
nonisolated struct LiveWeighEngine {
    enum Event: Equatable {
        /// Grams added since the last stable reading.
        case added(grams: Double)
        /// Weight came off but not to nothing.
        case removed(grams: Double)
        /// Back to (about) zero - bowl lifted or scale tared.
        case reset
    }

    /// How steady the reading must be (grams, top to bottom) to count as settled.
    var tolerance = 0.6
    /// For how long, in seconds.
    var settleSeconds = 0.8
    /// Smaller changes than this are noise, not an ingredient.
    var minimumChange = 1.0

    /// Weight accounted for so far.
    private(set) var committed = 0.0
    private var window: [(time: Date, grams: Double)] = []
    /// The settled value last acted on, so one plateau reports once.
    private var lastSettled: Double?

    init(tolerance: Double = 0.6, settleSeconds: Double = 0.8, minimumChange: Double = 1.0) {
        self.tolerance = tolerance
        self.settleSeconds = settleSeconds
        self.minimumChange = minimumChange
    }

    /// Feed one reading; returns an event when the weight has settled on something new.
    mutating func ingest(grams: Double, at time: Date) -> Event? {
        window.append((time, grams))
        window.removeAll { time.timeIntervalSince($0.time) > settleSeconds * 2 }

        // Settled: readings spanning the settle time that all sit within tolerance.
        guard let oldest = window.first, time.timeIntervalSince(oldest.time) >= settleSeconds,
              window.count >= 3 else { return nil }
        let recent = window.filter { time.timeIntervalSince($0.time) <= settleSeconds }
        guard let low = recent.map(\.grams).min(), let high = recent.map(\.grams).max(),
              high - low <= tolerance, recent.count >= 3 else { return nil }
        let settled = (low + high) / 2

        if let lastSettled, abs(settled - lastSettled) < minimumChange { return nil }
        lastSettled = settled

        if settled < minimumChange {
            let hadWeight = committed >= minimumChange
            committed = 0
            return hadWeight ? .reset : nil
        }
        let delta = settled - committed
        if delta >= minimumChange {
            committed = settled
            return .added(grams: (delta * 10).rounded() / 10)
        }
        if delta <= -minimumChange {
            committed = settled
            return .removed(grams: (-delta * 10).rounded() / 10)
        }
        return nil
    }

    /// Start counting again from whatever is on the scale now (after tapping Tare in the app).
    mutating func rebase(to grams: Double = 0) {
        committed = grams
        lastSettled = nil
        window.removeAll()
    }
}
