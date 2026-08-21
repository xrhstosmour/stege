import AppKit

struct AeroWindow: WindowModel {
    let id: Int
    let title: String
    let appName: String?
    var isFocused: Bool = false
    var appIcon: NSImage?
    let workspace: String?
    let bundleID: String?
    /// Reported alongside every window, which is what removes the need for the
    /// separate `list-workspaces --focused` call.
    let workspaceIsFocused: Bool

    enum CodingKeys: String, CodingKey {
        case id = "window-id"
        case title = "window-title"
        case appName = "app-name"
        case bundleID = "app-bundle-id"
        case workspace
        case workspaceIsFocused = "workspace-is-focused"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        appName = try container.decodeIfPresent(String.self, forKey: .appName)
        workspace = try container.decodeIfPresent(
            String.self, forKey: .workspace)
        workspaceIsFocused =
            try container.decodeIfPresent(Bool.self, forKey: .workspaceIsFocused)
            ?? false
        isFocused = false
        // Prefer the bundle identifier: looking an icon up by display name has
        // to scan every running application and picks the wrong one when two
        // share a name.
        bundleID = try container.decodeIfPresent(String.self, forKey: .bundleID)
        appIcon = IconCache.shared.icon(bundleID: bundleID, appName: appName)
    }
}

struct AeroSpace: SpaceModel {
    typealias WindowType = AeroWindow
    let workspace: String
    var id: String { workspace }
    var isFocused: Bool = false
    var windows: [AeroWindow] = []

    enum CodingKeys: String, CodingKey {
        case workspace
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        workspace = try container.decode(String.self, forKey: .workspace)
    }

    init(workspace: String, isFocused: Bool = false, windows: [AeroWindow] = [])
    {
        self.workspace = workspace
        self.isFocused = isFocused
        self.windows = windows
    }
}
