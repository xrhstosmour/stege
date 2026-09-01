import Combine
import CoreAudio
import Foundation

/// A selectable audio device.
struct AudioDevice: Identifiable, Equatable {
    let id: AudioObjectID
    let name: String
}

/// Output volume and microphone mute state, via public `CoreAudio`.
///
/// Both are driven by property listeners rather than a timer: `CoreAudio` posts
/// a callback whenever volume, mute or the default device changes, which is
/// every moment either value can move.
final class AudioManager: ObservableObject {
    /// One per process. The sound and microphone widgets are separate entries
    /// in the bar but the same devices underneath, and two managers would mean
    /// two sets of `CoreAudio` listeners reporting the same changes.
    static let shared = AudioManager()

    @Published private(set) var volume: Double = 0
    @Published private(set) var isOutputMuted = false
    @Published private(set) var isInputMuted = false
    @Published private(set) var hasInput = false
    /// Input gain, 0 to 1. Nil when the device exposes no settable gain,
    /// which is true of most USB and Bluetooth microphones.
    @Published private(set) var inputVolume: Double?
    @Published private(set) var outputDevices: [AudioDevice] = []
    @Published private(set) var inputDevices: [AudioDevice] = []
    @Published private(set) var currentOutputID: AudioObjectID = 0
    @Published private(set) var currentInputID: AudioObjectID = 0
    /// Applications making sound right now. Only read while a popup is open.
    @Published private(set) var sources: [AudioSource] = []

    /// The registered block is kept alongside the address because
    /// `AudioObjectRemovePropertyListenerBlock` only removes the exact block it
    /// was given. Passing a fresh one silently removes nothing and leaks.
    /// Where the level was before a mute that had to be done by turning it
    /// down, so unmuting can put it back rather than guessing.
    private var volumeBeforeMute: Double = 0
    private var sourcesTimer: Timer?

    private struct Listener {
        let device: AudioObjectID
        let address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }
    private var listeners: [Listener] = []

    init() {
        refresh()
        observeDefaultDeviceChanges()
        observeCurrentDevices()
    }

    deinit {
        removeListeners()
    }

    // MARK: - Reading

    private func refresh() {
        outputDevices = Self.devices(input: false)
        inputDevices = Self.devices(input: true)
        currentOutputID = Self.defaultDevice(input: false) ?? 0
        currentInputID = Self.defaultDevice(input: true) ?? 0

        if let output = Self.defaultDevice(input: false) {
            volume = Self.volume(of: output) ?? 0
            isOutputMuted = Self.isMuted(output, input: false) ?? false
        }
        if let input = Self.defaultDevice(input: true) {
            hasInput = true
            isInputMuted = Self.isMuted(input, input: true) ?? false
            inputVolume = Self.volume(of: input, input: true)
        } else {
            hasInput = false
            inputVolume = nil
        }
    }

