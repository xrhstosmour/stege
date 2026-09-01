import AppKit
import CoreAudio
import Foundation

/// An application currently producing sound.
struct AudioSource: Identifiable, Equatable {
    let id: pid_t
    let name: String
    let icon: NSImage?

    static func == (lhs: AudioSource, rhs: AudioSource) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name
    }
}

/// Which applications are making sound.
///
/// Not per-application volume, which macOS does not offer. The HAL gained
/// process objects in macOS 14.4 and they carry a process identifier, a bundle
/// identifier and whether the process is running output, but no volume and no
/// mute: checked by asking every process object for both properties and getting
/// `false` from all of them. Setting a level per application means installing a
/// virtual audio device that becomes the default output and mixing in
/// userspace, which is a system audio driver and an administrator prompt, and
/// is not what this app is.
///
/// What is left is worth having on its own: the popup can say what is making
/// the noise, which is usually the question behind reaching for the volume.
enum AudioActivity {
    static func current() -> [AudioSource] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var size: UInt32 = 0
        guard
            AudioObjectGetPropertyDataSize(
                AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                &size) == noErr, size > 0
        else { return [] }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        var objects = [AudioObjectID](repeating: 0, count: count)
        guard
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject), &address, 0, nil,
                &size, &objects) == noErr
        else { return [] }

        var found: [AudioSource] = []
        for object in objects where isRunningOutput(object) {
            guard let pid = processIdentifier(of: object), pid > 0 else {
                continue
            }
            // Helper processes make sound on an application's behalf, and a
            // row naming one of those is worse than no row, so anything
            // without a name of its own is left out.
            guard
                let application = NSRunningApplication(processIdentifier: pid),
                let name = application.localizedName
            else { continue }
            guard !found.contains(where: { $0.id == pid }) else { continue }
            found.append(
                AudioSource(id: pid, name: name, icon: application.icon))
        }
        return found
    }

    private static func isRunningOutput(_ object: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyIsRunningOutput,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(object, &address) else { return false }
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard
            AudioObjectGetPropertyData(
                object, &address, 0, nil, &size, &running) == noErr
        else { return false }
        return running != 0
    }

    private static func processIdentifier(of object: AudioObjectID) -> pid_t? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(object, &address) else { return nil }
        var pid: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, &pid)
                == noErr
        else { return nil }
        return pid
    }
}
