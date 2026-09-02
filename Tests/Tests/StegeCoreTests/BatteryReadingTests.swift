import Testing

@testable import StegeCore

struct BatteryReadingTests {
    private func state(_ level: Int, charging: Bool = false)
        -> BatteryReading.State
    {
        BatteryReading.state(
            level: level, isCharging: charging,
            warningLevel: 30, criticalLevel: 10)
    }

    @Test func chargingWinsOverEveryLevel() {
        #expect(state(5, charging: true) == .charging)
        #expect(state(100, charging: true) == .charging)
    }

    @Test func theThresholdsAreInclusive() {
        #expect(state(10) == .critical)
        #expect(state(11) == .warning)
        #expect(state(30) == .warning)
        #expect(state(31) == .normal)
    }

    @Test func aFlatBatteryIsCritical() {
        #expect(state(0) == .critical)
    }

    @Test func theFillIsHeldBackOnlyBehindTheNumber() {
        #expect(
            BatteryReading.fillOpacity(state: .normal, showsPercentage: true)
                == 0.35)
        #expect(
            BatteryReading.fillOpacity(state: .normal, showsPercentage: false)
                == 1)
    }

    @Test func theStatesWorthNoticingAreDrawnStrongly() {
        #expect(
            BatteryReading.fillOpacity(state: .critical, showsPercentage: true)
                == 1)
        #expect(
            BatteryReading.fillOpacity(state: .warning, showsPercentage: true)
                > BatteryReading.fillOpacity(
                    state: .normal, showsPercentage: true))
    }

    /// It divided by 110 once, so a full battery drew short of the end and
    /// never looked full.
    @Test func aFullBatteryFillsTheWholeBody() {
        #expect(BatteryReading.fillWidth(level: 100, innerWidth: 26.5) == 26.5)
    }

    @Test func anEmptyBatteryStillHasAShape() {
        #expect(BatteryReading.fillWidth(level: 0, innerWidth: 26.5) == 1.5)
    }

    @Test func theFillIsProportional() {
        #expect(BatteryReading.fillWidth(level: 50, innerWidth: 26.5) == 13.25)
    }

    @Test func anImpossibleLevelIsClamped() {
        #expect(BatteryReading.fillWidth(level: 140, innerWidth: 26.5) == 26.5)
        #expect(BatteryReading.fillWidth(level: -5, innerWidth: 26.5) == 1.5)
    }
}
