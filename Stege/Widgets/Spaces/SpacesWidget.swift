import SwiftUI

struct SpacesWidget: View {
    @ObservedObject var viewModel = SpacesViewModel.shared
    @Environment(\.barScreenIndex) private var screenIndex

    @ObservedObject var configManager = ConfigManager.shared
    /// The app menus widget takes this widget's place while it is revealed, so
    /// the bar shows either the workspaces or the frontmost application's
    /// menus, never both at once.
    @ObservedObject private var reveal = AppMenusReveal.shared
    var foregroundHeight: CGFloat { configManager.config.bar.foreground.resolveHeight() }

    private var isStandingAside: Bool {
        reveal.swapsSpaces && reveal.isRevealed
    }

    /// The workspaces on this display.
    ///
    /// `AeroSpace` assigns workspaces to monitors, so with two displays every
    /// bar drew every workspace and both bars were identical, each of them
    /// half wrong. A workspace whose monitor is unknown, which is every
    /// workspace under `yabai`, is drawn on all of them as before.
    private var spaces: [AnySpace] {
        guard let screenIndex else { return viewModel.spaces }
        return viewModel.spaces.filter {
            $0.monitorScreenID == nil || $0.monitorScreenID == screenIndex
        }
    }

    var body: some View {
        HStack(spacing: foregroundHeight < 30 ? 0 : 8) {
            if !isStandingAside {
                ForEach(spaces) { space in
                    SpaceView(space: space)
                }
            }
        }
        .widgetBackground(horizontalPadding: 5, cornerRadius: 10)
        .animation(.smooth(duration: 0.3), value: spaces)
        .animation(.smooth(duration: 0.15), value: isStandingAside)
        .foregroundStyle(Color("Foreground"))
        .environmentObject(viewModel)
    }
}

/// This view shows a space with its windows.
private struct SpaceView: View {
    @EnvironmentObject var configProvider: ConfigProvider
    @EnvironmentObject var viewModel: SpacesViewModel

    var config: ConfigData { configProvider.config }
    var spaceConfig: ConfigData { config["space"]?.dictionaryValue ?? [:] }

    @ObservedObject var configManager = ConfigManager.shared
    var foregroundHeight: CGFloat { configManager.config.bar.foreground.resolveHeight() }

    var showKey: Bool { spaceConfig["show-key"]?.boolValue ?? true }

    let space: AnySpace

    @State var isHovered = false

    var body: some View {
        let isFocused = space.windows.contains { $0.isFocused } || space.isFocused
        HStack(spacing: 0) {
            Spacer().frame(width: 10)
            if showKey {
                Text(space.id)
                    .font(.headline)
                    .frame(minWidth: 15)
                    .fixedSize(horizontal: true, vertical: false)
                // Separates the key from the window icons, so it only belongs
                // here when there are icons. Unconditional, an empty
                // workspace's pill got 10pt on the left of its key and 15pt on
                // the right, since this ran with nothing after it to separate.
                if !space.windows.isEmpty {
                    Spacer().frame(width: 5)
                }
            }
            HStack(spacing: 2) {
                ForEach(space.windows) { window in
                    WindowView(window: window, space: space)
                }
            }
            Spacer().frame(width: 10)
        }
        .frame(height: 30)
        // The unfocused pill lifts under the pointer. Both branches used to be
        // `NoActive`, so the hover state was computed, animated, and invisible.
        .background(
            foregroundHeight < 30 ?
            (isFocused
             ? Color("NoActive")
             : Color.clear) :
                (isFocused
                 ? Color("Active")
                 : isHovered ? BarStyle.hoverFill : Color("NoActive"))
        )
        .clipShape(RoundedRectangle(cornerRadius: foregroundHeight < 30 ? 0 : 8, style: .continuous))
        .shadow(color: Color("Shadow"), radius: foregroundHeight < 30 ? 0 : 2)
        .transition(.blurReplace)
        .onTapGesture {
            // Switching is what was asked for, not the menus of whatever ends
            // up focused underneath the pointer afterwards.
            AppMenusReveal.shared.suppressUntilPointerLeaves()
            viewModel.switchToSpace(space, needWindowFocus: true)
        }
        .animation(BarStyle.hoverAnimation, value: isHovered)
        .onHover { value in
            isHovered = value
        }
    }
}

/// This view shows a window and its icon.
private struct WindowView: View {
    @EnvironmentObject var configProvider: ConfigProvider
    @EnvironmentObject var viewModel: SpacesViewModel

