import Foundation

/// Session-relative source time, without the old hourly modulo discontinuity.
struct FrameClock {
    private var previous: Double?
    private var elapsed: Double = 0
    struct Tick { let elapsed: Float; let delta: Float; let discontinuity: Bool }
    mutating func advance(_ pts: Double) -> Tick {
        guard pts.isFinite else { return Tick(elapsed: Float(elapsed),delta: 0,discontinuity: true) }
        guard let previous else { self.previous = pts; return Tick(elapsed: 0,delta: 0,discontinuity: false) }
        let delta = pts-previous
        self.previous = pts
        guard delta > 0 else { return Tick(elapsed: Float(elapsed),delta: 0,discontinuity: true) }
        elapsed += delta
        return Tick(elapsed: Float(elapsed),delta: Float(delta),discontinuity: delta > 0.5)
    }
}
