import AppKit
import ApplicationServices

/// One entry in an application menu, or a separator between entries.
struct AppMenuEntry: Identifiable {
    let id = UUID()
    let title: String
    let shortcut: AppMenuShortcut?
    let isEnabled: Bool
    let isChecked: Bool
    let hasSubmenu: Bool
    let isSeparator: Bool

    /// The live Accessibility element, kept so activating the entry presses the
    /// real menu item rather than trying to reproduce what it does.
    let element: AXUIElement?
}

/// A menu entry's keyboard equivalent, already decoded into modifier flags.
struct AppMenuShortcut {
    let key: String
    let command: Bool
    let shift: Bool
    let option: Bool
    let control: Bool
    let function: Bool

    /// Rendered in the order macOS itself uses: control, option, shift, command.
    var display: String {
        var result = ""
        if function { result += "fn" }
        if control { result += "\u{2303}" }
        if option { result += "\u{2325}" }
        if shift { result += "\u{21E7}" }
        if command { result += "\u{2318}" }
        return result + key.uppercased()
    }
}

enum AppMenuReader {

    /// Bit layout of `AXMenuItemCmdModifiers`.
    ///
    /// This is *not* Carbon's `kMenuNoCommandModifier` layout, despite the
    /// similar shape. It was derived by reading the raw value for menu entries
    /// whose real shortcuts are known: Log Out `Shift-Command-Q` reports 1,
    /// Force Quit `Option-Command-Escape` reports 2, Lock Screen
    /// `Control-Command-Q` reports 4, Show Next Tab `Control-Tab` reports 12,
    /// and Window Fill `fn-Control-F` reports 28.
    private enum Modifier {
        static let shift = 1
        static let option = 2
        static let control = 4
        /// Set when the shortcut does *not* involve Command, so the sense is
        /// inverted relative to every other flag here.
        static let noCommand = 8
        static let function = 16
    }

    private static func attribute<T>(
        _ element: AXUIElement, _ name: String, as type: T.Type
    ) -> T? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, name as CFString, &value)
                == .success
        else { return nil }
        return value as? T
    }

    /// The menu bar of a running application, or nil if it exposes none.
    private static func menuBar(of application: NSRunningApplication)
        -> AXUIElement?
    {
        let element = AXUIElementCreateApplication(
            application.processIdentifier)
        return attribute(element, kAXMenuBarAttribute, as: AXUIElement.self)
    }

    /// The top-level menu titles, `File`, `Edit` and so on.
    ///
    /// Deliberately shallow. Reading only the titles costs well under a
    /// millisecond, so it can run on every application switch, while the
    /// entries behind each title are read on demand in `entries(under:)`.
    /// The Apple menu is dropped because Stege draws its own.
    static func topLevelMenus(of application: NSRunningApplication)
        -> [AppMenuEntry]
    {
        guard let bar = menuBar(of: application),
            let items = attribute(bar, kAXChildrenAttribute, as: [AXUIElement].self)
        else { return [] }

        return items.dropFirst().compactMap { item in
            guard let title = attribute(item, kAXTitleAttribute, as: String.self),
                !title.isEmpty
            else { return nil }
            return AppMenuEntry(
                title: title,
                shortcut: nil,
                isEnabled: attribute(item, kAXEnabledAttribute, as: Bool.self) ?? true,
                isChecked: false,
                hasSubmenu: true,
                isSeparator: false,
                element: item)
        }
    }

    /// The entries inside a menu, one level deep.
    ///
    /// A menu bar item holds a single child, the menu itself, whose children are
    /// the entries. Applications populate these eagerly, verified across Finder,
    /// Chrome, `1Password`, `WezTerm` and System Settings, so nothing has to be
    /// opened on screen to read them.
    static func entries(under item: AXUIElement) -> [AppMenuEntry] {
        guard
            let menu = attribute(item, kAXChildrenAttribute, as: [AXUIElement].self)?
                .first,
            let children = attribute(menu, kAXChildrenAttribute, as: [AXUIElement].self)
        else { return [] }

        return children.map { entry in
            let title = attribute(entry, kAXTitleAttribute, as: String.self) ?? ""
            // Separators carry no title, which is the only thing distinguishing
            // them through the Accessibility API.
            guard !title.isEmpty else {
                return AppMenuEntry(
                    title: "", shortcut: nil, isEnabled: false, isChecked: false,
                    hasSubmenu: false, isSeparator: true, element: nil)
            }

            let submenu =
                attribute(entry, kAXChildrenAttribute, as: [AXUIElement].self)?
                .first
            let submenuEntries =
                submenu.flatMap {
                    attribute($0, kAXChildrenAttribute, as: [AXUIElement].self)
                } ?? []

            return AppMenuEntry(
                title: title,
                shortcut: shortcut(of: entry),
                isEnabled: attribute(entry, kAXEnabledAttribute, as: Bool.self) ?? true,
                isChecked: !(attribute(
                    entry, kAXMenuItemMarkCharAttribute, as: String.self) ?? "")
                    .isEmpty,
                hasSubmenu: !submenuEntries.isEmpty,
                isSeparator: false,
                element: entry)
        }
    }

    private static func shortcut(of entry: AXUIElement) -> AppMenuShortcut? {
        guard
            let key = attribute(entry, kAXMenuItemCmdCharAttribute, as: String.self),
            !key.isEmpty
        else { return nil }
        let raw = attribute(entry, kAXMenuItemCmdModifiersAttribute, as: Int.self) ?? 0
        return AppMenuShortcut(
            key: key,
            command: raw & Modifier.noCommand == 0,
            shift: raw & Modifier.shift != 0,
            option: raw & Modifier.option != 0,
            control: raw & Modifier.control != 0,
            function: raw & Modifier.function != 0)
    }

    /// Activates a menu entry by pressing the real item, so whatever the
    /// application does on selection happens exactly as it normally would.
    @discardableResult
    static func activate(_ entry: AppMenuEntry) -> Bool {
        guard let element = entry.element, entry.isEnabled else { return false }
        return AXUIElementPerformAction(element, kAXPressAction as CFString)
            == .success
    }

    /// Whether the process holds Accessibility permission. Without it the menu
    /// bar of other applications is invisible and every read returns nothing.
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Prompts for Accessibility permission, showing the system's own dialog.
    static func requestTrust() {
        let options =
            [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true]
            as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
