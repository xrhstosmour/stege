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

    @StateObject private var manager = AppMenusManager()
    @State private var rects: [String: CGRect] = [:]

    var body: some View {
        HStack(spacing: 2) {
            if !manager.isTrusted {
                permissionPrompt
            } else {
                ForEach(
                    Array(manager.menus.prefix(maximumMenus).enumerated()),
                    id: \.element.id
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
        .animation(.smooth(duration: 0.15), value: manager.applicationName)
        .onChange(of: manager.applicationName) { _, _ in
            // The previous application's menu titles are gone, so their frames
            // are too. Without this they accumulate for the life of the process.
            rects.removeAll()
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