    var config: ConfigData { configProvider.config }
    var windowConfig: ConfigData { config["window"]?.dictionaryValue ?? [:] }
    var titleConfig: ConfigData {
        windowConfig["title"]?.dictionaryValue ?? [:]
    }

    var showTitle: Bool { windowConfig["show-title"]?.boolValue ?? true }
    var maxLength: Int { titleConfig["max-length"]?.intValue ?? 50 }
    var alwaysDisplayAppTitleFor: [String] { titleConfig["always-display-app-name-for"]?.arrayValue?.filter({ $0.stringValue != nil }).map { $0.stringValue! } ?? [] }

    /// The window that is already focused is the one the app menus widget
    /// swaps in for. Under `click` a click on it does the swap, and under
    /// `hover` the pointer resting on it does.
    @ObservedObject private var reveal = AppMenusReveal.shared

    let window: AnyWindow
    let space: AnySpace

    @State var isHovered = false

    /// Whether this pill is the one that reveals the menus. Only the focused
    /// window: making every pill a trigger is what stopped another workspace
    /// from being clickable, because aiming at one swapped it out for the
    /// menus on the way.
    private var isRevealTrigger: Bool {
        reveal.revealsOnHover && window.isFocused
    }

    /// Hoisted out of the modifier chain. Inline, the ternary pushed the
    /// whole body past what the compiler will infer in reasonable time.
    private var highlight: Color {
        isHovered || (!showTitle && window.isFocused)
            ? Color("Selected") : Color.clear
    }

    var body: some View {
        let titleMaxLength = maxLength
        let size: CGFloat = 21
        let sameAppCount = space.windows.filter { $0.appName == window.appName }
            .count
        let title = WindowLabel.text(
            applicationName: window.appName,
            title: window.title,
            hasSiblings: sameAppCount > 1,
            alwaysUseApplicationName: alwaysDisplayAppTitleFor.contains {
                $0 == window.appName
            }
        )
        let spaceIsFocused = space.windows.contains { $0.isFocused }
        HStack {
            ZStack {
                if let icon = window.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: size, height: size)
                        .shadow(
                            color: Color("Icon Shadow"),
                            radius: 2
                        )
                } else {
                    Image(systemName: "questionmark.circle")
                        .resizable()
                        .frame(width: size, height: size)
                }
            }
            // A minimized window is still in its workspace and still worth a
            // click, but it is not on screen, so it is drawn back.
            .opacity(window.isMinimized ? 0.4 : (spaceIsFocused && !window.isFocused ? 0.5 : 1))
            .transition(.blurReplace)

            if window.isFocused, !title.isEmpty, showTitle {
                HStack {
                    Text(
                        title.count > titleMaxLength
                            ? String(title.prefix(titleMaxLength)) + "..."
                            : title
                    )
                    .fixedSize(horizontal: true, vertical: false)
                    .shadow(color: Color("Foreground Shadow"), radius: 3)
                    .fontWeight(.semibold)
                    Spacer().frame(width: 5)
                }
                .transition(.blurReplace)
            }
        }
        .padding(.all, 2)
        .background(highlight)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .animation(BarStyle.hoverAnimation, value: isHovered)
        .frame(height: 30)
        .contentShape(Rectangle())
        .background(
            ZStack {
                if isRevealTrigger {
                    HoverTracker { reveal.setHovered($0, from: .spaces) }
                    GeometryReader { geometry in
                        Color.clear
                            .onAppear {
                                reveal.setSpan(
                                    geometry.frame(in: .global), for: .spaces)
                            }
                            .onChange(of: geometry.frame(in: .global)) { _, new in
                                reveal.setSpan(new, for: .spaces)
                            }
                    }
                }
            }
            // Focus moves to another workspace and this pill stops being the
            // trigger, taking its tracking area with it while the pointer is
            // still inside. Nothing would report the pointer leaving.
            .onDisappear { reveal.forget(.spaces) }
        )
        .onChange(of: isRevealTrigger) { _, isTrigger in
            guard !isTrigger else { return }
            reveal.forget(.spaces)
        }
        .onTapGesture {
            if reveal.togglesOnClick, window.isFocused {
                reveal.toggleRevealed()
                return
            }
            reveal.suppressUntilPointerLeaves()
            viewModel.switchToSpaceAndWindow(space, window: window)
        }
        .onHover { value in
            isHovered = value
        }
        .help(
            reveal.togglesOnClick && window.isFocused
                ? "Show this application's menus" : "")
    }
}
