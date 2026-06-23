import Foundation

/// Smooths the noisy per-update tempo estimates into a steady display value.
///
/// The raw detector reading is recomputed roughly once a second and naturally
/// jitters (and occasionally locks an octave off). This applies a rolling
/// median — which suppresses frame-to-frame jitter *and* the occasional half/
/// double-tempo outlier — plus hysteresis so the shown number only moves on a
/// real change, not ±1 noise. Real tempo changes still propagate as the window
/// fills with the new value. Pure value type; the owner serializes access.
public struct BPMStabilizer {
    private var history: [Double] = []
    private var shown: Double?
    private let windowSize: Int
    private let changeThreshold: Double

    public init(windowSize: Int = 5, changeThreshold: Double = 3) {
        self.windowSize = max(3, windowSize)
        self.changeThreshold = changeThreshold
    }

    /// The current stabilized BPM, or nil until enough readings have arrived.
    public var stableBPM: Double? { shown }

    /// Feed one raw per-update estimate; returns the stabilized value.
    @discardableResult
    public mutating func add(_ raw: Double) -> Double? {
        guard raw > 0 else { return shown }
        history.append(raw)
        if history.count > windowSize {
            history.removeFirst()
        }

        // Report from the very first reading (median of what we have) so the
        // pill shows promptly; the median firms up as more readings arrive.
        let median = history.sorted()[history.count / 2]
        if let current = shown {
            if abs(median - current) >= changeThreshold {
                shown = median
            }
        } else {
            shown = median
        }
        return shown
    }

    public mutating func reset() {
        history.removeAll()
        shown = nil
    }
}
