import AppKit
import ApplicationServices
import Foundation

/// Whether anything is capturing the screen.
///
/// There is no public API for this. What there is, is the sentence macOS puts
/// on Control Center's own menu bar extra while a sensor is in use: its
/// `AXDescription` goes from "Control Center" to "Control Center, Screen
/// Recording is in use". That is a description rather than an identifier, and
/// descriptions are translated, so the names are read out of the table macOS
/// builds them from rather than spelled in English here:
/// `ControlCenter.app/Contents/Resources/SensorIndicators.loctable` holds
/// `Screen Recording`, `System Audio Recording` and
/// `Screen & System Audio Recording` in 42 languages, and `Bundle` resolves the
/// one the system is running in.
///
/// Costs one accessibility attribute read. It needs no permission beyond the
/// Accessibility access the app menus already require, and unlike anything
/// built on `ScreenCaptureKit` it never asks for Screen Recording itself.
enum ScreenRecordingReader {
    /// The keys macOS uses for the screen-related sensors, and their
    /// translations in whatever language the system is running in.
    ///
    /// Resolved once. The system language does not change while the process is
    /// running, and opening a bundle per poll would.
    private static let names: [String] = {
        let keys = [
            "Screen Recording",
            "Screen & System Audio Recording",
            "System Audio Recording",
        ]
        guard
            let bundle = Bundle(
                path: "/System/Library/CoreServices/ControlCenter.app")
        else { return keys }
        // The English key stays in the list as well: it is the value on an
        // English system, and the fallback if the table ever moves.
        return keys.flatMap { key -> [String] in
            let translated = bundle.localizedString(
                forKey: key, value: key, table: "SensorIndicators")
            return translated == key ? [key] : [key, translated]
        }
    }()

    static func isRecording() -> Bool {
        guard let description = controlCentreDescription() else { return false }
        return names.contains { description.localizedCaseInsensitiveContains($0) }
    }

    private static func controlCentreDescription() -> String? {
        guard let extra = MenuExtra.element(for: .controlCentre) else {
            return nil
        }
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                extra, kAXDescriptionAttribute as CFString, &value) == .success
        else { return nil }
        return value as? String
    }
}
