import SwiftUI

/// The artwork of whatever is playing.
///
/// Lived in the now playing bar widget until that widget was removed. The
/// sound popup is the only thing that draws it now, but it stays here with the
/// rest of the now playing code rather than moving in with the volume slider.
struct AlbumArtView: View {
    let song: NowPlayingSong
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
                .stroke(BarStyle.ink.opacity(0.18), lineWidth: 0.5)
        }
    }
}
