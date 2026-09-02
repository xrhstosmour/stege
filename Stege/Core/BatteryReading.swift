import Foundation

/// What the battery widget decides from a charge level, with no drawing in it.
///
/// The thresholds and the fill geometry were tuned by eye against renders and
/// are easy to break by accident, so they are here rather than inside the view.
enum BatteryReading {
    /// Which state the level falls into.
    enum State: Equatable {
        case charging
        case critical
        case warning
        case normal
    }

    static func state(
        level: Int, isCharging: Bool, warningLevel: Int, criticalLevel: Int
    ) -> State {
        if isCharging { return .charging }
        if level <= criticalLevel { return .critical }
        if level <= warningLevel { return .warning }
        return .normal
    }

    /// How solid the level is drawn behind the number.
    ///
    /// macOS fills its battery at full strength because it puts nothing on
    /// top. With the number in the body the fill is a background before it is a
    /// reading, and the digits have to stay legible over it at every level, so
    /// the plain one is held well back. The three that mean something are not.
    static func fillOpacity(state: State, showsPercentage: Bool) -> Double {
        guard showsPercentage else { return 1 }
        switch state {
        case .charging: return 0.75
        case .critical: return 1
        case .warning: return 0.85
        case .normal: return 0.35
        }
    }

    /// The width of the fill inside a body of `innerWidth` points.
    ///
    /// Never quite nothing: a battery that has just run out still has a
    /// battery's shape, and a fill of zero width reads as a drawing error. It
    /// divided by 110 once, so a full battery drew short of the end and never
    /// looked full.
    static func fillWidth(level: Int, innerWidth: Double) -> Double {
        let clamped = Double(min(100, max(0, level)))
        return max(1.5, innerWidth * clamped / 100)
    }
}
