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

    var body: some View {
        ZStack(alignment: .trailing) {
            if let song = playingManager.nowPlaying {
                // Hidden view for measuring the intrinsic width.
                MeasurableNowPlayingContent(song: song) { measuredWidth in
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
                VisibleNowPlayingContent(song: song, width: animatedWidth)
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
        }
    }

    /// A player is running and Stege cannot read what it is playing.
    ///
    /// Drawn rather than left blank. Nothing playing and cannot see what is
    /// playing looked identical from the bar, which is the worst way to report
    /// a permission that was never granted: the widget simply is not there and
    /// there is nothing to click to find out why.
    ///
    /// It is the same shape as any other mark in the bar rather than the
    /// capsule a playing track gets, because there is nothing to put in a
    /// capsule.
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

/// A view that composes the album art and song text into a capsule-shaped content view.
struct NowPlayingContent: View {
    let song: NowPlayingSong
    @ObservedObject var configManager = ConfigManager.shared
    var foregroundHeight: CGFloat { configManager.config.experimental.foreground.resolveHeight() }
    
    var body: some View {
        Group {
            if foregroundHeight < 38 {
                HStack(spacing: 8) {
                    AlbumArtView(song: song)
                    SongTextView(song: song)
                }
            } else {
                HStack(spacing: 8) {
                    AlbumArtView(song: song)
                    SongTextView(song: song)
                }
                .padding(.horizontal, foregroundHeight < 45 ? 8 : 12)
                .frame(height: foregroundHeight < 45 ? 30 : 38)
                .background(configManager.config.experimental.foreground.widgetsBackground.blur)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(Color("NoActive"), lineWidth: 1)
                )
            }
        }
        .foregroundColor(Color("Foreground"))
    }
}

// MARK: - Measurable Now Playing Content

/// A wrapper view that measures the intrinsic width of the now playing content.
struct MeasurableNowPlayingContent: View {
    let song: NowPlayingSong
    let onSizeChange: (CGFloat) -> Void

    var body: some View {
        NowPlayingContent(song: song)
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
    let width: CGFloat

    var body: some View {
        NowPlayingContent(song: song)
            .frame(width: width, height: 38)
            .animation(.smooth(duration: 0.1), value: song)
            .transition(.blurReplace)
    }
}

// MARK: - Album Art View

/// A view that displays the album art with a fade animation and a pause indicator if needed.
struct AlbumArtView: View {
    let song: NowPlayingSong

    var body: some View {
        ZStack {
            FadeAnimatedCachedImage(
                url: song.albumArtURL,
                image: song.artwork,
                targetSize: CGSize(width: 20, height: 20)
            )
            .frame(width: 20, height: 20)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .scaleEffect(song.state == .paused ? 0.9 : 1)
            .brightness(song.state == .paused ? -0.3 : 0)

            if song.state == .paused {
                Image(systemName: "pause.fill")
                    .foregroundColor(Color("Icon"))
                    .transition(.blurReplace)
            }
        }
        .animation(.smooth(duration: 0.1), value: song.state == .paused)
    }
}

// MARK: - Song Text View

/// A view that displays the song title and artist.
struct SongTextView: View {
    let song: NowPlayingSong
    @ObservedObject var configManager = ConfigManager.shared
    var foregroundHeight: CGFloat { configManager.config.experimental.foreground.resolveHeight() }

    var body: some View {

        VStack(alignment: .leading, spacing: -1) {
            if foregroundHeight >= 30 {
                Text(song.title)
                    .font(.system(size: 11))
                    .fontWeight(.medium)
                    .padding(.trailing, 2)
                Text(song.artist)
                    .opacity(0.8)
                    .font(.system(size: 10))
                    .padding(.trailing, 2)
            } else {
                Text(song.artist + " — " + song.title)
                    .font(.system(size: 12))
            }
        }
        // Disable animations for text changes.
        .transaction { transaction in
            transaction.animation = nil
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
