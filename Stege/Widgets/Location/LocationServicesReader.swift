import AppKit
import Foundation

/// Whether anything is using Location Services.
///
/// There is no public API for this. What there is, is the sentence macOS puts
/// on Control Center's own menu bar extra while a sensor is in use: its
/// `AXDescription` goes from "Control Center" to "Control Center, Location is
/// in use", the same mechanism the corner privacy dot for microphone, camera
/// and screen recording is built on. That is a description rather than an
/// identifier, and descriptions are translated, so the name is read out of the
/// table macOS builds them from rather than spelled in English here:
/// `ControlCenter.app/Contents/Resources/SensorIndicators.loctable` holds
/// `Location` alongside the other sensor names, in every language the system
/// ships.
///
/// Costs one accessibility attribute read. It needs no permission beyond the
/// Accessibility access the app menus already require, and asks Location
/// Services for nothing itself.
enum LocationServicesReader {
    /// The key macOS uses for Location, and its translation in whatever
    /// language the system is running in.
    ///
    /// Resolved once. The system language does not change while the process is
    /// running, and opening a bundle per poll would.
    private static let names: [String] = {
        let key = "Location"
        guard
            let bundle = Bundle(
                path: "/System/Library/CoreServices/ControlCenter.app")
        else { return [key] }
        let translated = bundle.localizedString(
            forKey: key, value: key, table: "SensorIndicators")
        // The English key stays in the list as well: it is the value on an
        // English system, and the fallback if the table ever moves.
        return translated == key ? [key] : [key, translated]
    }()

    static func isInUse() -> Bool {
        guard let description = MenuExtra.description(for: .controlCentre)
        else { return false }
        return names.contains { description.localizedCaseInsensitiveContains($0) }
    }
}
