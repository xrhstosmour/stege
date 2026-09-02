import AVFoundation
import Combine
import CoreAudio
import CoreMediaIO
import Foundation

/// Reports whether the microphone or camera is in use by any application.
///
/// Replacing the menu bar hides the orange and green dots macOS draws there, so
/// this restores that signal. It needs no permission of its own: both properties
/// describe device state, not captured content.
final class PrivacyManager: ObservableObject {
    @Published private(set) var isMicrophoneActive = false
    @Published private(set) var isCameraActive = false
    /// Read a different way from the other two, because macOS exposes no
    /// device property for it. See `ScreenRecordingReader`.
    @Published private(set) var isScreenRecordingActive = false

    private var timer: Timer?
    /// One read at a time. A slow answer must not queue the next tick behind it.
    private var isReadingScreenRecording = false

    /// CoreAudio and CoreMediaIO expose "is something using this device" as a
    /// property but post no notification when it changes, so this is polled.
    /// Two seconds is enough to be noticed and cheap enough not to matter, both
    /// reads are in-process property lookups rather than process spawns.
    private let interval: TimeInterval = 2.0

    init() {
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
        let microphone = PrivacyManager.isAnyAudioInputRunning()
        let camera = PrivacyManager.isAnyCameraRunning()
        if microphone != isMicrophoneActive || camera != isCameraActive {
            isMicrophoneActive = microphone
            isCameraActive = camera
        }
        refreshScreenRecording()
    }

    /// Off the main thread, unlike the two above.
    ///
    /// Those are in-process property lookups. This one crosses into Control
    /// Center over the accessibility API, several round trips of it, and an
    /// application that is slow to answer would stall the bar for as long as it
    /// took, every two seconds.
    private func refreshScreenRecording() {
        guard !isReadingScreenRecording else { return }
        isReadingScreenRecording = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let recording = ScreenRecordingReader.isRecording()
            DispatchQueue.main.async {
                guard let self else { return }
                self.isReadingScreenRecording = false
                guard recording != self.isScreenRecordingActive else { return }
                self.isScreenRecordingActive = recording
            }
        }
    }

    // MARK: - Microphone

    private static func isAnyAudioInputRunning() -> Bool {
        for device in audioInputDevices() where isAudioDeviceRunning(device) {
            return true
        }
        return false
    }

    private static func audioInputDevices() -> [AudioObjectID] {
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

        var devices = [AudioObjectID](
            repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                &size, &devices) == noErr
        else { return [] }

        // Only devices with input streams can be a microphone.
        return devices.filter { hasInputStreams($0) }
    }

    private static func hasInputStreams(_ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard
            AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size)
                == noErr
        else { return false }
        return size > 0
    }

    private static func isAudioDeviceRunning(_ device: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard
            AudioObjectGetPropertyData(
                device, &address, 0, nil, &size, &running) == noErr
        else { return false }
        return running != 0
    }

    // MARK: - Camera

    private static func isAnyCameraRunning() -> Bool {
        for device in cameraDevices() where isCameraRunning(device) {
            return true
        }
        return false
    }

    private static func cameraDevices() -> [CMIOObjectID] {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))

        var size: UInt32 = 0
        guard
            CMIOObjectGetPropertyDataSize(
                CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, &size)
                == noErr, size > 0
        else { return [] }

        var devices = [CMIOObjectID](
            repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard
            CMIOObjectGetPropertyData(
                CMIOObjectID(kCMIOObjectSystemObject), &address, 0, nil, size,
                &used, &devices) == noErr
        else { return [] }
        return devices
    }

    private static func isCameraRunning(_ device: CMIOObjectID) -> Bool {
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(
                kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var used: UInt32 = 0
        guard
            CMIOObjectGetPropertyData(
                device, &address, 0, nil, size, &used, &running) == noErr
        else { return false }
        return running != 0
    }
}
