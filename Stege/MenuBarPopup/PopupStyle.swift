import SwiftUI

/// The shape every popup in the bar shares.
///
/// Each popup used to set its own width, padding and row spacing, so opening
/// two next to each other showed two different panels: 240 points here, 280
/// there, 10 points of padding in one and 14 in the next, and rows that gave no
/// sign they could be clicked. These are the numbers they now all use.
enum PopupStyle {
    /// Wide enough for a network name or a device name next to its trailing
    /// control, and narrow enough that a popup opened at the edge of the
    /// screen still fits.
    static let width: CGFloat = 260
    /// Wider, for the popups laying out a slider and a label on one line.
    static let wideWidth: CGFloat = 280
    static let padding: CGFloat = 14
    /// Between the sections of a popup, not between the rows of one section.
    static let spacing: CGFloat = 12
    /// Between rows inside a section, which sit closer together than sections.
    static let rowSpacing: CGFloat = 2
    static let rowRadius: CGFloat = 6

    static let titleSize: CGFloat = 13
    static let bodySize: CGFloat = 12
    static let captionSize: CGFloat = 11
    /// Every row's leading icon is laid out in the same column, so the labels
    /// line up whether or not a given row has one.
    static let iconColumn: CGFloat = 16
}

extension View {
    /// The outer frame of a popup: one fixed width, one padding.
    ///
    /// Fixed, not a minimum. `Divider` reports an ideal width of infinity, so
    /// under `minWidth` it stretches the popup to the width of the
    /// screen-sized panel behind it and pushes the leading text off the
    /// display.
    func popupContainer(wide: Bool = false) -> some View {
        self
            .padding(PopupStyle.padding)
            .frame(
                width: wide ? PopupStyle.wideWidth : PopupStyle.width,
                alignment: .leading)
    }

    /// A row that can be clicked, highlighted while the pointer is over it.
    ///
    /// The highlight is the whole point: without it nothing in these popups
    /// looked like it did anything, which is the opposite of the menus they
    /// replace.
    func popupRow(action: @escaping () -> Void) -> some View {
        modifier(PopupRow(action: action))
    }

    /// The same padding and shape as a clickable row, for rows that only
    /// report something, so a list of both keeps one rhythm.
    func popupStaticRow() -> some View {
        self
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct PopupRow: ViewModifier {
    let action: () -> Void
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: PopupStyle.rowRadius)
                    .fill(.primary.opacity(isHovered ? 0.09 : 0))
            )
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .onTapGesture(perform: action)
    }
}

/// A popup's title line: a symbol, a name, and whatever control belongs on the
/// right, such as a power switch.
struct PopupHeader<Trailing: View>: View {
    let symbol: String
    let title: String
    var tint: Color = .primary
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: PopupStyle.titleSize))
                .foregroundStyle(tint)
                .frame(width: 18)
            Text(title)
                .font(.system(size: PopupStyle.titleSize, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            trailing
        }
    }
}

extension PopupHeader where Trailing == EmptyView {
    init(symbol: String, title: String, tint: Color = .primary) {
        self.init(symbol: symbol, title: title, tint: tint) { EmptyView() }
    }
}

/// The small heading over a list, such as "Other Networks".
struct PopupSectionTitle<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: PopupStyle.captionSize, weight: .semibold))
                .opacity(0.6)
            Spacer(minLength: 8)
            trailing
        }
    }
}

extension PopupSectionTitle where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title: title) { EmptyView() }
    }
}

/// The row at the foot of a popup that hands off to System Settings.
struct PopupSettingsRow: View {
    let title: String
    var symbol: String = "gearshape"
    let action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: PopupStyle.captionSize))
                .frame(width: PopupStyle.iconColumn)
            Text(title).font(.system(size: PopupStyle.bodySize))
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .opacity(0.5)
        }
        .popupRow(action: action)
    }
}

/// Opens a System Settings pane and closes the popup, which is what every
/// hand-off row in the bar wants.
func openSettings(_ target: String) {
    guard let url = URL(string: target) else { return }
    MenuBarPopup.hide()
    NSWorkspace.shared.open(url)
}
