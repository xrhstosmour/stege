import SwiftUI

/// What `default.nowplaying` draws now that there is no now playing widget.
///
/// The identifier is still understood, so a configuration carrying it is not
/// broken and does not get the red marker that a mistyped name gets. It draws
/// a music note that says where the thing went and opens it, because a widget
/// that silently drew nothing would be indistinguishable from one that had
/// failed.
struct NowPlayingMovedMarker: View {
    @ObservedObject private var manager = AudioManager.shared
    @State private var rect: CGRect = .zero

    var body: some View {
        Image(systemName: "music.note")
            .barGlyphBox()
            .opacity(0.5)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .background(.black.opacity(0.001))
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
                MenuBarPopup.show(rect: rect, id: "audio") {
                    AudioPopup(manager: manager, scope: .output)
                }
            }
            .help(
                "What is playing is in the sound popup. Remove "
                    + "\"default.nowplaying\" from widgets.displayed to drop "
                    + "this mark.")
    }
}
