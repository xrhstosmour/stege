import AppKit
import SwiftUI

/// The frontmost application's menu titles, the feature prototyped in
/// upstream issue #5 but never shipped.
///
/// Clicking a title opens Stege's own rendering of that menu rather than the
/// system one, which is what lets it match the rest of the bar. Selecting an
/// entry presses the real Accessibility element, so the application behaves
/// exactly as it would through its own menu bar.
struct AppMenusWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    var config: ConfigData { configProvider.config }

    /// How many menu titles to draw before truncating. Chrome exposes eleven,
    /// which crowds out the rest of the bar on a laptop display.
    var maximumMenus: Int { config["max-menus"]?.intValue ?? 6 }
    /// Whether to emphasise the application's own name menu, the first one,
    /// the way macOS does. The menu itself is always drawn, since it holds
    /// About and Quit.
    var showApplicationName: Bool {
        config["show-application-name"]?.boolValue ?? true
    }

    /// When the menu titles past the application's own name are drawn.
    ///
    /// `always` is the default and matches macOS. `hover` and `modifier` keep
    /// the bar quiet until asked, which suits a narrow display or a menu bar
    /// already carrying a lot of workspaces.
    enum Visibility: String {
        case always
        case hover
        case modifier
    }

    var visibility: Visibility {
        Visibility(rawValue: config["visibility"]?.stringValue ?? "always")
            ?? .always
    }

    /// Which key reveals the menus under `visibility = "modifier"`.
    var modifierKey: NSEvent.ModifierFlags {
        ModifierKeyMonitor.modifier(
            named: config["modifier-key"]?.stringValue ?? "option")
    }

    @StateObject private var manager = AppMenusManager()
    @StateObject private var modifiers = ModifierKeyMonitor.shared
    @ObservedObject private var reveal = AppMenusReveal.shared
    @State private var rects: [String: CGRect] = [:]

    /// Whether the menus are drawn at all.
    ///
    /// Under `always` they simply are. The other two modes take the workspace
    /// pills' place when asked and give it back afterwards, so the answer is
    /// shared state rather than this view's own: the pointer that opens them is
    /// usually over the pills, not over anything this widget drew.
    private var menusRevealed: Bool {
        visibility == .always || reveal.isRevealed
    }

    private var visibleMenus: [AppMenuEntry] {
        Array(manager.menus.prefix(maximumMenus))
    }

    var body: some View {
        HStack(spacing: 2) {
            if !manager.isTrusted {
                permissionPrompt
            } else if menusRevealed {
                applicationIcon
                ForEach(
                    Array(visibleMenus.enumerated()), id: \.element.id
                ) { index, menu in
                    // The first menu an application publishes is its own name
                    // menu, the one holding About and Quit. Drawing the name
                    // separately as well printed it twice, "Finder Finder".
                    // macOS emphasises that first menu instead, and doing the
                    // same keeps it clickable rather than an inert label.
                    menuTitle(
                        menu,
                        emphasised: index == 0 && showApplicationName)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .background(.black.opacity(0.001))
        .background(
            // Only installed for the mode that needs it, so `always` and
            // `modifier` carry no tracking area at all.
            Group {
                if visibility == .hover {
                    HoverTracker { reveal.setHovered($0, from: .menus) }
                }
            }
        )
        .animation(.smooth(duration: 0.15), value: menusRevealed)
        .onAppear { retainMonitors(for: visibility) }
        .onDisappear { releaseMonitors(for: visibility) }
        .onChange(of: visibility) { previous, current in
            // The configuration file is watched, so this can change while the
            // bar is running, and the monitors have to follow it.
            releaseMonitors(for: previous)
            retainMonitors(for: current)
        }
        .onChange(of: modifiers.isHolding(modifierKey)) { _, holding in
            guard visibility == .modifier else { return }
            reveal.setRevealed(holding)
        }
        .animation(.smooth(duration: 0.15), value: manager.applicationName)
        .onChange(of: manager.applicationName) { _, _ in
            // The previous application's menu titles are gone, so their frames
            // are too. Without this they accumulate for the life of the process.
            rects.removeAll()
        }
    }

    /// Hover needs no monitor: its tracking area lives in the view hierarchy
    /// and is torn down with it.
    private func retainMonitors(for visibility: Visibility) {
        if visibility == .modifier { modifiers.retain() }
        // Told here rather than computed by the spaces widget, because a bar
        // with no app menus widget in it must never see its pills disappear.
        reveal.swapsSpaces = visibility != .always
    }

    private func releaseMonitors(for visibility: Visibility) {
        if visibility == .modifier { modifiers.release() }
        reveal.swapsSpaces = false
        reveal.setRevealed(false)
    }

    /// The frontmost application's icon, ahead of its name, so the swapped-in
    /// row is recognisable at a glance rather than a wall of words.
    @ViewBuilder
    private var applicationIcon: some View {
        if let icon = NSWorkspace.shared.frontmostApplication?.icon {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 15, height: 15)
                .padding(.leading, 4)
        }
    }

    @ViewBuilder
    private func menuTitle(_ menu: AppMenuEntry, emphasised: Bool = false)
        -> some View
    {
        Text(menu.title)
            .font(.system(size: 13, weight: emphasised ? .semibold : .regular))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { rects[menu.id] = geometry.frame(in: .global) }
                        .onChange(of: geometry.frame(in: .global)) { _, new in
                            rects[menu.id] = new
                        }
                }
            )
            .onTapGesture {
                AppMenuPresenter.present(
                    menu: menu, manager: manager,
                    below: rects[menu.id] ?? .zero)
            }
    }

    /// Without Accessibility permission there are no menus to show at all, so
    /// the widget says so and opens the right settings pane instead of silently
    /// rendering nothing.
    private var permissionPrompt: some View {
        HStack(spacing: 4) {
            Image(systemName: "lock.fill").font(.system(size: 10))
            Text("Enable Accessibility")
                .font(.system(size: 13))
        }
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .onTapGesture { AppMenuReader.requestTrust() }
    }
}
