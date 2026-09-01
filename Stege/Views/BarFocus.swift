import AppKit
import SwiftUI

/// Stepping through the bar from the keyboard.
///
/// The bar is a row of controls that could only be reached with the pointer,
/// which is the largest thing it was missing against the menu bar it replaces.
/// A shortcut puts a ring on the first item, the arrow keys walk it, `return`
/// opens what is under it and `escape` puts it away.
///
/// Keys are read by a panel of its own rather than by the bar. The bar's panel
/// is deliberately non-activating, because a bar that stole focus every time
/// the pointer crossed it would be unusable, and a window that cannot become
/// key cannot receive a key press. This panel is one point across, off in a
/// corner, and exists only while the ring is up.
final class BarFocus: ObservableObject {
    static let shared = BarFocus()

    /// Which item the ring is on, or nil when the keyboard is not driving.
    @Published private(set) var focused: Int?

    /// How many items are on the bar, set by the bar as it draws.
    var count: Int = 0

    private var panel: NSPanel?

    private init() {}

    var isActive: Bool { focused != nil }

    func begin() {
        guard count > 0 else { return }
        if focused != nil {
            end()
            return
        }
        focused = 0
        showPanel()
    }

    func end() {
        focused = nil
        panel?.orderOut(nil)
        panel = nil
    }

    func move(by step: Int) {
        guard let current = focused, count > 0 else { return }
        // Wraps, because a row of a dozen items is quicker to reach the far end
        // of by going the short way round.
        focused = (current + step + count) % count
    }

    /// Opens whatever the ring is on. Widgets listen for their own index.
    func activate() {
        guard let focused else { return }
        NotificationCenter.default.post(
            name: .barItemActivated, object: nil,
            userInfo: ["index": focused])
    }

    private func showPanel() {
        let panel = KeyCapturePanel(
            contentRect: NSRect(x: -10, y: -10, width: 1, height: 1),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
    }
}

/// The window that reads the keys while the ring is up.
private final class KeyCapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case 123: BarFocus.shared.move(by: -1)  // Left.
        case 124: BarFocus.shared.move(by: 1)  // Right.
        case 48:  // Tab, and shift-tab backwards, which is what a row of
            // controls answers to everywhere else.
            BarFocus.shared.move(
                by: event.modifierFlags.contains(.shift) ? -1 : 1)
        case 36, 49: BarFocus.shared.activate()  // Return, space.
        case 53: BarFocus.shared.end()  // Escape.
        default: super.keyDown(with: event)
        }
    }

    /// Clicking anywhere else means the pointer has taken over, so the ring is
    /// no longer what is driving.
    override func resignKey() {
        super.resignKey()
        DispatchQueue.main.async { BarFocus.shared.end() }
    }
}

extension Notification.Name {
    static let barItemActivated = Notification.Name("barItemActivated")
}

/// Which item in the bar a widget is, so it can tell whether the ring is on it
/// and whether an activation was meant for it.
private struct BarItemIndexKey: EnvironmentKey {
    static let defaultValue: Int? = nil
}

extension EnvironmentValues {
    var barItemIndex: Int? {
        get { self[BarItemIndexKey.self] }
        set { self[BarItemIndexKey.self] = newValue }
    }
}

extension View {
    /// Draws the ring when the keyboard is on this item, and runs `action` when
    /// it is opened from the keyboard. Everything a widget needs to join in.
    func barFocusable(action: @escaping () -> Void) -> some View {
        modifier(BarFocusable(action: action))
    }
}

private struct BarFocusable: ViewModifier {
    @Environment(\.barItemIndex) private var index
    @ObservedObject private var focus = BarFocus.shared
    let action: () -> Void

    private var isFocused: Bool {
        guard let index else { return false }
        return focus.focused == index
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(Color.accentColor, lineWidth: 2)
                        .padding(-2)
                }
            }
            .onReceive(
                NotificationCenter.default.publisher(for: .barItemActivated)
            ) { notification in
                guard let index,
                    notification.userInfo?["index"] as? Int == index
                else { return }
                action()
            }
    }
}