    private static func defaultDevice(input: Bool) -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: input
                ? kAudioHardwarePropertyDefaultInputDevice
                : kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                &size, &device) == noErr, device != kAudioObjectUnknown
        else { return nil }
        return device
    }

    /// Volume, 0 to 1, for either direction.
    ///
    /// `kAudioDevicePropertyVolumeScalar` is read on the main element first,
    /// which many devices do not implement, then per channel. The deprecated
    /// `VirtualMainVolume` selector that would have covered both is not exposed
    /// to Swift at all.
    private static func volume(of device: AudioObjectID, input: Bool = false)
        -> Double?
    {
        if let main = scalarVolume(
            device, channel: kAudioObjectPropertyElementMain, input: input)
        {
            return main
        }
        let channels = [1, 2].compactMap {
            scalarVolume(
                device, channel: AudioObjectPropertyElement($0), input: input)
        }
        guard !channels.isEmpty else { return nil }
        return channels.reduce(0, +) / Double(channels.count)
    }

    private static func scalarVolume(
        _ device: AudioObjectID, channel: AudioObjectPropertyElement,
        input: Bool = false
    ) -> Double? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: input
                ? kAudioDevicePropertyScopeInput
                : kAudioDevicePropertyScopeOutput,
            mElement: channel)
        guard AudioObjectHasProperty(device, &address) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
                == noErr
        else { return nil }
        return Double(value)
    }

    private static func isMuted(_ device: AudioObjectID, input: Bool) -> Bool? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: input
                ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted)
                == noErr
        else { return nil }
        return muted != 0
    }

    // MARK: - Devices

    /// Every device that can play or record, depending on `input`.
    ///
    /// A device is only usable in a direction if it exposes streams in that
    /// direction. Without that check the list includes every device twice, so
    /// microphones appear as speakers and vice versa.
    static func devices(input: Bool) -> [AudioDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard
            AudioObjectGetPropertyDataSize(
                AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
                == noErr, size > 0
        else { return [] }

        var ids = [AudioObjectID](
            repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                &size, &ids) == noErr
        else { return [] }

        return ids.compactMap { id in
            guard hasStreams(id, input: input), let name = name(of: id) else {
                return nil
            }
            return AudioDevice(id: id, name: name)
        }
    }

    private static func hasStreams(_ device: AudioObjectID, input: Bool) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: input
                ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard
            AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr
        else { return false }
        return size > 0
    }

    private static func name(of device: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        guard
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, &name)
                == noErr
        else { return nil }
        return name as String
    }

    /// Switches the system default device, which is what the menu bar picker
    /// is expected to do: it changes where audio goes for everything, not just
    /// for this app.
    func selectDevice(_ device: AudioDevice, input: Bool) {
        var address = AudioObjectPropertyAddress(
            mSelector: input
                ? kAudioHardwarePropertyDefaultInputDevice
                : kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var id = device.id
        guard
            AudioObjectSetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                UInt32(MemoryLayout<AudioObjectID>.size), &id) == noErr
        else { return }
        refresh()
        removeDeviceListeners()
        observeCurrentDevices()
    }

    /// Started and stopped by the popup. The HAL has no notification for a
    /// process starting output, so this polls, and there is no reason to poll
    /// while nothing is on screen to show it.
    func startWatchingSources() {
        guard sourcesTimer == nil else { return }
        refreshSources()
        sourcesTimer = Timer.scheduledTimer(
            withTimeInterval: 2, repeats: true
        ) { [weak self] _ in self?.refreshSources() }
    }

    func stopWatchingSources() {
        sourcesTimer?.invalidate()
        sourcesTimer = nil
        sources = []
    }

    private func refreshSources() {
        let found = AudioActivity.current()
        if found != sources { sources = found }
    }

    // MARK: - Writing

    /// Writes to the main element where it exists, otherwise to each channel,
    /// mirroring how the value is read.
    func setVolume(_ newValue: Double) {
        guard let written = write(volume: newValue, input: false) else { return }
        volume = written
    }

    /// Input gain. Silently does nothing on a device with no settable gain,
    /// which is why the popup only draws the slider when `inputVolume` is set.
    func setInputVolume(_ newValue: Double) {
        guard let written = write(volume: newValue, input: true) else { return }
        inputVolume = written
    }

    /// Returns the value actually written, or nil when the device accepted
    /// none, so the caller does not publish a level the hardware ignored.
    private func write(volume newValue: Double, input: Bool) -> Double? {
        guard let device = Self.defaultDevice(input: input) else { return nil }
        var value = Float32(min(1, max(0, newValue)))
        let elements: [AudioObjectPropertyElement] =
            Self.scalarVolume(
                device, channel: kAudioObjectPropertyElementMain, input: input)
            != nil ? [kAudioObjectPropertyElementMain] : [1, 2]

        var wrote = false
        for element in elements {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: input
                    ? kAudioDevicePropertyScopeInput
                    : kAudioDevicePropertyScopeOutput,
                mElement: element)
            guard AudioObjectHasProperty(device, &address) else { continue }
            if AudioObjectSetPropertyData(
                device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size),
                &value) == noErr
            {
                wrote = true
            }
        }
        return wrote ? Double(value) : nil
    }

    /// Moves the level by `delta`, clamped, and unmutes on the way up.
    ///
    /// Scrolling a muted control up and hearing nothing would look broken, and
    /// scrolling down to zero is the same thing the mute button does.
    func nudgeVolume(by delta: Double) {
        let target = min(1, max(0, volume + delta))
        if target > 0.001, isOutputMuted { toggleOutputMute() }
        setVolume(target)
    }

    func toggleInputMute() {
        toggleMute(input: true)
    }

    /// The input equivalent of `nudgeVolume`, for the microphone widget's
    /// scroll wheel. Devices with no settable gain have nothing to nudge.
    func nudgeInputVolume(by delta: Double) {
        guard let current = inputVolume else { return }
        let target = min(1, max(0, current + delta))
        if target > 0.001, isInputMuted { toggleInputMute() }
        setInputVolume(target)
    }

    /// Not every output device carries a mute property, the built-in speakers
    /// among them, so the volume is dropped to zero and restored instead when
    /// there is nothing to set. The icon reads the same either way.
    func toggleOutputMute() {
        guard !toggleMute(input: false) else { return }
        if isOutputMuted || volume <= 0.001 {
            setVolume(volumeBeforeMute > 0.001 ? volumeBeforeMute : 0.25)
            isOutputMuted = false
        } else {
            volumeBeforeMute = volume
            setVolume(0)
            isOutputMuted = true
        }
    }

    @discardableResult
    private func toggleMute(input: Bool) -> Bool {
        guard let device = Self.defaultDevice(input: input) else { return false }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: input
                ? kAudioDevicePropertyScopeInput
                : kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(device, &address) else { return false }
        var muted: UInt32 = (input ? isInputMuted : isOutputMuted) ? 0 : 1
        let size = UInt32(MemoryLayout<UInt32>.size)
        guard
            AudioObjectSetPropertyData(device, &address, 0, nil, size, &muted)
                == noErr
        else { return false }
        if input {
            isInputMuted = muted != 0
        } else {
            isOutputMuted = muted != 0
        }
        return true
    }

    // MARK: - Listening

    private func observeDefaultDeviceChanges() {
        for selector in [
            kAudioHardwarePropertyDefaultOutputDevice,
            kAudioHardwarePropertyDefaultInputDevice,
        ] {
            addListener(
                to: AudioObjectID(kAudioObjectSystemObject),
                selector: selector, scope: kAudioObjectPropertyScopeGlobal
            ) { [weak self] in
                // The one change that really does invalidate everything: the
                // per-device listeners are attached to a device that is no
                // longer the default, so they come down and go back up.
                guard let self else { return }
                self.removeDeviceListeners()
                self.refresh()
                self.observeCurrentDevices()
            }
        }
    }

    /// Listeners are attached to the devices themselves, so they have to be
    /// torn down and rebuilt whenever the default device changes.
    ///
    /// Each one reads back only the property it watches. They used to share a
    /// block that rebuilt every listener and re-enumerated every device, which
    /// meant a slider drag did that on the main thread for every step of the
    /// drag, and the popup moved in steps behind the pointer.
    private func observeCurrentDevices() {
        if let output = Self.defaultDevice(input: false) {
            addListener(
                to: output, selector: kAudioDevicePropertyVolumeScalar,
                scope: kAudioDevicePropertyScopeOutput
            ) { [weak self] in self?.readOutputVolume() }
            addListener(
                to: output, selector: kAudioDevicePropertyMute,
                scope: kAudioDevicePropertyScopeOutput
            ) { [weak self] in self?.readOutputMute() }
        }
        if let input = Self.defaultDevice(input: true) {
            addListener(
                to: input, selector: kAudioDevicePropertyMute,
                scope: kAudioDevicePropertyScopeInput
            ) { [weak self] in self?.readInputMute() }
            // So the popup's gain slider follows changes made anywhere else,
            // the same way the output slider already does.
            addListener(
                to: input, selector: kAudioDevicePropertyVolumeScalar,
                scope: kAudioDevicePropertyScopeInput
            ) { [weak self] in self?.readInputVolume() }
        }
    }

    /// Reads one property back, and publishes only when it actually moved. A
    /// level written from here comes straight back through its own listener,
    /// and republishing an unchanged value redraws the popup for nothing.
    private func readOutputVolume() {
        guard let device = Self.defaultDevice(input: false),
            let value = Self.volume(of: device),
            abs(value - volume) > 0.0001
        else { return }
        volume = value
    }

    private func readOutputMute() {
        guard let device = Self.defaultDevice(input: false),
            let muted = Self.isMuted(device, input: false),
            muted != isOutputMuted
        else { return }
        isOutputMuted = muted
    }

    private func readInputVolume() {
        guard let device = Self.defaultDevice(input: true) else { return }
        let value = Self.volume(of: device, input: true)
        guard value != inputVolume else { return }
        inputVolume = value
    }

    private func readInputMute() {
        guard let device = Self.defaultDevice(input: true),
            let muted = Self.isMuted(device, input: true),
            muted != isInputMuted
        else { return }
        isInputMuted = muted
    }

    private func addListener(
        to device: AudioObjectID, selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope, onChange: @escaping () -> Void
    ) {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: scope,
            mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { _, _ in onChange() }
        let status = AudioObjectAddPropertyListenerBlock(
            device, &address, DispatchQueue.main, block)
        if status == noErr {
            listeners.append(
                Listener(device: device, address: address, block: block))
        }
    }

    private func removeDeviceListeners() {
        let system = AudioObjectID(kAudioObjectSystemObject)
        listeners.removeAll { listener in
            guard listener.device != system else { return false }
            remove(listener)
            return true
        }
    }

    private func removeListeners() {
        listeners.forEach(remove)
        listeners.removeAll()
    }

    private func remove(_ listener: Listener) {
        var address = listener.address
        AudioObjectRemovePropertyListenerBlock(
            listener.device, &address, DispatchQueue.main, listener.block)
    }
}
