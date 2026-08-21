import AppKit
import Combine
import Foundation
import IOKit.pwr_mgt

/// Reports whether something is deliberately keeping the Mac awake, and what.
///
/// Inspired by omarchy's StayAwake indicator. Replacing the menu bar hides
/// Amphetamine's own icon, so without this there is nothing left to say the
/// machine will not sleep.
final class StayAwakeManager: ObservableObject {
    @Published private(set) var isActive = false
    /// The applications responsible, for the tooltip.
    @Published private(set) var holders: [String] = []

    private var timer: Timer?

    /// Assertions that keep the display or the system awake. Others, such as
    /// preventing disk idle, do not stop the Mac sleeping and are ignored.
    private static let blocking: Set<String> = [
        "PreventUserIdleDisplaySleep",
        "PreventUserIdleSystemSleep",
        "NoDisplaySleepAssertion",
        "NoIdleSleepAssertion",
    ]

    /// macOS itself always holds an assertion while the display is on, so
    /// counting it would leave the indicator permanently lit and useless.
    private static let systemProcesses: Set<String> = [
        "powerd", "coreaudiod", "WindowServer",
    ]

    init(interval: TimeInterval = 5.0) {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) {
            [weak self] _ in
            self?.refresh()
        }
    }

    deinit { timer?.invalidate() }

    private func refresh() {
        let found = Self.blockingProcesses()
        guard found != holders else { return }
        holders = found
        isActive = !found.isEmpty
    }

    /// Read through IOKit rather than by running `pmset`, so a five second
    /// cadence costs nothing. Spawning a process on a timer is what made the
    /// workspace widget expensive.
    private static func blockingProcesses() -> [String] {
        var assertions: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&assertions) == kIOReturnSuccess,
            let byProcess = assertions?.takeRetainedValue()
                as? [NSNumber: [[String: Any]]]
        else { return [] }

        var names: Set<String> = []
        for (pid, entries) in byProcess {
            for entry in entries {
                let type =
                    entry["AssertionTrueType"] as? String
                    ?? entry["AssertionType"] as? String ?? ""
                guard blocking.contains(type) else { continue }

                let name =
                    entry["Process Name"] as? String
                    ?? NSRunningApplication(
                        processIdentifier: pid_t(pid.int32Value))?
                        .localizedName ?? ""
                guard !name.isEmpty, !systemProcesses.contains(name) else {
                    continue
                }
                names.insert(name)
            }
        }
        return names.sorted()
    }
}
