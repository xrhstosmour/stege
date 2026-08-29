import SwiftUI

/// The Apple menu, drawn as its own widget so it can be placed independently of
/// the application menus.
///
/// The menu itself is provided by the system rather than by the frontmost
/// application, so its contents, Sleep, Restart, Shut Down and the rest, are the
/// same whichever application is in front.
struct AppleMenuWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    var config: ConfigData { configProvider.config }
    var iconSize: Double {
        Double(config["icon-size"]?.intValue ?? Int(BarStyle.glyphSize))
    }
    /// Draw the short menu in the bar's own style, rather than handing over
    /// to the full system one.
    var useShortMenu: Bool { config["short-menu"]?.boolValue ?? true }

    @StateObject private var manager = AppMenusManager()
    @State private var rect: CGRect = .zero

    @State private var isHovered = false

    var body: some View {
        Image(systemName: "apple.logo")
            .font(.system(size: iconSize))
            .padding(.horizontal, 6)
            .frame(maxHeight: .infinity)
            // Lit under the pointer like the menu titles beside it, so the two
            // ends of the same row behave the same way.
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(.white.opacity(isHovered ? 0.16 : 0))
                    .padding(.vertical, 5)
            )
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .animation(.smooth(duration: 0.12), value: isHovered)
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear { rect = geometry.frame(in: .global) }
                        .onChange(of: geometry.frame(in: .global)) { _, new in
                            rect = new
                        }
                }
            )
            .onTapGesture {
                // Without Accessibility there is no menu to show, and silently
                // doing nothing on click looks like a broken widget rather than
                // a missing permission. Prompt instead.
                guard manager.isTrusted else {
                    AppMenuReader.requestTrust()
                    return
                }
                guard let appleMenu = manager.appleMenu else { return }
                guard useShortMenu else {
                    AppMenuPresenter.present(
                        menu: appleMenu, manager: manager, below: rect)
                    return
                }
                MenuBarPopup.show(rect: rect, id: "applemenu") {
                    AppleMenuPopup(manager: manager)
                }
            }
            .opacity(manager.isTrusted ? 1 : 0.4)
            .help(
                manager.isTrusted
                    ? "Apple menu"
                    : "Click to grant Accessibility, needed to open the Apple menu")
    }
}
