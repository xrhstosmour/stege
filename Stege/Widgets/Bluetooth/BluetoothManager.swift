import Combine
import CoreBluetooth
import Darwin
import Foundation
import IOBluetooth

/// A Bluetooth device, paired or merely in range.
struct BluetoothDevice: Identifiable, Equatable {
    let id: String
    let name: String
    /// 0 to 1, or nil when the device does not report a battery level.
    let batteryLevel: Double?
    let isConnected: Bool
    let isPaired: Bool
    /// What the device says it is, from its class of device record, so the row
    /// can draw the right symbol without guessing from the name.
    var kind: Kind = .unknown

    enum Kind {
        case keyboard
        case pointing
        case headphones
        case speaker
        case phone
        case computer
        case watch
        case unknown
    }
}

/// Bluetooth power state and connected devices.
///
/// `IOBluetooth` is used rather than `CoreBluetooth`: `CoreBluetooth` describes
/// devices this app could connect to as a client, and would prompt for
/// permission, while the bar only needs to report what the system is already
/// connected to.
final class BluetoothManager: NSObject, ObservableObject {
    /// One instance. Bluetooth state is a property of the machine, not of a
    /// bar, and there is one bar per screen: two managers on a two-monitor
    /// setup were each polling the same radio on the same 30s timer.
    static let shared = BluetoothManager()

    @Published private(set) var isPoweredOn = false
    /// Everything the system has paired, connected or not, so the popup can
    /// connect one back rather than only report what is already up.
    @Published private(set) var devices: [BluetoothDevice] = []
    /// Devices found by an inquiry that are not paired yet.
    @Published private(set) var discovered: [BluetoothDevice] = []
    @Published private(set) var isScanning = false
    /// Ends a scan that the radio never reports the end of. See `startScan`.
    private var scanDeadline: Timer?
    /// The address a connect, disconnect or pair is in flight for.
    /// The device an action is in flight for, and which action it is, so a row
    /// can say `Connecting…` rather than only spinning. Wi-Fi keeps its scan
    /// and its join apart for the same reason.
    enum Activity {
        case connecting
        case disconnecting
        case pairing

        var label: String {
            switch self {
            case .connecting: return "Connecting…"
            case .disconnecting: return "Disconnecting…"
            case .pairing: return "Pairing…"
            }
        }
    }

    @Published private(set) var busy: String?
    @Published private(set) var activity: Activity?
    /// Set when an action did not take, so the popup can say so.
    @Published private(set) var failure: String?
    /// Whether the app is allowed to read Bluetooth at all.
    ///
    /// Read through `CBManager.authorization`, which reports the current state
    /// without instantiating a central manager and therefore without prompting.
    /// `IOBluetooth` exposes no equivalent, and without this a denied
    /// permission is indistinguishable from Bluetooth simply being switched
    /// off, so the widget cannot tell the user which one it is.
    @Published private(set) var isAuthorized = true

    /// Set while the Control Center switch is being pressed, so the popup can
    /// show that something is happening rather than looking unresponsive.
    @Published private(set) var isSwitchingPower = false

    private var timer: Timer?
    /// Serialises reads so a slow one cannot overlap the next tick.
    private let queue = DispatchQueue(label: "stege.bluetooth", qos: .utility)
    private var isReading = false

    /// Held so they can be unregistered. `IOBluetooth` hands back a
    /// notification object per registration, and dropping it without
    /// unregistering leaves the callback live.
    private var connectNotification: IOBluetoothUserNotification?
    private var disconnectNotifications: [IOBluetoothUserNotification] = []

    /// Held for the length of one scan or one pairing. Both are one at a time:
    /// the radio can only do one inquiry, and pairing two devices at once is
    /// not something the popup can express.
    private var activeInquiry: IOBluetoothDeviceInquiry?
    private var activePairing: IOBluetoothDevicePair?

