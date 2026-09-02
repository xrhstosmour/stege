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
    var isFocused: Bool { get }
    var appIcon: NSImage? { get set }
}

protocol SpacesProvider {
    associatedtype SpaceType: SpaceModel
    func getSpacesWithWindows() -> [SpaceType]?
}

protocol SwitchableSpacesProvider: SpacesProvider {
    func focusSpace(spaceId: String, needWindowFocus: Bool)
    func focusWindow(windowId: String)
}

struct AnyWindow: Identifiable, Equatable {
    let id: Int
    let title: String
    let appName: String?
    let isFocused: Bool
    let appIcon: NSImage?

    init<W: WindowModel>(_ window: W) {
        self.id = window.id
        self.title = window.title
        self.appName = window.appName
        self.isFocused = window.isFocused
        self.appIcon = window.appIcon
    }

    static func == (lhs: AnyWindow, rhs: AnyWindow) -> Bool {
        return lhs.id == rhs.id && lhs.title == rhs.title
            && lhs.appName == rhs.appName && lhs.isFocused == rhs.isFocused
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
        } else {
            _focusSpace = nil
            _focusWindow = nil
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
}
