import SwiftUI

/// A chevron that brings back what hiding the real menu bar took away.
///
/// Two modes.
///
/// `extras`, the default, appends the other applications' status items to the
/// bar: 1Password, Docker, Dropbox and the rest, drawn as their own icons and
/// pressed for real when clicked. Nothing leaves the screen and Stege's own
/// widgets stay where they are. See `MenuBarExtrasReader` for how the items are
/// found without screenshotting them.
///
/// `collapse` is the older behaviour, where the bar gets out of the way so the
/// real menu bar underneath becomes reachable. It is the fallback for anything
/// the Accessibility route cannot reach. `sticky` keeps it out of the way until
/// it is expanded again, leaving a small button in the middle of the menu bar
/// to do that with, and `sticky = false` brings it back once the pointer
/// travels far enough down or a timeout expires.
struct RevealWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    var config: ConfigData { configProvider.config }

    enum Mode: String {
        case extras
        case collapse
    }

    var mode: Mode {
        Mode(rawValue: config["mode"]?.stringValue ?? "extras") ?? .extras
    }

    /// Three points more than a glyph.
    ///
    /// An application icon is square artwork with its own padding baked in,
    /// so at the glyph's own point size it draws visibly smaller than the
    /// symbols beside it: an SF Symbol at 15 points puts 15 points of ink on
    /// the screen, a 15 point application icon rather less.
    var iconSize: CGFloat {
        CGFloat(config["icon-size"]?.intValue ?? Int(BarStyle.glyphSize) + 3)
    }

    /// How the appended icons are drawn.
    ///
    /// `colour` is the default: the icons are drawn as the applications drew
    /// them. This was `monochrome` on the argument that a row of full-colour
    /// application icons next to single-weight glyphs looks like two bars
    /// stapled together. It does, a little, but greyscaling somebody's icon is
    /// also the surest way to make it unrecognisable, and recognising them at
    /// a glance is the entire job of this row. `monochrome` is still there for
    /// anyone who wants the flatter look.
    ///
    /// Neither applies to an application that publishes a real menu bar
    /// template, which is line art meant for exactly this and is always tinted
    /// to the bar's own foreground.
    ///
    /// Neither is the glyph the application actually puts in the menu bar, and
    /// there is no way to be. Dumping every accessibility attribute of a
    /// third-party status item returns a frame, a role and sometimes a name,
    /// and no image: `Maccy` and `SwipeAeroSpace` publish nothing to draw with.
    /// Apple's own extras do, `AXPath` on the battery hands back the shape it
    /// drew, but those are the ones Stege replaces with its own widgets.
    ///
    /// So the only route to the real glyph is photographing the item, which
    /// needs Screen Recording and, because a hidden status item is parked off
    /// screen where `ScreenCaptureKit` refuses to capture it, the menu bar
    /// pulled down for every refresh. What is left is to draw the application
    /// icon at the bar's own size and let the glyphs stay the brighter mark.
    enum IconStyle: String {
        case monochrome
        case colour
        case color
    }

    var iconStyle: IconStyle {
        IconStyle(rawValue: config["icon-style"]?.stringValue ?? "colour")
            ?? .colour
    }

    private var isMonochrome: Bool { iconStyle == .monochrome }

    /// Applications that sit in the bar permanently, outside the chevron.
    ///
    /// This is what a tray manager is actually for. Fidelity to the system's
    /// own glyphs is not what makes Bartender worth running, having three
    /// icons in the bar instead of eleven is, and that needs no permission at
    /// all.
    var pinned: [String] { identifiers("always-show") }
    /// Applications that never appear, behind the chevron or otherwise.
    ///
    /// Either list takes a bundle identifier or the application's name, since
    /// the name is the only one of the two anybody can read off the screen.
    /// See `RevealFilter`.
    var hidden: [String] { identifiers("hidden") }

    private func identifiers(_ key: String) -> [String] {
        config[key]?.arrayValue?.compactMap { $0.stringValue } ?? []
    }

    /// Adds the item's application to the `hidden` list in the configuration
    /// file, which is what makes it stay gone. The file is watched, so the row
    /// redraws without it as soon as the write lands, and the entry outlives
    /// the restart because the file is where the list lives.
    ///
    /// This is the one thing macOS's own Menu Bar settings do that the row
    /// otherwise could not: pick an item and never see it again.
    private func hide(_ item: MenuBarExtraItem) {
        guard let entry = entry(for: item), !matches(item, hiddenEntries) else {
            return
        }
        ConfigManager.shared.updateConfigValue(
            key: "widgets.default.reveal.hidden",
            rawValue: RevealFilter.tomlArray(hidden + [entry]))
    }

    private func entry(for item: MenuBarExtraItem) -> String? {
        RevealFilter.entry(
            bundleIdentifier: item.bundleIdentifier, name: item.name)
    }

    private func matches(_ item: MenuBarExtraItem, _ entries: Set<String>) -> Bool {
        RevealFilter.matches(
            bundleIdentifier: item.bundleIdentifier, name: item.name,
            in: entries)
    }

    /// Normalised once per render rather than once per item per list.
    private var hiddenEntries: Set<String> { RevealFilter.normalisedSet(hidden) }
    private var pinnedEntries: Set<String> { RevealFilter.normalisedSet(pinned) }

    private var visibleItems: [MenuBarExtraItem] {
        let hiddenEntries = hiddenEntries
        return reader.items.filter { !matches($0, hiddenEntries) }
    }

    private var pinnedItems: [MenuBarExtraItem] {
        let pinnedEntries = pinnedEntries
        return visibleItems.filter { matches($0, pinnedEntries) }
    }

    private var collapsedItems: [MenuBarExtraItem] {
        let pinnedEntries = pinnedEntries
        return visibleItems.filter { !matches($0, pinnedEntries) }
    }

    /// Stay out of the way until pressed again, rather than coming back on
    /// pointer movement. `collapse` only.
    var sticky: Bool { config["sticky"]?.boolValue ?? true }
    /// How far the pointer must move down before the bar returns. Unused in
    /// sticky mode.
    var returnThreshold: Double {
        Double(config["return-threshold"]?.intValue ?? 80)
    }
    /// Seconds after which the bar returns even if the pointer never moves.
    /// Unused in sticky mode.
    var timeout: Double { Double(config["timeout"]?.intValue ?? 10) }

    @ObservedObject private var visibility = BarVisibility.shared
    @ObservedObject private var reader = MenuBarExtrasReader.shared
    private var isShowingExtras: Bool { visibility.isShowingExtras }

    /// The gap the rest of the bar uses, so the appended icons keep the row's
    /// rhythm rather than sitting closer together than everything else.
    private var spacing: CGFloat {
        ConfigManager.shared.config.bar.foreground.spacing
    }

    var body: some View {
        HStack(spacing: spacing) {
            // The chevron only when there is something behind it. With
            // everything pinned or hidden it would open onto nothing.
            if mode == .collapse || !collapsedItems.isEmpty || !reader.isTrusted
            {
                chevron
            }
            if mode == .extras {
                if !reader.isTrusted {
                    permissionLock
                } else {
                    // Each list only when it has something in it. An empty
                    // `HStack` is still a subview, so the row spaced past it
                    // and the chevron sat one gap further from the widget on
                    // its right than every other pair in the bar.
                    if isShowingExtras, !collapsedItems.isEmpty {
                        extras(collapsedItems)
                    }
                    if !pinnedItems.isEmpty {
                        extras(pinnedItems)
                    }
                }
            }
        }
        .animation(.smooth(duration: 0.2), value: isShowingExtras)
        .animation(.smooth(duration: 0.2), value: reader.items.count)
        .onAppear {
            // At launch, not on the first press. Pinned items have to be in
            // the bar before anything is pressed.
            guard mode == .extras else { return }
            reader.startWatching()
            reader.refresh()
        }
    }

    private var chevron: some View {
        Image(systemName: chevronSymbol)
            .font(.system(size: BarStyle.chevronSize, weight: .semibold))
            // Sized to its ink, like every other mark in the row. A chevron at
            // 12 points inks about 5, so a box the size of the point size left
            // three points of nothing either side and made this the widest gap
            // in the bar. Both directions ink the same width, so the box does
            // not have to promise anything beyond the one it draws.
            .frame(
                width: GlyphInk.width(
                    of: "chevron.left", size: BarStyle.chevronSize))
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .background(.black.opacity(0.001))
            .onTapGesture(perform: toggle)
            .help(helpText)
    }

    /// Points at what pressing it does, not at where the items are. `<` pulls
    /// the rest of the menu bar in from the right, `>` sends it back.
    private var chevronSymbol: String {
        switch mode {
        case .extras: return isShowingExtras ? "chevron.right" : "chevron.left"
        case .collapse: return sticky ? "chevron.left" : "chevron.right"
        }
    }

    private var helpText: String {
        switch mode {
        case .extras:
            return isShowingExtras
                ? "Hide the other menu bar items"
                : "Show the other menu bar items"
        case .collapse:
            return "Show the system menu bar"
        }
    }

    private func toggle() {
        switch mode {
        case .extras:
            if !isShowingExtras { reader.refresh() }
            visibility.isShowingExtras.toggle()
        case .collapse:
            if sticky {
                visibility.toggleCollapsed()
            } else {
                visibility.hide(
                    returnThreshold: returnThreshold, timeout: timeout)
            }
        }
    }

    private var permissionLock: some View {
        Image(systemName: "lock.fill")
            .font(.system(size: 10))
            .help("Stege needs Accessibility permission to read these")
    }

    private func extras(_ items: [MenuBarExtraItem]) -> some View {
        HStack(spacing: spacing) {
            ForEach(items) { item in
                extraIcon(item)
            }
        }
    }

    @ViewBuilder
    private func extraIcon(_ item: MenuBarExtraItem) -> some View {
        if let icon = item.icon, item.isMenuBarGlyph {
            // The application's real menu bar glyph. Line art meant for
            // exactly this, so it is drawn the way the bar draws its own
            // marks: one colour, full strength, no toning down.
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: iconSize, height: iconSize)
                .foregroundStyle(Color("Foreground Outside"))
                .modifier(ExtraIconInteraction(item: item, reader: reader, hide: hide))
        } else {
            Group {
                if let icon = item.icon {
                    Image(nsImage: icon).resizable()
                } else {
                    Image(systemName: "app.dashed").resizable()
                }
            }
            .scaledToFit()
            .frame(width: iconSize, height: iconSize)
            .grayscale(isMonochrome ? 1 : 0)
            // Enough contrast to read against black, but not lifted towards
            // white. These are filled application icons sitting next to
            // single-weight line glyphs, and brightening them made the
            // borrowed half of the row the brightest thing in it.
            .contrast(isMonochrome ? 1.2 : 1)
            .opacity(isMonochrome ? 0.85 : 1)
            .modifier(ExtraIconInteraction(item: item, reader: reader, hide: hide))
        }
    }
}

