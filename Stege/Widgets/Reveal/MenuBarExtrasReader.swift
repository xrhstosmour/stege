import AppKit
import ApplicationServices
import Combine

/// One other application's menu bar status item.
struct MenuBarExtraItem: Identifiable {
    let id: String
    let name: String
    /// What the pinning and hiding lists are keyed by, because it is the one
    /// thing about an application that does not change with its language or
    /// its version.
    let bundleIdentifier: String?
    let icon: NSImage?
    /// Whether `icon` is the glyph the application actually draws in the menu
    /// bar, rather than its application icon. A real glyph is line art meant
    /// for a menu bar and is drawn as a template beside Stege's own marks; an
    /// application icon is filled artwork and is toned down instead.
    let isMenuBarGlyph: Bool
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
            // The type is checked before the cast, for the reason
            // `axValue(of:_:)` below gives. This asks every running
            // application for an attribute and each answers with whatever
            // it put there, so a force cast on that took the whole bar down
            // over one badly behaved status item. The same cast was made
            // safe in `MenuExtra` and in `axValue`, and this site was
            // missed.
            guard
                let bar = copy(element, "AXExtrasMenuBar"),
                CFGetTypeID(bar as CFTypeRef) == AXUIElementGetTypeID(),
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
                guard isShownInMenuBar(item) else { continue }
                let glyph = menuBarGlyph(for: item, in: application)
                found.append(
                    MenuBarExtraItem(
                        id: "\(application.bundleIdentifier ?? "\(pid)")-\(index)",
                        name: application.localizedName ?? "",
                        bundleIdentifier: application.bundleIdentifier,
                        icon: glyph ?? flattenedIcon(for: application),
                        isMenuBarGlyph: glyph != nil,
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

    /// Whether macOS is actually showing this item, as opposed to keeping it.
    ///
    /// A menu bar that has run out of room does not drop items, it parks them
    /// under the notch, where they still have a window, a position and a real
    /// width, and are simply never drawn. The row was listing those, so it
    /// showed three more icons than the menu bar it stands in for.
    ///
    /// `auxiliaryTopLeftArea` and `auxiliaryTopRightArea` are the two strips
    /// either side of the notch, so anything between them is in the part of the
    /// bar that does not exist. A display without a notch publishes neither and
    /// has no such gap, so everything on it counts as shown.
    private static func isShownInMenuBar(_ item: AXUIElement) -> Bool {
        let origin = position(of: item)
        let width = size(of: item).width
        guard
            let screen = NSScreen.screens.first(where: {
                $0.frame.minX <= origin.x && origin.x < $0.frame.maxX
            }) ?? NSScreen.main,
            let left = screen.auxiliaryTopLeftArea,
            let right = screen.auxiliaryTopRightArea
        else { return true }

        let gap = left.maxX..<right.minX
        // Either edge inside the gap is enough. An item is not half drawn.
        return !gap.contains(origin.x) && !gap.contains(origin.x + width - 1)
    }

    // MARK: - Accessibility

    /// The application's own icon, drawn once into a plain bitmap.
    ///
    /// `NSRunningApplication.icon` hands back an image carrying more than
    /// thirty `NSISIconImageRep`s, macOS 26's compiled icon representation, at
    /// every size from 16 to 2048 points. Handed straight to SwiftUI at bar
    /// size, one of those was picking the wrong representation and drawing a
    /// smeared band of colour instead of the icon: `Docker` in particular came
    /// out as coloured noise in a rounded frame. Rasterising it here, once,
    /// through `NSImage.draw` picks the representation the same way every
    /// other part of macOS does and leaves SwiftUI a single flat bitmap to
    /// scale.
    ///
    /// 64 points rather than the 18 the bar draws, so a larger `icon-size`
    /// still has pixels to work with.
    private static func flattenedIcon(
        for application: NSRunningApplication
    ) -> NSImage? {
        let key = (application.bundleIdentifier
            ?? application.bundleURL?.path ?? "") as NSString
        if let cached = iconCache.object(forKey: key) { return cached }
        guard let icon = application.icon else { return nil }

        let size = NSSize(width: 64, height: 64)
        let flat = NSImage(size: size)
        flat.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        icon.draw(in: NSRect(origin: .zero, size: size))
        flat.unlockFocus()

        iconCache.setObject(flat, forKey: key)
        return flat
    }

    /// One rasterisation per application, for the same reason as `glyphCache`.
    private static let iconCache = NSCache<NSString, NSImage>()

    /// The glyph the application actually draws in the menu bar, when it can
    /// be found at all.
    ///
    /// A status item publishes no image through the accessibility API, checked
    /// by dumping every attribute of several. Two things do lead back to one.
    ///
    /// `AXTitle` on the item is often the name of the image the application set
    /// on its status button, because `NSImage`'s accessibility title falls back
    /// to the image's name. `SwipeAeroSpace` exposes `MenubarIcon` this way.
    ///
    /// Failing that, applications name the asset conventionally: `Maccy` ships
    /// `StatusBarMenuImage`, `LocalSend` ships `StatusBarItemIcon`. Asking the
    /// bundle for those by name reaches into the compiled asset catalog the
    /// same way the application itself does.
    ///
    /// Plenty are reachable by neither. `Docker` names its assets for the state
    /// they show, `Running` and `Paused` and `Stopped`, and `Amphetamine` and
    /// `1Password` ship no menu bar template at all. Those keep their
    /// application icon, so the row is mixed rather than uniform. The
    /// alternative is photographing the menu bar, which costs a Screen
    /// Recording grant and, for an item parked off screen, does not work.
    private static func menuBarGlyph(
        for item: AXUIElement, in application: NSRunningApplication
    ) -> NSImage? {
        guard let bundleURL = application.bundleURL,
            let bundle = Bundle(url: bundleURL)
        else { return nil }

        let key = (application.bundleIdentifier ?? bundleURL.path) as NSString
        if let cached = glyphCache.object(forKey: key) { return cached }

        var names: [String] = []
        if let title = copy(item, kAXTitleAttribute as String) as? String,
            !title.trimmingCharacters(in: .whitespaces).isEmpty
        {
            names.append(title)
        }
        names.append(contentsOf: conventionalGlyphNames)

        for name in names {
            guard let image = bundle.image(forResource: name) else { continue }
            // Only images the application marked as templates. Anything else
            // is artwork, and artwork tinted as a template draws as a solid
            // block.
            guard image.isTemplate else { continue }
            glyphCache.setObject(image, forKey: key)
            return image
        }
        return nil
    }

    /// What applications tend to call the asset, most specific first.
    private static let conventionalGlyphNames = [
        "StatusBarMenuImage", "StatusBarItemIcon", "StatusBarIcon",
        "MenubarIcon", "MenuBarIcon", "MenuBarItemIcon", "StatusIcon",
        "StatusItemIcon", "TrayIcon", "menubar", "statusbar",
    ]

    /// One lookup per application. Opening a bundle and searching its asset
    /// catalog is not free, and the row is read again whenever the menu bar
    /// changes.
    private static let glyphCache = NSCache<NSString, NSImage>()

    private static func copy(_ element: AXUIElement, _ attribute: String) -> Any? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element, attribute as CFString, &value) == .success
        else { return nil }
        return value
    }

    /// The type is checked before the cast. `AXUIElementCopyAttributeValue`
    /// answers with whatever the other application put there, and a force cast
    /// on that crashes the whole bar over one badly behaved status item. This
    /// runs on every menu bar change.
    private static func axValue(
        of element: AXUIElement, _ attribute: String
    ) -> AXValue? {
        guard let value = copy(element, attribute) else { return nil }
        guard CFGetTypeID(value as CFTypeRef) == AXValueGetTypeID() else {
            return nil
        }
        return (value as! AXValue)
    }

    private static func position(of element: AXUIElement) -> CGPoint {
        var point = CGPoint.zero
        guard let value = axValue(of: element, kAXPositionAttribute as String)
        else { return point }
        AXValueGetValue(value, .cgPoint, &point)
        return point
    }

    private static func size(of element: AXUIElement) -> CGSize {
        var size = CGSize.zero
        guard let value = axValue(of: element, kAXSizeAttribute as String)
        else { return size }
        AXValueGetValue(value, .cgSize, &size)
        return size
    }
}
