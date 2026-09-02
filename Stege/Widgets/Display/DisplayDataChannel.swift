import CoreGraphics
import Foundation
import IOKit

/// Brightness on an external monitor, over the cable.
///
/// `DisplayServicesGetBrightness` answers only for the built-in panel. On an
/// external it returns error 1000, which is why every display but the laptop's
/// own used to have no slider at all. What does work is DDC/CI, the small
/// command protocol every monitor with an on-screen menu speaks over the
/// display cable's I2C lines. Reading VCP feature 0x10 gives the same
/// luminance the monitor's own buttons set, and writing it moves the backlight
/// rather than dimming the picture in software.
///
/// On Apple Silicon the I2C lines are reached through `IOAVService`, four
/// unexported C functions in `IOKit`. They need no entitlement, checked on this
/// machine: both attached monitors answered.
///
/// Nothing here is guessed. Each display is matched to its port by the serial
/// number in its EDID, which macOS publishes on the framebuffer service and
/// CoreGraphics publishes for the display ID, so the wrong monitor cannot be
/// dimmed.
enum DisplayDataChannel {
    /// The I2C address every DDC/CI monitor listens on, and the offset the
    /// transaction starts at.
    private static let address: UInt32 = 0x37
    private static let offset: UInt32 = 0x51
    /// Whether this build can talk to a monitor at all.
    static var isAvailable: Bool { create != nil && write != nil && read != nil }

    // MARK: - Reading and writing

    /// 0 to 1, or nil when the monitor does not answer.
    static func brightness(of id: CGDirectDisplayID) -> Float? {
        guard let service = service(for: id) else { return nil }
        guard let (current, maximum) = readLuminance(service), maximum > 0 else {
            return nil
        }
        return Float(current) / Float(maximum)
    }

    /// Returns whether the monitor took it.
    @discardableResult
    static func setBrightness(_ value: Float, on id: CGDirectDisplayID) -> Bool {
        guard let service = service(for: id), let write else { return false }
        // The scale the monitor reports, not a fixed 0 to 100. Most report 100
        // but the standard does not require it.
        let maximum = maximums[id] ?? readLuminance(service)?.1 ?? 100
        maximums[id] = maximum
        var request = DisplayDataChannelMessage.writeRequest(
            value: DisplayDataChannelMessage.level(
                for: value, maximum: maximum))
        return write(service, address, offset, &request, UInt32(request.count))
            == KERN_SUCCESS
    }

    /// Current and maximum, straight from the monitor.
    ///
    /// Read on a retry loop because DDC has no handshake: the monitor answers
    /// when it is ready, and a read that lands early comes back with a stale
    /// header. `DisplayDataChannelMessage.parse` is what tolerates that.
    private static func readLuminance(_ service: CFTypeRef) -> (Int, Int)? {
        guard let write, let read else { return nil }
        for _ in 0..<3 {
            var request = DisplayDataChannelMessage.readRequest()
            guard write(service, address, offset, &request,
                        UInt32(request.count)) == KERN_SUCCESS
            else { continue }
            usleep(60_000)

            var reply = [UInt8](repeating: 0, count: 12)
            guard read(service, address, offset, &reply,
                       UInt32(reply.count)) == KERN_SUCCESS,
                let reading = DisplayDataChannelMessage.parse(reply)
            else {
                usleep(40_000)
                continue
            }
            return (reading.current, reading.maximum)
        }
        return nil
    }

    /// One read per display, kept because asking for the scale costs a full
    /// round trip and it does not change while the monitor is plugged in.
    nonisolated(unsafe) private static var maximums: [CGDirectDisplayID: Int] = [:]

    // MARK: - Finding the port a display is on

    /// Cached because walking the registry twice per slider drag is wasteful,
    /// and cleared whenever the displays change.
    nonisolated(unsafe) private static var services:
        [CGDirectDisplayID: CFTypeRef] = [:]

    static func forget() {
        services.removeAll()
        maximums.removeAll()
    }

    private static func service(for id: CGDirectDisplayID) -> CFTypeRef? {
        if let cached = services[id] { return cached }
        guard let create, CGDisplayIsBuiltin(id) == 0 else { return nil }
        guard let port = port(for: id) else { return nil }

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault, IOServiceMatching("DCPAVServiceProxy"),
            &iterator) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iterator) }

        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            defer {
                IOObjectRelease(entry)
                entry = IOIteratorNext(iterator)
            }
            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(entry, kIOServicePlane, &parent)
                == KERN_SUCCESS
            else { continue }
            var name = [CChar](repeating: 0, count: 256)
            IORegistryEntryGetName(parent, &name)
            IOObjectRelease(parent)
            guard String(cString: name).hasPrefix(port + ":") else { continue }
            guard let service = create(kCFAllocatorDefault, entry)?
                .takeRetainedValue()
            else { continue }
            services[id] = service
            return service
        }
        return nil
    }

    /// The `dispextN` node this display is plugged into, matched by the serial
    /// number in its EDID. Position in the registry is not used: the order the
    /// ports enumerate in has nothing to do with the order macOS numbers the
    /// displays in.
    private static func port(for id: CGDirectDisplayID) -> String? {
        let serial = Int(CGDisplaySerialNumber(id))
        let model = Int(CGDisplayModelNumber(id))
        guard serial != 0 else { return nil }

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault, IOServiceMatching("IOMobileFramebufferShim"),
            &iterator) == KERN_SUCCESS
        else { return nil }
        defer { IOObjectRelease(iterator) }

        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            defer {
                IOObjectRelease(entry)
                entry = IOIteratorNext(iterator)
            }
            var path = [CChar](repeating: 0, count: 1024)
            guard IORegistryEntryGetPath(entry, kIOServicePlane, &path)
                == KERN_SUCCESS
            else { continue }
            let text = String(cString: path)
            guard let range = text.range(
                of: "dispext[0-9]+", options: .regularExpression)
            else { continue }

            var properties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(
                entry, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                let all = properties?.takeRetainedValue() as? [String: Any],
                let attributes = all["DisplayAttributes"] as? [String: Any],
                let product = attributes["ProductAttributes"] as? [String: Any]
            else { continue }
            guard product["SerialNumber"] as? Int == serial,
                product["ProductID"] as? Int == model
            else { continue }
            return String(text[range])
        }
        return nil
    }

    // MARK: - The unexported calls

    private typealias CreateService = @convention(c) (
        CFAllocator?, io_service_t
    ) -> Unmanaged<CFTypeRef>?
    private typealias Transfer = @convention(c) (
        CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32
    ) -> IOReturn

    private static let iokit: UnsafeMutableRawPointer? = dlopen(
        "/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY)

    private static let create: CreateService? = {
        guard let iokit, let symbol = dlsym(iokit, "IOAVServiceCreateWithService")
        else { return nil }
        return unsafeBitCast(symbol, to: CreateService.self)
    }()

    private static let write: Transfer? = {
        guard let iokit, let symbol = dlsym(iokit, "IOAVServiceWriteI2C")
        else { return nil }
        return unsafeBitCast(symbol, to: Transfer.self)
    }()

    private static let read: Transfer? = {
        guard let iokit, let symbol = dlsym(iokit, "IOAVServiceReadI2C")
        else { return nil }
        return unsafeBitCast(symbol, to: Transfer.self)
    }()
}
