import SwiftUI

/// Shown once at launch when a configured widget needs a permission it does not
/// have, so a widget never silently does nothing.
///
/// Drawn the way System Settings draws a pane: the application's own icon over
/// a title and one line of explanation, then a single grouped list with hairline
/// separators. It used to be a stack of separately shaded cards, which read as
/// eight controls rather than one list, and gave the window a texture nothing
/// else in macOS has.
struct PermissionsView: View {
    @ObservedObject var model: PermissionsModel
    let onDismiss: () -> Void

    private var required: [PermissionItem] {
        model.items.filter(\.isRequired)
    }

    var body: some View {
        VStack(spacing: 20) {
            header

            VStack(spacing: 0) {
                ForEach(Array(required.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Divider().padding(.leading, 52)
                    }
                    row(item)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            )

            HStack(spacing: 12) {
                Text("A permission applies the moment it is granted.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("Done", action: onDismiss)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
            Text(
                required.allSatisfy(\.isGranted)
                    ? "Stege's permissions"
                    : "Stege needs a few permissions"
            )
            .font(.headline)
            Text("Only the ones your configured widgets actually use are listed.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func row(_ item: PermissionItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(
                systemName: item.isGranted
                    ? "checkmark.circle.fill" : "exclamationmark.circle.fill"
            )
            .font(.system(size: 15))
            .foregroundStyle(item.isGranted ? Color.green : Color.orange)
            .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.body)
                Text(item.explanation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            if item.isGranted {
                Text("Granted")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Button("Grant") { model.request(item) }
                    .controlSize(.small)
            }

            // Reopening this window closes no door: `request(_:)` above
            // prompts once and never again after that, so a permission
            // granted or denied by accident, or reset by macOS across an
            // update, otherwise has no way back short of hunting through
            // System Settings by hand.
            Button {
                model.openSettings(item)
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Open \(item.title) in System Settings")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
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
    /// Asked twice, a second and a half apart, before anything is put on
    /// screen.
    ///
    /// Not every authorization is readable the instant the process starts.
    /// `CBManager.authorization` reports `.notDetermined` until a central
    /// manager exists, and the calendar and location statuses settle the same
    /// way, so the first read after launch says a permission is missing that
    /// has in fact been granted for months. Deciding from that read put a
    /// window on screen listing four permissions, every one of them marked
    /// Granted, at every launch.
    ///
    /// The cost of the second read is that a window genuinely needed appears a
    /// second and a half later than it would have.
    func showIfNeeded() {
        model.refresh()
        guard !model.missing.isEmpty else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self else { return }
            self.model.refresh()
            guard !self.model.missing.isEmpty else { return }
            self.show()
        }
    }

    func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 320),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered, defer: false)
        // No title text over a pane that already says what it is at the top,
        // which is how System Settings and every macOS onboarding sheet does it.
        window.title = "Stege Permissions"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false

        let hosting = NSHostingView(
            rootView: PermissionsView(model: model) { [weak self] in
                self?.window?.close()
            })
        window.contentView = hosting
        // Sized to what the list actually needs. The fixed 320 points left a
        // band of empty window under three rows and clipped the fourth.
        window.setContentSize(hosting.fittingSize)
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
