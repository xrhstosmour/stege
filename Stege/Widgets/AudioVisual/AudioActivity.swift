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
            guard let source = describe(pid: pid, object: object) else {
                continue
            }
            // One row per application, not per process. A browser plays through
            // an audio helper and can have several.
            guard !found.contains(where: { $0.name == source.name }) else {
                continue
            }
            found.append(source)
        }
        return found
    }

    /// The application behind a process making sound.
    ///
    /// A process identifier is not enough on its own. Browsers and several
    /// media applications play through a helper process, which has no
    /// `NSRunningApplication` of its own, so asking for one and giving up drops
    /// exactly the applications most worth naming. The bundle identifier the
    /// process object carries resolves back to the application itself, and its
    /// helpers carry a bundle identifier derived from it.
    private static func describe(pid: pid_t, object: AudioObjectID)
        -> AudioSource?
    {
        if let application = NSRunningApplication(processIdentifier: pid),
            let name = application.localizedName
        {
            return AudioSource(id: pid, name: name, icon: application.icon)
        }

        guard let bundle = bundleIdentifier(of: object), !bundle.isEmpty
        else { return nil }
        let workspace = NSWorkspace.shared
        // A helper is named for its parent, `com.google.Chrome.helper`, so
        // trimming components back finds the application it belongs to.
        var candidate = bundle
        while !candidate.isEmpty {
            if let url = workspace.urlForApplication(
                withBundleIdentifier: candidate)
            {
                let name =
                    FileManager.default.displayName(atPath: url.path)
                    .replacingOccurrences(of: ".app", with: "")
                return AudioSource(
                    id: pid, name: name,
                    icon: workspace.icon(forFile: url.path))
            }
            guard let dot = candidate.lastIndex(of: ".") else { break }
            candidate = String(candidate[..<dot])
        }
        return nil
    }

    private static func bundleIdentifier(of object: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyBundleID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(object, &address) else { return nil }
        var value: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(
                object, &address, 0, nil, &size, pointer)
        }
        guard status == noErr else { return nil }
        return value as String?
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
