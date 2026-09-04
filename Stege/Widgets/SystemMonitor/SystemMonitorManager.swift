import Combine
import Darwin
import Foundation

/// Network throughput, read straight from the kernel.
///
/// No process spawning: upstream's widgets shell out, which is what made the
/// workspace polling expensive. `sysctl`-backed interface counters are
/// in-process calls costing microseconds, so a two second cadence is
/// affordable.
final class SystemMonitorManager: ObservableObject {
    /// Bytes per second since the previous sample.
    @Published private(set) var bytesReceivedPerSecond: Double = 0
    @Published private(set) var bytesSentPerSecond: Double = 0

    /// One per process. The Wi-Fi popup wants these readings, and two managers
    /// would mean two timers polling the same interface counters a second
    /// apart. Built on first use, so a bar without that widget starts nothing
    /// at all.
    static let shared = SystemMonitorManager()

    private var timer: Timer?
    private var previousTraffic: (received: UInt64, sent: UInt64, at: Date)?
    private let interval: TimeInterval

    init(interval: TimeInterval = 2.0) {
        self.interval = interval
        refreshTraffic()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) {
            [weak self] _ in
            self?.refreshTraffic()
        }
    }

    deinit {
        timer?.invalidate()
    }

    /// Interface counters are cumulative, so throughput is the delta over the
    /// real elapsed time rather than over the nominal interval, which drifts
    /// whenever the run loop is busy.
    private func refreshTraffic() {
        guard let totals = Self.interfaceTotals() else { return }
        let now = Date()
        defer { previousTraffic = (totals.received, totals.sent, now) }
        guard let last = previousTraffic else { return }

        let elapsed = now.timeIntervalSince(last.at)
        guard elapsed > 0 else { return }
        // Counters reset when an interface disappears, so ignore a decrease
        // rather than reporting a negative rate.
        let received = totals.received >= last.received
            ? Double(totals.received - last.received) / elapsed : 0
        let sent = totals.sent >= last.sent
            ? Double(totals.sent - last.sent) / elapsed : 0
        bytesReceivedPerSecond = received
        bytesSentPerSecond = sent
    }

    /// Byte counters summed over every physical interface.
    ///
    /// Loopback is excluded, otherwise local traffic between processes on this
    /// machine is reported as network throughput.
    private static func interfaceTotals() -> (received: UInt64, sent: UInt64)? {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return nil }
        defer { freeifaddrs(addresses) }

        var received: UInt64 = 0
        var sent: UInt64 = 0
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }
            guard let name = String(validatingUTF8: current.pointee.ifa_name),
                !name.hasPrefix("lo"),
                current.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
                let data = current.pointee.ifa_data
            else { continue }
            let stats = data.assumingMemoryBound(to: if_data.self).pointee
            received += UInt64(stats.ifi_ibytes)
            sent += UInt64(stats.ifi_obytes)
        }
        return (received, sent)
    }
}
