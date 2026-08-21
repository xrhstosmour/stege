import SwiftUI

/// Shown once at launch when a configured widget needs a permission it does not
/// have, so a widget never silently does nothing.
struct PermissionsView: View {
    @ObservedObject var model: PermissionsModel
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Stege needs a few permissions")
                    .font(.system(size: 16, weight: .semibold))
                Text(
                    "Only the ones your configured widgets actually use are listed."
                )
                .font(.system(size: 12))
                .opacity(0.7)
            }

            VStack(spacing: 10) {
                ForEach(model.items.filter(\.isRequired)) { item in
                    row(item)
                }
            }

            HStack {
                Text("Granting a permission applies immediately.")
                    .font(.system(size: 11))
                    .opacity(0.55)
                Spacer()
                Button("Done", action: onDismiss)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 460)
    }

    @ViewBuilder
    private func row(_ item: PermissionItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(
                systemName: item.isGranted
                    ? "checkmark.circle.fill" : "exclamationmark.circle"
            )
            .font(.system(size: 15))
            .foregroundStyle(item.isGranted ? Color.green : Color.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.system(size: 13, weight: .medium))
                Text(item.explanation).font(.system(size: 11)).opacity(0.7)
            }

            Spacer(minLength: 12)

            if item.isGranted {
                Text("Granted").font(.system(size: 11)).opacity(0.5)
            } else {
                Button("Grant") { model.request(item) }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.05)))
    }
}

/// Owns the window itself. Kept separate from the view so the window can be
/// closed from the button without the view needing a reference to it.
final class PermissionsWindowController {
    static let shared = PermissionsWindowController()
    private var window: NSWindow?
    private let model = PermissionsModel()

    private init() {}

    /// Shows the window only when something is actually missing, so a fully
    /// granted setup never sees it.
    func showIfNeeded() {
        model.refresh()
        guard !model.missing.isEmpty else { return }
        show()
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        window.title = "Stege Permissions"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(
            rootView: PermissionsView(model: model) { [weak self] in
                self?.window?.close()
            })
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
