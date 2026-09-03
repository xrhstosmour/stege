import Foundation

class AerospaceSpacesProvider: SpacesProvider, SwitchableSpacesProvider {
    typealias SpaceType = AeroSpace
    let executablePath = ConfigManager.shared.config.aerospace.path

    /// Every workspace that holds windows, with the focused one marked.
    ///
    /// One `aerospace` invocation, not four. `%{workspace-is-focused}` is
    /// reported per window, which replaces the separate focused-workspace
    /// query, and upstream additionally called that query again inside the
    /// window loop, once per window with no workspace. A second invocation is
    /// still needed for the focused *window*, since `aerospace` exposes no
    /// `window-is-focused` placeholder.
    func getSpacesWithWindows() -> [AeroSpace]? {
        guard let windows = fetchWindows() else { return nil }

        let focusedWindowID = focusedWindowID(among: windows)

        var spacesByID: [String: AeroSpace] = [:]
        for window in windows {
            guard let workspace = window.workspace, !workspace.isEmpty else {
                continue
            }
            var mutableWindow = window
            mutableWindow.isFocused = (window.id == focusedWindowID)

            var space =
                spacesByID[workspace]
                ?? AeroSpace(
                    workspace: workspace,
                    isFocused: window.workspaceIsFocused,
                    monitorScreenID: window.monitorScreenID)
            space.isFocused = space.isFocused || window.workspaceIsFocused
            space.windows.append(mutableWindow)
            spacesByID[workspace] = space
        }

        return spacesByID.values.map { space in
            var sorted = space
            sorted.windows.sort { $0.id < $1.id }
            return sorted
        }
    }

    func focusSpace(spaceId: String, needWindowFocus: Bool) {
        _ = runAerospaceCommand(arguments: ["workspace", spaceId])
    }

    func focusWindow(windowId: String) {
        _ = runAerospaceCommand(arguments: ["focus", "--window-id", windowId])
    }

    func moveWindow(windowId: String, toSpace spaceId: String) {
        _ = runAerospaceCommand(arguments: [
            "move-node-to-workspace", "--window-id", windowId, "--", spaceId,
        ])
    }

    private func runAerospaceCommand(arguments: [String]) -> Data? {
        guard TrustedExecutable.isTrusted(executablePath) else {
            Log.spaces.error(
                "aerospace.path is not a trusted binary, refusing to run it: \(self.executablePath, privacy: .public)"
            )
            return nil
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        do {
            try process.run()
        } catch {
            Log.spaces.error(
                "aerospace could not be run: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return data
    }

    private func fetchWindows() -> [AeroWindow]? {
        guard
            let data = runAerospaceCommand(arguments: [
                "list-windows", "--all", "--json", "--format",
                "%{window-id} %{app-name} %{app-bundle-id} %{window-title} "
                    + "%{workspace} %{workspace-is-focused} "
                    + "%{monitor-appkit-nsscreen-screens-id}",
            ])
        else { return nil }
        do {
            return try JSONDecoder().decode([AeroWindow].self, from: data)
        } catch {
            Log.spaces.error(
                "aerospace returned something unreadable: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Which window has focus, without spawning a second `aerospace`.
    ///
    /// The window server already knows, and `FrontmostWindow` reads it out of
    /// the list it publishes. That answer is only trusted when it names one of
    /// the windows just listed, which is the check that makes it safe: a
    /// frontmost application `AeroSpace` does not manage, or one showing no
    /// ordinary window, falls through to asking `AeroSpace` and costs exactly
    /// what it cost before.
    private func focusedWindowID(among windows: [AeroWindow]) -> Int? {
        if let found = FrontmostWindowReader.current(),
            windows.contains(where: { $0.id == found })
        {
            return found
        }
        return fetchFocusedWindowID()
    }

    private func fetchFocusedWindowID() -> Int? {
        guard
            let data = runAerospaceCommand(arguments: [
                "list-windows", "--focused", "--json", "--format",
                "%{window-id} %{window-title} %{app-name} %{workspace}",
            ])
        else { return nil }
        return try? JSONDecoder().decode([AeroWindow].self, from: data).first?.id
    }
}
