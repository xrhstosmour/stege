import AppKit

protocol SpaceModel: Identifiable, Equatable, Codable {
    associatedtype WindowType: WindowModel
    var isFocused: Bool { get set }
    var windows: [WindowType] { get set }
}

protocol WindowModel: Identifiable, Equatable, Codable {
    var id: Int { get }
    var title: String { get }
    var appName: String? { get }
    var bundleID: String? { get }
    var isFocused: Bool { get }
    var appIcon: NSImage? { get set }
}

extension WindowModel {
    /// Not every window manager reports one. `yabai` gives the display name
    /// only, which is what its windows fall back to for their icon.
    var bundleID: String? { nil }
}

protocol SpacesProvider {
    associatedtype SpaceType: SpaceModel
    func getSpacesWithWindows() -> [SpaceType]?
}

protocol SwitchableSpacesProvider: SpacesProvider {
    func focusSpace(spaceId: String, needWindowFocus: Bool)
    func focusWindow(windowId: String)
    /// Puts a window back in a workspace it is no longer in. Only used after a
    /// minimized window is restored, because the window manager assigns it to
    /// whichever workspace happens to be focused at the time.
    func moveWindow(windowId: String, toSpace spaceId: String)
}

extension SwitchableSpacesProvider {
    /// Nothing by default. `yabai` reports minimized windows itself, so nothing
    /// is ever restored from memory under it and there is nothing to move.
    func moveWindow(windowId: String, toSpace spaceId: String) {}
}

struct AnyWindow: Identifiable, Equatable {
    let id: Int
    let title: String
    let appName: String?
    let bundleID: String?
    let isFocused: Bool
    /// Put back from memory rather than reported by the window manager. See
    /// `MinimizedWindowMemory`.
    let isMinimized: Bool
    let appIcon: NSImage?

    init<W: WindowModel>(_ window: W) {
        self.id = window.id
        self.title = window.title
        self.appName = window.appName
        self.bundleID = window.bundleID
        self.isFocused = window.isFocused
        self.isMinimized = false
        self.appIcon = window.appIcon
    }

    init(
        id: Int, title: String, appName: String?, bundleID: String?,
        isFocused: Bool, isMinimized: Bool, appIcon: NSImage?
    ) {
        self.id = id
        self.title = title
        self.appName = appName
        self.bundleID = bundleID
        self.isFocused = isFocused
        self.isMinimized = isMinimized
        self.appIcon = appIcon
    }

    static func == (lhs: AnyWindow, rhs: AnyWindow) -> Bool {
        return lhs.id == rhs.id && lhs.title == rhs.title
            && lhs.appName == rhs.appName && lhs.isFocused == rhs.isFocused
            && lhs.isMinimized == rhs.isMinimized
    }
}

struct AnySpace: Identifiable, Equatable {
    let id: String
    let isFocused: Bool
    let windows: [AnyWindow]
    /// Which display this workspace belongs to, counting `NSScreen.screens`
    /// from one. Nil where the window manager does not say, and a workspace
    /// that does not say is drawn on every bar.
    let monitorScreenID: Int?

    init<S: SpaceModel>(_ space: S) {
        if let aero = space as? AeroSpace {
            self.id = aero.workspace
            self.monitorScreenID = aero.monitorScreenID
        } else if let yabai = space as? YabaiSpace {
            self.id = String(yabai.id)
            self.monitorScreenID = nil
        } else {
            self.id = "0"
            self.monitorScreenID = nil
        }
        self.isFocused = space.isFocused
        self.windows = space.windows.map { AnyWindow($0) }
    }

    init(
        id: String, isFocused: Bool, windows: [AnyWindow],
        monitorScreenID: Int?
    ) {
        self.id = id
        self.isFocused = isFocused
        self.windows = windows
        self.monitorScreenID = monitorScreenID
    }

    static func == (lhs: AnySpace, rhs: AnySpace) -> Bool {
        return lhs.id == rhs.id && lhs.isFocused == rhs.isFocused
            && lhs.monitorScreenID == rhs.monitorScreenID
            && lhs.windows == rhs.windows
    }
}

class AnySpacesProvider {
    private let _getSpacesWithWindows: () -> [AnySpace]?
    private let _focusSpace: ((String, Bool) -> Void)?
    private let _focusWindow: ((String) -> Void)?
    private let _moveWindow: ((String, String) -> Void)?

    init<P: SpacesProvider>(_ provider: P) {
        _getSpacesWithWindows = {
            provider.getSpacesWithWindows()?.map { AnySpace($0) }
        }
        if let switchable = provider as? any SwitchableSpacesProvider {
            _focusSpace = { spaceId, needWindowFocus in
                switchable.focusSpace(
                    spaceId: spaceId, needWindowFocus: needWindowFocus)
            }
            _focusWindow = { windowId in
                switchable.focusWindow(windowId: windowId)
            }
            _moveWindow = { windowId, spaceId in
                switchable.moveWindow(windowId: windowId, toSpace: spaceId)
            }
        } else {
            _focusSpace = nil
            _focusWindow = nil
            _moveWindow = nil
        }
    }

    func getSpacesWithWindows() -> [AnySpace]? {
        _getSpacesWithWindows()
    }

    func focusSpace(spaceId: String, needWindowFocus: Bool) {
        _focusSpace?(spaceId, needWindowFocus)
    }

    func focusWindow(windowId: String) {
        _focusWindow?(windowId)
    }

    func moveWindow(windowId: String, toSpace spaceId: String) {
        _moveWindow?(windowId, spaceId)
    }
}
