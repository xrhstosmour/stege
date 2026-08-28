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
    /// `always` is the default and matches macOS. The other three keep the bar
    /// quiet until asked, which suits a narrow display or a menu bar already
    /// carrying a lot of workspaces.
    ///
    /// `hover` is the one to avoid on a bar that also shows workspaces: the
    /// menus take the workspaces' place, and the pointer has to cross the
    /// workspaces to reach anything, so they vanish on the way and there is no
    /// way to click another window with the mouse. `click` is the same swap
    /// asked for deliberately, by clicking the pill of the window that is
    /// already focused, and the workspaces stay put until then.
    enum Visibility: String {
        case always
        case hover
        case modifier
        case click
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
            ZStack {
                if visibility == .hover {
                    HoverTracker { reveal.setHovered($0, from: .menus) }
                    GeometryReader { geometry in
                        Color.clear
                            .onAppear {
                                reveal.setSpan(
                                    geometry.frame(in: .global), for: .menus)
                            }
                            .onChange(of: geometry.frame(in: .global)) { _, new in
                                reveal.setSpan(new, for: .menus)
                            }
                    }
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
        reveal.revealsOnHover = visibility == .hover
        reveal.togglesOnClick = visibility == .click
    }

    private func releaseMonitors(for visibility: Visibility) {
        if visibility == .modifier { modifiers.release() }
        reveal.swapsSpaces = false
        reveal.revealsOnHover = false
        reveal.togglesOnClick = false
        reveal.setRevealed(false)
    }

    /// The frontmost application's icon, ahead of its name, so the swapped-in
    /// row is recognisable at a glance rather than a wall of words.
    ///
    /// Under `click` it is also the way back. The workspaces are what was
    /// clicked to get here and they are no longer on screen, so without this
    /// the swap would be one-way.
    @ViewBuilder
    private var applicationIcon: some View {
        if let icon = NSWorkspace.shared.frontmostApplication?.icon {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 15, height: 15)
                .padding(.leading, 4)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard visibility == .click else { return }
                    reveal.setRevealed(false)
                }
                .help(
                    visibility == .click
                        ? "Show the workspaces again"
                        : manager.applicationName)
        }
    }

    @ViewBuilder
    private func menuTitle(_ menu: AppMenuEntry, emphasised: Bool = false)
        -> some View
    {
        AppMenuTitle(
            title: menu.title, emphasised: emphasised,
            onFrameChange: { rects[menu.id] = $0 },
            action: {
                AppMenuPresenter.present(
                    menu: menu, manager: manager,
                    below: rects[menu.id] ?? .zero)
            })
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

/// One menu title, lit under the pointer the way macOS lights its own.
///
/// Without this the titles were the only things in the bar that gave no sign
/// they could be clicked: the workspace pills highlight, every popup row
/// highlights, and File, Edit and View sat there as plain text.
///
/// `onHover` rather than a tracking area, because unlike the reveal this only
/// has to be right while the pointer is over the title itself, and the popup
/// that opens takes the pointer with it.
private struct AppMenuTitle: View {
    let title: String
    let emphasised: Bool
    let onFrameChange: (CGRect) -> Void
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Text(title)
            .font(.system(size: 13, weight: emphasised ? .semibold : .regular))
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(.white.opacity(isHovered ? 0.16 : 0))
            )
            .contentShape(Rectangle())
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { onFrameChange(geometry.frame(in: .global)) }
                        .onChange(of: geometry.frame(in: .global)) { _, new in
                            onFrameChange(new)
                        }
                }
            )
            .onHover { isHovered = $0 }
            .animation(.smooth(duration: 0.12), value: isHovered)
            .onTapGesture(perform: action)
    }
}
