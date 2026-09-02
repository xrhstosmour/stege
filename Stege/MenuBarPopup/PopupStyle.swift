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
    static let width: CGFloat = 280
    /// Kept so the call sites still read, but the same as `width` now. Two
    /// widths meant opening the sound popup and then the Wi-Fi one visibly
    /// The margin the rows are inset from, which their highlight bleeds to.
    /// macOS menus keep this tight and put the air inside the rows instead.
    static let padding: CGFloat = 6
    /// Between the sections of a popup, not between the rows of one section.
    static let spacing: CGFloat = 8
    /// Between rows inside a section, which sit closer together than sections.
    static let rowSpacing: CGFloat = 1
    static let rowRadius: CGFloat = 5

    /// Inside a row. Five points above and below a twelve point line gives the
    /// twenty two point row macOS uses, which is a lot more air than the four
    /// this had.
    static let rowHorizontalPadding: CGFloat = 8
    static let rowVerticalPadding: CGFloat = 5

    /// The corner radius of the popup pane. macOS menus round to about this
    /// much.
    static let cornerRadius: CGFloat = 13

    static let bodySize: CGFloat = 12
    static let captionSize: CGFloat = 11
    /// Every row's leading icon is laid out in the same column, so the labels
    /// line up whether or not a given row has one.
    static let iconColumn: CGFloat = 16
}

/// The pane every popup is drawn on.
///
/// Solid black, the same as the bar it hangs from. This was briefly a blurred,
/// gradient-lit surface in the Dock's style, and against a bar that is flat
/// black the two read as two different materials rather than one control.
///
/// What it does keep from that attempt is the corner radius. The popup used to
/// round at 40 points on a pane 260 wide, so the curve ate most of the top and
/// bottom edges.
struct PopupSurface: View {
    var cornerRadius: CGFloat = PopupStyle.cornerRadius

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.black)
    }
}

extension View {
    /// The outer frame of a popup: one fixed width, one padding.
    ///
    /// Fixed, not a minimum. `Divider` reports an ideal width of infinity, so
    /// under `minWidth` it stretches the popup to the width of the
    /// screen-sized panel behind it and pushes the leading text off the
    /// display.
    func popupContainer() -> some View {
        self
            .padding(PopupStyle.padding)
            .frame(width: PopupStyle.width, alignment: .leading)
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
            .padding(.horizontal, PopupStyle.rowHorizontalPadding)
            .padding(.vertical, PopupStyle.rowVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The line between two sections of a popup.
///
/// Not `Divider`, for two reasons. It reports an ideal width of infinity, which
/// is what forced every popup to a fixed width in the first place. And macOS
/// insets its menu separators from the menu's edges rather than running them
/// wall to wall.
struct PopupSeparator: View {
    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.12))
            .frame(height: 1)
            .padding(.horizontal, PopupStyle.rowHorizontalPadding)
            .padding(.vertical, 2)
    }
}

private struct PopupRow: ViewModifier {
    let action: () -> Void
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, PopupStyle.rowHorizontalPadding)
            .padding(.vertical, PopupStyle.rowVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            // The accent colour, not a wash of white. A menu row under the
            // pointer in macOS is selected, and says so in the colour the user
            // picked; nine percent white read as a hint that something might
            // happen rather than as the selection it is.
            .background(
                RoundedRectangle(
                    cornerRadius: PopupStyle.rowRadius, style: .continuous
                )
                .fill(isHovered ? Color.accentColor : .clear)
            )
            .foregroundStyle(isHovered ? Color.white : Color.primary)
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .onTapGesture(perform: action)
    }
}

/// An on/off switch, drawn rather than taken from `Toggle`.
///
/// `Toggle(.switch)` came out looking like empty space in the Wi-Fi and battery
/// popups. The open and close animation was blamed for it at the time, on the
/// theory that the AppKit-backed switch could not survive being composited
/// through `blur` and `scaleEffect`. That was wrong: a switch drawn under
/// exactly that modifier chain renders fine.
///
/// The real reason is the panel. The bar is a non-activating panel and is
/// almost never the key window, and AppKit draws a switch in its inactive
/// style whenever the window it is in is not key: a dark grey capsule with no
/// accent colour. At `mini` size against a black popup that is very close to
/// nothing at all, and it stays grey even while it is on, so it cannot say
/// which way it is set.
///
/// Shapes carry no such state, so this is built from two of them.
struct PopupSwitch: View {
    let isOn: Bool
    let action: () -> Void

    private let width: CGFloat = 26
    private let height: CGFloat = 15

    var body: some View {
        Capsule()
            .fill(isOn ? Color.accentColor : Color.primary.opacity(0.25))
            .frame(width: width, height: height)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(.white)
                    .padding(1.5)
                    .shadow(radius: 0.5)
            }
            .animation(.smooth(duration: 0.15), value: isOn)
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(isOn ? "on" : "off")
    }
}

/// The row a popup's power switch sits on: what the radio is attached to, and
/// the switch that turns it off.
///
/// This is what is left of the title line every popup used to open with. A
/// popup is opened by clicking the thing it is about, so a first line naming
/// that thing said nothing the click had not already said, and it cost a row
/// of height in every popup to say it. What could not go is the switch, so the
/// switch keeps a row and the text beside it now carries the connection rather
/// than the name.
struct PopupPowerRow<Leading: View, Trailing: View>: View {
    let state: String
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            leading
                .frame(width: PopupStyle.iconColumn)
            Text(state)
                .font(.system(size: PopupStyle.bodySize, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            trailing
        }
        .popupStaticRow()
    }
}

/// A round icon button, for controls that are a symbol and nothing else.
///
/// The transport in the sound popup is three of these in a row, where a
/// labelled row would be three lines for what reads as one control.
struct PopupIconButton: View {
    let symbol: String
    var size: CGFloat = 12
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .medium))
            .frame(width: 24, height: 24)
            .background(
                Circle().fill(isHovered ? Color.accentColor : .clear)
            )
            .foregroundStyle(isHovered ? Color.white : Color.primary)
            .contentShape(Circle())
            .onHover { isHovered = $0 }
            .onTapGesture(perform: action)
            .accessibilityAddTraits(.isButton)
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