    /// A slow safety net, not the main refresh.
    ///
    /// Connecting and disconnecting are delivered as notifications, so the
    /// timer no longer carries them. What it still covers has no notification
    /// at all: the controller being switched on or off, and battery levels,
    /// which macOS writes into its preferences without announcing.
    private init(interval: TimeInterval = 30.0) {
        super.init()
        refresh()
        registerForConnections()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) {
            [weak self] _ in
            self?.refresh()
        }
    }

    deinit {
        timer?.invalidate()
        scanDeadline?.invalidate()
        activeInquiry?.stop()
        connectNotification?.unregister()
        disconnectNotifications.forEach { $0.unregister() }
    }

    private func registerForConnections() {
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(deviceConnected(_:device:)))

        // Only future connections are announced, so anything already connected
        // when the bar starts needs its disconnect notification taken here or
        // unplugging it would go unnoticed until the safety net ran.
        queue.async { [weak self] in
            guard let self,
                let paired = IOBluetoothDevice.pairedDevices()
                    as? [IOBluetoothDevice]
            else { return }
            let connected = paired.filter { $0.isConnected() }
            DispatchQueue.main.async {
                for device in connected {
                    self.watchForDisconnect(of: device)
                }
            }
        }
    }

    private func watchForDisconnect(of device: IOBluetoothDevice) {
        guard
            let notification = device.register(
                forDisconnectNotification: self,
                selector: #selector(deviceDisconnected(_:device:)))
        else { return }
        disconnectNotifications.append(notification)
    }

    @objc private func deviceConnected(
        _ notification: IOBluetoothUserNotification, device: IOBluetoothDevice
    ) {
        // Registered per device, because `IOBluetooth` has no global
        // disconnect notification the way it has a global connect one.
        watchForDisconnect(of: device)
        refresh()
    }

    @objc private func deviceDisconnected(
        _ notification: IOBluetoothUserNotification, device: IOBluetoothDevice
    ) {
        notification.unregister()
        disconnectNotifications.removeAll { $0 === notification }
        refresh()
    }

    /// Reads on a background queue, never on the main thread.
    ///
    /// `IOBluetooth` access is gated by TCC, and the very first call blocks
    /// while the system decides whether to prompt. Doing that on the main
    /// thread freezes the whole bar, not just this widget: every other widget
    /// stops rendering until it returns.
    private func refresh() {
        guard !isReading else { return }
        isReading = true

        let authorized = CBManager.authorization == .allowedAlways

        queue.async { [weak self] in
            guard let self else { return }
            guard authorized else {
                DispatchQueue.main.async {
                    self.isReading = false
                    self.isAuthorized = false
                    self.isPoweredOn = false
                    self.devices = []
                }
                return
            }
            let powered =
                IOBluetoothHostController.default()?.powerState
                == kBluetoothHCIPowerStateON
            // A controller that is off has nothing paired to it that can be
            // reached. `IOBluetoothDevice.isConnected()` keeps answering yes
            // from its cached objects for a while after the radio goes down,
            // so asking it at all here means listing devices as connected to a
            // radio that is not running.
            let connected = powered ? Self.connectedDevices() : []

            DispatchQueue.main.async {
                self.isReading = false
                self.isAuthorized = true
                // Assigned separately. These used to share one guard, so a
                // read where only the power had changed wrote the same stale
                // device array straight back and the list kept its blue
                // connected dots after the radio was switched off.
                if powered != self.isPoweredOn { self.isPoweredOn = powered }
                if connected != self.devices { self.devices = connected }
            }
        }
    }

    /// Turns the radio on or off.
    ///
    /// `IOBluetoothPreferenceSetControllerPowerState` is not in any published
    /// header, but it is a plain C function exported by `IOBluetooth` and it is
    /// what `blueutil` has always used. It sets the state directly and returns
    /// immediately.
    ///
    /// This used to press the switch in Control Center's own Bluetooth panel,
    /// which meant the panel visibly opened and closed every time. Nothing
    /// about the bar should look like it is operating the menu bar it replaced,
    /// so where a real call exists it is used, and the panel is left for the
    /// two settings that have no call at all.
    func setPower(_ on: Bool) {
        guard !isSwitchingPower, on != isPoweredOn else { return }
        guard let set = Self.setControllerPowerState else {
            failure = "Bluetooth cannot be switched on this system"
            return
        }
        isSwitchingPower = true
        failure = nil
        _ = set(on ? 1 : 0)
        // Left true until the read-back sees the radio move. It used to be
        // cleared on the next line, in the same runloop tick, so SwiftUI never
        // rendered a frame with it set and the header spinner was unreachable.
        readBackPower(until: !on, attempt: 0)
    }

    private typealias SetPowerState = @convention(c) (Int32) -> Int32

    /// Looked up once. `IOBluetooth` is already linked, but the symbol is not
    /// declared anywhere, so it is reached by name rather than called directly.
    private static let setControllerPowerState: SetPowerState? = {
        guard
            let handle = dlopen(
                "/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth",
                RTLD_LAZY),
            let symbol = dlsym(
                handle, "IOBluetoothPreferenceSetControllerPowerState")
        else { return nil }
        return unsafeBitCast(symbol, to: SetPowerState.self)
    }()

    /// The radio takes a moment to come up, and the only thing watching it
    /// otherwise is a thirty second timer, so the popup would sit on the old
    /// answer until long after the switch had moved.
    private func readBackPower(until previous: Bool, attempt: Int) {
        guard attempt < 12 else {
            // Gave up. The radio never reported the move, so let the switch go
            // rather than leaving it spinning for the rest of the session.
            isSwitchingPower = false
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            [weak self] in
            guard let self else { return }
            self.refresh()
            guard self.isPoweredOn == previous else {
                // The power has moved, but the device list settles after it
                // does, so keep reading for a moment rather than handing the
                // next thirty seconds to the safety-net timer.
                self.isSwitchingPower = false
                self.settle(attempt: 0)
                return
            }
            self.readBackPower(until: previous, attempt: attempt + 1)
        }
    }

    /// A few more reads once the power has moved, so devices that drop off
    /// after the controller does are noticed straight away.
    private func settle(attempt: Int) {
        guard attempt < 4 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            self.refresh()
            self.settle(attempt: attempt + 1)
        }
    }

    /// What the device is, from the class of device record every Bluetooth
    /// device carries.
    ///
    /// This used to be guessed from the name, which failed on anything not
    /// spelling out what it was: `MX Master 3S` contains neither "mouse" nor
    /// "trackpad". The record is the device's own answer.
    private static func kind(of device: IOBluetoothDevice)
        -> BluetoothDevice.Kind
    {
        switch Int(device.deviceClassMajor) {
        case kBluetoothDeviceClassMajorPeripheral:
            // Masked against the constants rather than shifted by hand, so the
            // alignment is whatever `IOBluetooth` defines rather than what this
            // guessed it to be. A device can claim both, and a combo is more
            // useful drawn as a keyboard.
            let minor = Int(device.deviceClassMinor)
            if minor & kBluetoothDeviceClassMinorPeripheral1Keyboard != 0 {
                return .keyboard
            }
            if minor & kBluetoothDeviceClassMinorPeripheral1Pointing != 0 {
                return .pointing
            }
            return .unknown
        case kBluetoothDeviceClassMajorAudio:
            switch Int(device.deviceClassMinor) {
            case kBluetoothDeviceClassMinorAudioHeadset,
                kBluetoothDeviceClassMinorAudioHandsFree,
                kBluetoothDeviceClassMinorAudioHeadphones:
                return .headphones
            default:
                return .speaker
            }
        case kBluetoothDeviceClassMajorPhone: return .phone
        case kBluetoothDeviceClassMajorComputer: return .computer
        case kBluetoothDeviceClassMajorWearable: return .watch
        default: return .unknown
        }
    }

    /// Every paired device, connected first and then by name, which is the
    /// order the system's own list uses.
    private static func connectedDevices() -> [BluetoothDevice] {
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]
        else { return [] }
        return
            paired
            .map { device in
                BluetoothDevice(
                    id: device.addressString ?? UUID().uuidString,
                    name: device.name ?? device.addressString ?? "Unknown",
                    batteryLevel: batteryLevel(for: device),
                    isConnected: device.isConnected(),
                    isPaired: true,
                    kind: kind(of: device))
            }
            .sorted {
                $0.isConnected == $1.isConnected
                    ? $0.name.localizedCaseInsensitiveCompare($1.name)
                        == .orderedAscending
                    : $0.isConnected
            }
    }

    // MARK: - Acting on a device

    private static func device(withAddress address: String) -> IOBluetoothDevice? {
        IOBluetoothDevice(addressString: address)
    }

    /// Connects or disconnects, whichever the device is not already.
    ///
    /// `openConnection` brings up the baseband link and macOS restores the
    /// profiles on top of it, which is what makes a headset audible again
    /// without this having to know anything about audio.
    func toggleConnection(_ device: BluetoothDevice) {
        guard busy == nil else { return }
        busy = device.id
        failure = nil
        let address = device.id
        let shouldConnect = !device.isConnected
        activity = shouldConnect ? .connecting : .disconnecting

        queue.async { [weak self] in
            guard let target = Self.device(withAddress: address) else {
                DispatchQueue.main.async {
                    self?.busy = nil
                    self?.activity = nil
                    self?.failure = "\(device.name) is not reachable"
                }
                return
            }
            let result =
                shouldConnect
                ? target.openConnection() : target.closeConnection()
            DispatchQueue.main.async {
                self?.busy = nil
                self?.activity = nil
                if result != kIOReturnSuccess {
                    self?.failure =
                        shouldConnect
                        ? "Could not connect \(device.name)"
                        : "Could not disconnect \(device.name)"
                }
                self?.refresh()
            }
        }
    }

    /// Pairs a device found by the inquiry.
    ///
    /// The delegate answers only the confirmation macOS would otherwise put on
    /// screen itself. A device that wants a typed PIN is left to the system,
    /// which has the UI for it, and reports back as a failure here.
    func pair(_ device: BluetoothDevice) {
        guard busy == nil else { return }
        guard let target = Self.device(withAddress: device.id) else { return }
        busy = device.id
        activity = .pairing
        failure = nil
        // Built and set by selector rather than through `pairWithDevice:` or
        // `device`. Each macOS SDK imports those differently, a factory
        // initialiser or a plain method, a property or a getter, so a source
        // form that compiles against one fails against the next. The selector
        // is the same on all of them.
        let pairing = IOBluetoothDevicePair()
        _ = pairing.perform(Selector(("setDevice:")), with: target)
        pairing.delegate = self
        activePairing = pairing
        if pairing.start() != kIOReturnSuccess {
            busy = nil
            activity = nil
            failure = "Could not start pairing \(device.name)"
            activePairing = nil
        }
    }

    // MARK: - Discovery

    /// How long a scan runs before it is stopped here.
    ///
    /// Longer than the eight second inquiry, because the inquiry is only the
    /// first half: `updateNewDeviceNames` then sends a name request to each
    /// device it found, and each of those has its own timeout. Two seconds of
    /// slack, and then it is over whatever the radio thinks.
    private static let scanDuration: TimeInterval = 10

    /// Looks for devices that are not paired yet.
    ///
    /// Stopped as soon as the popup goes away: an inquiry keeps the radio busy,
    /// and one left running would degrade whatever is already connected.
    ///
    /// It is stopped on a deadline as well. `deviceInquiryComplete` is the
    /// documented way to learn a scan has ended and it does not always arrive:
    /// observed here spinning past twelve seconds with an eight second inquiry
    /// length and nothing found, which leaves the popup saying `Looking…` for
    /// as long as it is open and the radio busy for as long as that.
    func startScan() {
        guard !isScanning else { return }
        discovered = []
        failure = nil
        let inquiry = IOBluetoothDeviceInquiry(delegate: self)
        inquiry?.updateNewDeviceNames = true
        inquiry?.inquiryLength = 8
        activeInquiry = inquiry
        if inquiry?.start() == kIOReturnSuccess {
            isScanning = true
            scanDeadline?.invalidate()
            scanDeadline = Timer.scheduledTimer(
                withTimeInterval: Self.scanDuration, repeats: false
            ) { [weak self] _ in
                self?.stopScan()
            }
        } else {
            failure = "Could not start scanning"
            activeInquiry = nil
        }
    }

    func stopScan() {
        scanDeadline?.invalidate()
        scanDeadline = nil
        activeInquiry?.stop()
        activeInquiry = nil
        isScanning = false
    }

    /// Battery level, where the device publishes one.
    ///
    /// There is no public API for this. macOS stores it per device address under
    /// the Bluetooth preferences domain, which is readable without any
    /// permission, and absent for devices that do not report a level.
    private static func batteryLevel(for device: IOBluetoothDevice) -> Double? {
        guard let address = device.addressString?.replacingOccurrences(
            of: ":", with: "-").lowercased(),
            let defaults = UserDefaults(suiteName: "com.apple.Bluetooth"),
            let cache = defaults.dictionary(forKey: "DeviceCache"),
            let entry = cache[address] as? [String: Any]
        else { return nil }

        // Single-battery devices report one percentage. Split devices, AirPods
        // and their case, report several, and the lowest is the one worth
        // surfacing.
        let keys = [
            "BatteryPercent", "BatteryPercentSingle", "BatteryPercentLeft",
            "BatteryPercentRight", "BatteryPercentCase",
        ]
        let levels = keys.compactMap { entry[$0] as? Double }.filter { $0 > 0 }
        guard let lowest = levels.min() else { return nil }
        // Stored as a fraction by some devices and a percentage by others.
        return lowest > 1 ? lowest / 100 : lowest
    }
}


