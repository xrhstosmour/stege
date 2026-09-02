import SwiftUI

// MARK: - Now Playing Widget

struct NowPlayingWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    @ObservedObject var playingManager = NowPlayingManager.shared

    @State private var widgetFrame: CGRect = .zero
    @State private var animatedWidth: CGFloat = 0

    /// Album artwork is fetched from the player's servers when the system
    /// does not hand it over directly. The only outbound request Stege makes,
    /// so it is worth being able to say no.
    var fetchesArtwork: Bool {
        configProvider.config["fetch-artwork"]?.boolValue ?? true
    }

    /// The album art in the bar, at the size every other mark is drawn at. Off
    /// leaves a music note, which is the whole item macOS shows for its own
    /// now playing status item.
    var showsArtwork: Bool {
        configProvider.config["show-artwork"]?.boolValue ?? true
    }
    /// The track title beside it. Off leaves the mark alone and puts
    /// everything in the popup, which is the sparser and more system-like of
    /// the two.
    var showsTitle: Bool {
        configProvider.config["show-title"]?.boolValue ?? true
    }
    /// How much of the row a long title may take before it is cut. A title is
    /// the one thing in this bar with no natural length.
    var titleWidth: CGFloat {
        CGFloat(configProvider.config["title-width"]?.intValue ?? 130)
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            if let song = playingManager.nowPlaying {
                // Hidden view for measuring the intrinsic width.
                MeasurableNowPlayingContent(song: song, style: style) {
                    measuredWidth in
                    if animatedWidth == 0 {
                        animatedWidth = measuredWidth
                    } else if animatedWidth != measuredWidth {
                        withAnimation(.smooth) {
                            animatedWidth = measuredWidth
                        }
                    }
                }
                .hidden()

                // Visible content with fixed animated width.
                VisibleNowPlayingContent(
                    song: song, style: style, width: animatedWidth
                )
                    .onTapGesture {
                        MenuBarPopup.show(rect: widgetFrame, id: "nowplaying") {
                            NowPlayingPopup(configProvider: configProvider)
                        }
                    }
            } else if let failure = playingManager.failure {
                unreachable(failure)
            }
        }
        .background(
            GeometryReader { geometry in
                Color.clear
                    .onAppear {
                        widgetFrame = geometry.frame(in: .global)
                    }
                    .onChange(of: geometry.frame(in: .global)) { _, newFrame in
                        widgetFrame = newFrame
                    }
            }
        )
        .onAppear {
            playingManager.fetchesArtwork = fetchesArtwork
            playingManager.startWatching()
        }
        .onDisappear { playingManager.stopWatching() }
    }

    private var style: NowPlayingStyle {
        NowPlayingStyle(
            showsArtwork: showsArtwork, showsTitle: showsTitle,
            titleWidth: titleWidth)
    }

    /// A player is running and Stege cannot read what it is playing.
    ///
    /// Drawn rather than left blank. Nothing playing and cannot see what is
    /// playing looked identical from the bar, which is the worst way to report
    /// a permission that was never granted: the widget simply is not there and
    /// there is nothing to click to find out why.
    private func unreachable(_ reason: String) -> some View {
        Image(systemName: "music.note")
            .barGlyphBox()
            .opacity(0.6)
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: BarStyle.badgeSize))
                    .foregroundStyle(.orange)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .background(.black.opacity(0.001))
            .help(reason)
            .onTapGesture {
                openSettings(
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
                )
            }
    }
}

// MARK: - Now Playing Content

/// What the widget draws in the bar, and how much of it.
struct NowPlayingStyle: Equatable {
    let showsArtwork: Bool
    let showsTitle: Bool
    let titleWidth: CGFloat
}

/// The track, drawn as one more mark in the row.
///
/// This used to be a capsule: a bordered, blurred pill holding twenty point
/// artwork and two stacked lines of text at eleven and ten points. Next to a
/// row of thirteen point single-weight glyphs it read as a separate control
/// that had been dropped into the bar, which is exactly what the rest of
/// `BarStyle` exists to stop.
///
/// macOS shows one mark for now playing and keeps the artwork, the title, the
/// artist and the transport in the panel behind it. This keeps the title,
/// because a bar wide enough to spare the room is more useful with it, but
/// everything else follows the row: no pill, one line, one size, one colour,
/// and the whole thing dimmed while playback is paused.
struct NowPlayingContent: View {
    let song: NowPlayingSong
    let style: NowPlayingStyle

    var body: some View {
        HStack(spacing: 6) {
            if style.showsArtwork {
                AlbumArtView(song: song)
            } else {
                Image(
                    systemName: song.state == .paused
                        ? "pause.fill" : "music.note"
                )
                .barGlyphBox()
            }

            if style.showsTitle {
                Text(song.title)
                    .font(BarStyle.labelFont)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: style.titleWidth, alignment: .leading)
            }
        }
        // Paused is said by dimming the whole item rather than by a badge, the
        // way a disabled control is said everywhere else in macOS.
        .opacity(song.state == .paused ? 0.55 : 1)
        .foregroundStyle(Color("Foreground Outside"))
        .frame(maxHeight: .infinity)
        .help("\(song.title) — \(song.artist)")
    }
}

// MARK: - Measurable Now Playing Content

/// A wrapper view that measures the intrinsic width of the now playing content.
struct MeasurableNowPlayingContent: View {
    let song: NowPlayingSong
    let style: NowPlayingStyle
    let onSizeChange: (CGFloat) -> Void

    var body: some View {
        NowPlayingContent(song: song, style: style)
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .onAppear {
                            onSizeChange(geometry.size.width)
                        }
                        .onChange(of: geometry.size.width) { _, newWidth in
                            onSizeChange(newWidth)
                        }
                }
            )
    }
}

// MARK: - Visible Now Playing Content

/// A view that displays now playing content with a fixed, animated width and transition.
struct VisibleNowPlayingContent: View {
    let song: NowPlayingSong
    let style: NowPlayingStyle
    let width: CGFloat

    var body: some View {
        NowPlayingContent(song: song, style: style)
            .frame(width: width)
            .frame(maxHeight: .infinity)
            // Keyed on what is drawn, not on the whole song. A song carries
            // its own playback position, which moves every second, so
            // animating on the song ran a tenth of a second of animation over
            // the whole item once a second, for ever, while nothing about it
            // had changed.
            .animation(.smooth(duration: 0.1), value: song.id)
            .animation(.smooth(duration: 0.1), value: song.state)
            .transition(.blurReplace)
    }
}

// MARK: - Album Art View

/// A view that displays the album art with a fade animation and a pause indicator if needed.
struct AlbumArtView: View {
    let song: NowPlayingSong
    /// The size of a glyph, so the artwork sits on the row's own baseline
    /// rather than standing a third taller than the marks beside it.
    var side: CGFloat = 15

    var body: some View {
        FadeAnimatedCachedImage(
            url: song.albumArtURL,
            image: song.artwork,
            targetSize: CGSize(width: side * 2, height: side * 2)
        )
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .stroke(.white.opacity(0.15), lineWidth: 0.5)
        }
    }
}

// MARK: - Preview

struct NowPlayingWidget_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            NowPlayingWidget()
        }
        .frame(width: 500, height: 100)
    }
}
