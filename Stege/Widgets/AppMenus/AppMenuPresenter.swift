import AppKit

/// Builds a real `NSMenu` from what the Accessibility API reported, and pops it
/// up under the bar.
///
/// Deliberately not a SwiftUI `Menu` or a hand-drawn popup. `NSMenu` renders
/// exactly as every other macOS menu does, and gets right-aligned keyboard
/// equivalents, submenu flyouts, scrolling for very long menus (Chrome's
/// Bookmarks menu has 110 entries) and keyboard navigation without any of it
/// being reimplemented.
final class AppMenuPresenter: NSObject, NSMenuDelegate {

    /// Retains the presenter for as long as its menu is on screen. A popped-up
    /// menu does not hold a strong reference to its delegate, so without this
    /// the delegate is deallocated and submenus silently stop populating.
    private static var active: AppMenuPresenter?

    private let manager: AppMenusManager
    /// Maps each submenu back to the entry that owns it, so its contents can be
    /// read when macOS is about to display it rather than up front.
    private var pendingSubmenus: [ObjectIdentifier: AppMenuEntry] = [:]

    private init(manager: AppMenusManager) {
        self.manager = manager
    }

    /// Shows `menu`'s entries under `rect`, given in global screen coordinates.
    static func present(
        menu: AppMenuEntry, manager: AppMenusManager, below rect: CGRect
    ) {
        let presenter = AppMenuPresenter(manager: manager)
        active = presenter

        let nsMenu = NSMenu()
        nsMenu.delegate = presenter
        nsMenu.autoenablesItems = false
        presenter.populate(nsMenu, with: manager.entries(for: menu))

        // `NSMenu` positions from the bottom-left in screen coordinates, while
        // SwiftUI reports frames top-left with y growing downward, so the origin
        // has to be flipped against the screen holding the bar.
        let screen =
            NSScreen.screens.first { $0.frame.intersects(rect) } ?? NSScreen.main
        let screenHeight = screen?.frame.maxY ?? 0
        let origin = NSPoint(x: rect.minX, y: screenHeight - rect.maxY)

        nsMenu.popUp(positioning: nil, at: origin, in: nil)
    }

    private func populate(_ nsMenu: NSMenu, with entries: [AppMenuEntry]) {
        for entry in entries {
            guard !entry.isSeparator else {
                nsMenu.addItem(.separator())
                continue
            }

            let item = NSMenuItem(
                title: entry.title, action: nil, keyEquivalent: "")
            item.isEnabled = entry.isEnabled
            item.state = entry.isChecked ? .on : .off

            if let shortcut = entry.shortcut {
                // Set purely for display. A menu item's key equivalent is only
                // live while its menu is open, so this cannot shadow the
                // application's own shortcuts.
                item.keyEquivalent = shortcut.key.lowercased()
                item.keyEquivalentModifierMask = shortcut.modifierFlags
            }

            // Hidden until Option is held, which is what the application's own
            // menu does with it. Both were being drawn, so Finder's File menu
            // showed "Get Info" and "Show Inspector" one under the other.
            //
            // `NSMenuItem` requires an alternate to share the key equivalent of
            // the item above and differ only in modifiers, and an entry with no
            // shortcut at all shares an empty one, so the modifier mask is set
            // either way.
            if entry.isAlternate {
                item.isAlternate = true
                if entry.shortcut == nil {
                    item.keyEquivalentModifierMask = .option
                }
            }

            if entry.hasSubmenu {
                let submenu = NSMenu()
                submenu.delegate = self
                submenu.autoenablesItems = false
                // Populated in `menuNeedsUpdate:` so a deep tree is only read
                // when the user actually opens that branch.
                pendingSubmenus[ObjectIdentifier(submenu)] = entry
                item.submenu = submenu
            } else if entry.isEnabled {
                item.target = self
                item.action = #selector(activate(_:))
                item.representedObject = Box(entry)
            }

            nsMenu.addItem(item)
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard let entry = pendingSubmenus.removeValue(forKey: ObjectIdentifier(menu))
        else { return }
        menu.removeAllItems()
        populate(menu, with: manager.entries(for: entry))
    }

    func menuDidClose(_ menu: NSMenu) {
        // Only the root menu closing means the interaction is over, submenus
        // close constantly while navigating.
        guard menu.supermenu == nil else { return }
        DispatchQueue.main.async { AppMenuPresenter.active = nil }
    }

    @objc private func activate(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? Box else { return }
        AppMenuReader.activate(box.entry)
    }

    /// `representedObject` is `Any?`, so the struct needs a reference wrapper.
    private final class Box {
        let entry: AppMenuEntry
        init(_ entry: AppMenuEntry) { self.entry = entry }
    }
}

extension AppMenuShortcut {
    var modifierFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if command { flags.insert(.command) }
        if shift { flags.insert(.shift) }
        if option { flags.insert(.option) }
        if control { flags.insert(.control) }
        if function { flags.insert(.function) }
        return flags
    }
}
