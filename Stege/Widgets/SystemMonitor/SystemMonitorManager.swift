import Combine
import Darwin
import Foundation

/// CPU and memory usage, read straight from the kernel.
///
/// No process spawning: upstream's widgets shell out, which is what made the
/// workspace polling expensive. `host_statistics64` and `sysctl` are in-process
/// calls costing microseconds, so a two second cadence is affordable.
final class SystemMonitorManager: ObservableObject {
    @Published private(set) var cpuUsage: Double = 0
    @Published private(set) var memoryUsage: Double = 0
    /// Bytes per second since the previous sample.
    @Published private(set) var bytesReceivedPerSecond: Double = 0
    @Published private(set) var bytesSentPerSecond: Double = 0
    /// Free and total bytes on the boot volume, or nil when it cannot be read.
    @Published private(set) var diskFree: Int64?
    @Published private(set) var diskTotal: Int64?

    /// One per process. The monitor widget and the Wi-Fi popup both want these
    /// readings, and two managers would mean two timers polling the same
    /// `host_statistics` and the same interface counters a second apart. Built
    /// on first use, so a bar with neither of those widgets in it starts
    /// nothing at all.
    static let shared = SystemMonitorManager()

    private var timer: Timer?
    private var previousTicks: (idle: UInt64, total: UInt64)?
    private var previousTraffic: (received: UInt64, sent: UInt64, at: Date)?
    private let interval: TimeInterval

    init(interval: TimeInterval = 2.0) {
        self.interval = interval
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) {
            [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        timer?.invalidate()
    }

    private func refresh() {
        if let cpu = Self.cpuUsage(previous: &previousTicks) { cpuUsage = cpu }
        if let memory = Self.memoryUsage() { memoryUsage = memory }
        refreshTraffic()
    }

    /// Space on the boot volume.
    ///
    /// `volumeAvailableCapacityForImportantUsage` rather than the raw free
    /// figure, because macOS will evict purgeable space to make room and the
    /// raw number reads far lower than what is actually usable. This is the
    /// number Finder shows.
    func updateDisk() {
        let url = URL(fileURLWithPath: "/")
        guard
            let values = try? url.resourceValues(forKeys: [
                .volumeTotalCapacityKey,
                .volumeAvailableCapacityForImportantUsageKey,
            ])
        else { return }
        diskTotal = values.volumeTotalCapacity.map(Int64.init)
        diskFree = values.volumeAvailableCapacityForImportantUsage
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

    /// CPU load as a fraction, derived from the delta between two tick counts.
    ///
    /// The counters are cumulative since boot, so a single reading describes the
    /// whole uptime rather than the present. The first call therefore only
    /// establishes a baseline and reports nothing.
    private static func cpuUsage(previous: inout (idle: UInt64, total: UInt64)?)
        -> Double?
    {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        // `cpu_ticks` is indexed by CPU_STATE_*: user 0, system 1, idle 2,
        // nice 3. Reading index 3 as idle counts nice ticks, which are near
        // zero on a desktop, and pins the reading at 100%.
        let user = UInt64(info.cpu_ticks.0)
        let system = UInt64(info.cpu_ticks.1)
        let idle = UInt64(info.cpu_ticks.2)
        let nice = UInt64(info.cpu_ticks.3)
        let total = user + system + idle + nice

        defer { previous = (idle, total) }
        guard let last = previous else { return nil }

        let idleDelta = idle &- last.idle
        let totalDelta = total &- last.total
        guard totalDelta > 0 else { return nil }
        return min(1, max(0, 1 - Double(idleDelta) / Double(totalDelta)))
    }

    /// Memory in use as a fraction of physical memory.
    ///
    /// Counts what macOS itself calls used memory: everything except free and
    /// purgeable pages. Speculative and external pages are excluded because they
    /// are reclaimable on demand and counting them reports a machine as full
    /// when it is not.
    private static func memoryUsage() -> Double? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let pageSize = UInt64(vm_kernel_page_size)
        let active = UInt64(stats.active_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let used = active + wired + compressed

        let total = ProcessInfo.processInfo.physicalMemory
        guard total > 0 else { return nil }
        return min(1, Double(used) / Double(total))
    }
}
