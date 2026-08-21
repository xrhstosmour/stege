import SwiftUI

/// The Apple menu, drawn as its own widget so it can be placed independently of
/// the application menus.
///
/// The menu itself is provided by the system rather than by the frontmost
/// application, so its contents, Sleep, Restart, Shut Down and the rest, are the
/// same whichever application is in front.
struct AppleMenuWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider

    @StateObject private var manager = AppMenusManager()
    @State private var rect: CGRect = .zero

    var body: some View {
        Image(systemName: "apple.logo")
            .font(.system(size: 14))
            .padding(.horizontal, 6)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
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
                guard let appleMenu = manager.appleMenu else { return }
                AppMenuPresenter.present(
                    menu: appleMenu, manager: manager, below: rect)
            }
            .opacity(manager.isTrusted ? 1 : 0.4)
            .help(
                manager.isTrusted
                    ? "Apple menu" : "Needs Accessibility permission")
    }
}
