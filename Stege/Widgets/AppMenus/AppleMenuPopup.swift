import ApplicationServices
import SwiftUI

/// A short Apple menu drawn in the bar's own style.
///
/// The system Apple menu carries fifteen entries, several of them duplicated
/// because macOS keeps the Option-key alternates in the same list, which the
/// Accessibility API gives no way to tell apart. This shows the five that are
/// actually reached for.
///
/// Each row presses the real menu item rather than reimplementing what it does,
/// so restart, shut down and log out all raise the system's own confirmation
/// and honour whatever it decides. Items are found by their action selector,
/// `_restartRequested:` and the like, because titles are localised and would
/// only match in English.
struct AppleMenuPopup: View {
    @ObservedObject var manager: AppMenusManager

    /// In the order macOS lists them, with the power items last.
    ///
    /// `_sleepRequested:` is the one macOS puts first of those, and it is the
    /// one of the group reached for daily, so leaving it out meant the shortcut
    /// was there for restarting and shutting down but not for the thing done
    /// every time you close the lid on purpose.
    private static let wanted: [(identifier: String, title: String, symbol: String)] = [
        ("_aboutThisMacRequested:", "About This Mac", "desktopcomputer"),
        ("_systemInformationRequested:", "System Information", "info.circle"),
        ("_sleepRequested:", "Sleep", "moon.fill"),
        ("_restartRequested:", "Restart", "arrow.clockwise"),
        ("_shutDownRequested:", "Shut Down", "power"),
        ("_logOutRequested:", "Log Out", "rectangle.portrait.and.arrow.right"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                // The power items are set apart, so none of them is a
                // neighbour of something harmless.
                if row.identifier == "_sleepRequested:", index > 0 {
                    PopupSeparator()
                }
                menuRow(row)
            }
        }
        .padding(PopupStyle.padding)
        .frame(width: 210, alignment: .leading)
    }

    private struct Row {
        let identifier: String
        let title: String
        let symbol: String
        let element: AXUIElement
    }

    /// Only the entries the system actually published. An item that is missing,
    /// which is what happens on a Mac with no restart available, is left out
    /// rather than drawn as a row that does nothing.
    private var rows: [Row] {
        guard let appleMenu = manager.appleMenu else { return [] }
        let entries = manager.entries(for: appleMenu)
        return Self.wanted.compactMap { wanted in
            guard
                let entry = entries.first(where: {
                    $0.identifier == wanted.identifier
                }),
                let element = entry.element
            else { return nil }
            return Row(
                identifier: wanted.identifier, title: wanted.title,
                symbol: wanted.symbol, element: element)
        }
    }

    /// Laid out and lit like every other popup row, rather than as a bare
    /// `HStack` with padding. Without the highlight there was no way to tell
    /// which of Restart and Shut Down the pointer was on, which is not a thing
    /// to be unsure about.
    private func menuRow(_ row: Row) -> some View {
        HStack(spacing: 10) {
            Image(systemName: row.symbol)
                .font(.system(size: PopupStyle.captionSize))
                .frame(width: PopupStyle.iconColumn)
            Text(row.title)
                .font(.system(size: PopupStyle.bodySize))
            Spacer(minLength: 8)
        }
        .popupRow {
            MenuBarPopup.hide()
            // After the popup is gone, so the confirmation macOS raises is not
            // covered by a panel that is on its way out.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                AXUIElementPerformAction(row.element, kAXPressAction as CFString)
            }
        }
    }
}
