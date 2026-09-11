import Foundation

struct AngleCalibration {
    let duration: TimeInterval = 1.5
    var tolerance: Double = 2
    private var anchor: Double?
    private var began: TimeInterval = 0
    private var previousTime: TimeInterval?
    private var sum = 0.0
    private var count = 0

    mutating func reset() {
        anchor = nil
        previousTime = nil
        sum = 0
        count = 0
    }

    // Fixed anchor prevents slow cumulative drift from qualifying as stable.
    // A sensor gap never counts toward the hold duration.
    mutating func ingest(_ angle: Double?, at time: TimeInterval) -> Double? {
        guard let angle, angle >= 0, angle <= 180 else { reset(); return nil }
        if let previousTime, time - previousTime > 0.5 || time < previousTime { reset() }
        previousTime = time
        if anchor == nil || abs(angle - anchor!) > tolerance {
            anchor = angle
            began = time
            sum = angle
            count = 1
            return nil
        }
        sum += angle
        count += 1
        guard time - began >= duration else { return nil }
        let result = (sum / Double(count)).rounded()
        reset()
        return result
    }
}