// MARK: - Inquiry

extension BluetoothManager: IOBluetoothDeviceInquiryDelegate {
    func deviceInquiryDeviceFound(
        _ sender: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!
    ) {
        add(device)
    }

    /// Names arrive after the addresses do, so a device first appears as its
    /// address and is rewritten once the radio has read the name.
    func deviceInquiryDeviceNameUpdated(
        _ sender: IOBluetoothDeviceInquiry!, device: IOBluetoothDevice!,
        devicesRemaining: UInt32
    ) {
        add(device)
    }

    func deviceInquiryComplete(
        _ sender: IOBluetoothDeviceInquiry!, error: IOReturn, aborted: Bool
    ) {
        scanDeadline?.invalidate()
        scanDeadline = nil
        isScanning = false
        activeInquiry = nil
    }

    private func add(_ device: IOBluetoothDevice?) {
        guard let device, let address = device.addressString else { return }
        // Already-paired devices are in the list above, and offering to pair
        // one again would do nothing.
        guard !device.isPaired() else { return }
        let entry = BluetoothDevice(
            id: address,
            name: device.name ?? address,
            batteryLevel: nil,
            isConnected: device.isConnected(),
            isPaired: false)
        if let index = discovered.firstIndex(where: { $0.id == address }) {
            discovered[index] = entry
        } else {
            discovered.append(entry)
        }
    }
}

// MARK: - Pairing

extension BluetoothManager: IOBluetoothDevicePairDelegate {
    /// Answering yes here is the same click the system dialog would ask for,
    /// and the request only arrives because this app started the pairing.
    func devicePairingUserConfirmationRequest(
        _ sender: Any!, numericValue: BluetoothNumericValue
    ) {
        activePairing?.replyUserConfirmation(true)
    }

    func devicePairingFinished(_ sender: Any!, error: IOReturn) {
        busy = nil
        activity = nil
        activePairing = nil
        if error != kIOReturnSuccess {
            failure = "Pairing did not complete"
        }
        refresh()
        discovered = []
    }
}