/// What both kinds of appended icon do when pointed at, kept in one place so
/// the two drawings cannot drift apart.
private struct ExtraIconInteraction: ViewModifier {
    let item: MenuBarExtraItem
    let reader: MenuBarExtrasReader
    let hide: (MenuBarExtraItem) -> Void

    /// An application with neither a bundle identifier nor a name cannot be
    /// written down, so there is nothing for the entry to say.
    private var canHide: Bool {
        RevealFilter.entry(
            bundleIdentifier: item.bundleIdentifier, name: item.name) != nil
    }

    func body(content: Content) -> some View {
        content
            .barHover(
                cornerRadius: 5, verticalInset: 4, horizontalOutset: 3)
            .contentShape(Rectangle())
            .onTapGesture { reader.press(item) }
            .help(item.name)
            .contextMenu {
                if canHide {
                    Button("Hide \(item.name)") { hide(item) }
                }
            }
    }
}

/// The button left behind while the bar is collapsed.
///
/// Drawn on its own tiny panel rather than inside the bar, because the bar is
/// gone: what is on screen underneath is the real menu bar, and a full-width
/// panel over it would swallow the clicks meant for the status items it just
/// revealed.
struct CollapsedRevealView: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(BarStyle.ink)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(BarStyle.surface)
            .contentShape(Rectangle())
            .onTapGesture { BarVisibility.shared.toggleCollapsed() }
            .help("Bring Stege back")
    }
}
