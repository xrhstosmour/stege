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

    /// The registered block is kept alongside the address because
    /// `AudioObjectRemovePropertyListenerBlock` only removes the exact block it
    /// was given. Passing a fresh one silently removes nothing and leaks.
    /// Where the level was before a mute that had to be done by turning it
    /// down, so unmuting can put it back rather than guessing.
    private var volumeBeforeMute: Double = 0

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

    func toggleInputMute() {
        toggleMute(input: true)
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
                selector: selector, scope: kAudioObjectPropertyScopeGlobal)
        }
    }

    /// Listeners are attached to the devices themselves, so they have to be
    /// torn down and rebuilt whenever the default device changes.
    private func observeCurrentDevices() {
        if let output = Self.defaultDevice(input: false) {
            addListener(
                to: output, selector: kAudioDevicePropertyVolumeScalar,
                scope: kAudioDevicePropertyScopeOutput)
            addListener(
                to: output, selector: kAudioDevicePropertyMute,
                scope: kAudioDevicePropertyScopeOutput)
        }
        if let input = Self.defaultDevice(input: true) {
            addListener(
                to: input, selector: kAudioDevicePropertyMute,
                scope: kAudioDevicePropertyScopeInput)
            // So the popup's gain slider follows changes made anywhere else,
            // the same way the output slider already does.
            addListener(
                to: input, selector: kAudioDevicePropertyVolumeScalar,
                scope: kAudioDevicePropertyScopeInput)
        }
    }

    private func addListener(
        to device: AudioObjectID, selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope
    ) {
        var address = AudioObjectPropertyAddress(
            mSelector: selector, mScope: scope,
            mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            // A default-device change invalidates the per-device listeners.
            self.removeDeviceListeners()
            self.refresh()
            self.observeCurrentDevices()
        }
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
