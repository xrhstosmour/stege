import AppKit
import ApplicationServices
import Combine

/// One other application's menu bar status item.
struct MenuBarExtraItem: Identifiable {
    let id: String
    let name: String
    let icon: NSImage?
    /// Where the real item sits in the real menu bar, used only to put the row
    /// in the same order macOS has it in.
    let position: CGFloat
    let element: AXUIElement
}

/// Every status item in the menu bar that is not one of macOS's own.
///
/// The bar hides the real menu bar, which takes every third-party status item
/// with it, and this is how they come back.
///
/// Nothing is captured or redrawn. Each application publishes its own status
/// item through the Accessibility API, under `AXExtrasMenuBar` on the
/// application element, so the item can be found, ordered by where it really
/// sits, and pressed. The icon shown is the application's own, from
/// `NSRunningApplication`, and pressing the row presses the real item so macOS
/// opens that application's real menu.
///
/// The obvious alternative, screenshotting each item and drawing the picture,
/// is what Bartender and Ice do. It needs Screen Recording, it needs
/// `ScreenCaptureKit` now that `CGWindowListCreateImage` is gone, and it needs
/// the menu bar pulled down before every capture because a hidden item has
/// nowhere on screen to be photographed. This needs none of that: it reuses the
/// Accessibility permission the app menus already ask for.
final class MenuBarExtrasReader: ObservableObject {
    static let shared = MenuBarExtrasReader()

    @Published private(set) var items: [MenuBarExtraItem] = []

    /// Applications whose items Stege already draws itself, so the row does not
    /// show a second copy of what is two icons to its left.
    ///
    /// Control Center owns every one of macOS's own extras, Wi-Fi, Bluetooth,
    /// sound, battery and the clock among them.
    private static let excluded: Set<String> = [
        "com.apple.controlcenter",
        "com.apple.TextInputMenuAgent",
    ]

    /// An unresponsive application must not stall the read. Every call below is
    /// synchronous and there are as many of them as there are running
    /// applications.
    private static let messagingTimeout: Float = 0.25

    private var observers: [NSObjectProtocol] = []

    private init() {}

    deinit {
        observers.forEach {
            NSWorkspace.shared.notificationCenter.removeObserver($0)
        }
    }

    /// Whether Stege can read other applications at all. Without this the row
    /// is empty and says so rather than looking like nothing is running.
    var isTrusted: Bool { AXIsProcessTrusted() }

    /// Re-reads when applications come and go, for as long as the row is on
    /// screen. Registered on the first reveal and left in place: the
    /// notifications are cheap, and a launch while the row is hidden still has
    /// to be noticed before it is shown again.
    func startWatching() {
        guard observers.isEmpty else { return }
        let centre = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
        ] {
            observers.append(
                centre.addObserver(
                    forName: name, object: nil, queue: .main
                ) { [weak self] _ in
                    self?.refresh()
                })
        }
    }

    /// Reads off the main thread. Each application is one Accessibility round
    /// trip, and there are usually a few hundred of them.
    func refresh() {
        DispatchQueue.global(qos: .userInitiated).async {
            let found = Self.read()
            DispatchQueue.main.async { self.items = found }
        }
    }

    private static func read() -> [MenuBarExtraItem] {
        var found: [MenuBarExtraItem] = []
        let ownPID = ProcessInfo.processInfo.processIdentifier

        for application in NSWorkspace.shared.runningApplications {
            let pid = application.processIdentifier
            guard pid > 0, pid != ownPID else { continue }
            if let bundle = application.bundleIdentifier,
                excluded.contains(bundle)
            {
                continue
            }

            let element = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(element, messagingTimeout)
            guard
                let bar = copy(element, "AXExtrasMenuBar"),
                let children = copy(
                    bar as! AXUIElement, kAXChildrenAttribute as String)
                    as? [AXUIElement]
            else { continue }

            for (index, item) in children.enumerated() {
                // Width rather than presence. An application can publish an
                // item it is not currently showing, and that one reports zero
                // width, so it would otherwise appear in the row as an icon
                // that does nothing.
                guard size(of: item).width > 0 else { continue }
                found.append(
                    MenuBarExtraItem(
                        id: "\(application.bundleIdentifier ?? "\(pid)")-\(index)",
                        name: application.localizedName ?? "",
                        icon: application.icon,
                        position: position(of: item).x,
                        element: item))
            }
        }

        // Left to right in the order macOS has them, so the row reads the same
        // as the menu bar it stands in for.
        return found.sorted { $0.position < $1.position }
    }

    func press(_ item: MenuBarExtraItem) {
        MenuExtra.press(element: item.element)
    }

    // MARK: - Accessibility

    private static func copy(_ element: AXUIElement, _ attribute: String) -> Any? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element, attribute as CFString, &value) == .success
        else { return nil }
        return value
    }

    private static func position(of element: AXUIElement) -> CGPoint {
        var point = CGPoint.zero
        guard let value = copy(element, kAXPositionAttribute as String) else {
            return point
        }
        AXValueGetValue(value as! AXValue, .cgPoint, &point)
        return point
    }

    private static func size(of element: AXUIElement) -> CGSize {
        var size = CGSize.zero
        guard let value = copy(element, kAXSizeAttribute as String) else {
            return size
        }
        AXValueGetValue(value as! AXValue, .cgSize, &size)
        return size
    }
}
