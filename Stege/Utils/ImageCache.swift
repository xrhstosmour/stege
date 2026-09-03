import AppKit
import Combine
import SwiftUI

// MARK: - Image Cache

/// A singleton cache for storing downloaded NSImage objects.
final class ImageCache {
    static let shared = NSCache<NSString, NSImage>()
}

// MARK: - Image Loader

/// An observable object that asynchronously downloads and caches images.
final class ImageLoader: ObservableObject {
    @Published var image: NSImage?
    
    private var cancellable: AnyCancellable?
    
    /// The URL of the image to load.
    var url: URL?
    
    /// Optional target size to which the image should be resized.
    var targetSize: CGSize?
    
    /// Initializes the loader with an optional URL and target size.
    /// - Parameters:
    ///   - url: The URL of the image.
    ///   - targetSize: The desired size for the image.
    init(url: URL?, targetSize: CGSize? = nil) {
        self.url = url
        self.targetSize = targetSize
    }
    
    /// Generates a cache key based on the URL and target size.
    private var cacheKey: NSString? {
        guard let url = url else { return nil }
        if let targetSize = targetSize {
            return "\(url.absoluteString)-\(Int(targetSize.width))x\(Int(targetSize.height))" as NSString
        } else {
            return url.absoluteString as NSString
        }
    }
    
    /// Loads the image from the URL, resizing if needed, and caches it.
    func load() {
        // Cancel any ongoing request before starting a new one.
        cancellable?.cancel()
        
        guard let url = url, let key = cacheKey else { return }
        
        // Check for cached image.
        if let cachedImage = ImageCache.shared.object(forKey: key) {
            self.image = cachedImage
            return
        }
        
        // Download image asynchronously.
        //
        // Decoding the bytes is all that happens off the main thread. The
        // resize used to happen here too, and it is `lockFocus` and a `draw`,
        // which is AppKit drawing into an offscreen context: not something to
        // do on `URLSession`'s queue. It is done below instead, after
        // `receive(on:)` has moved to the main thread.
        cancellable = URLSession.shared.dataTaskPublisher(for: url)
            .map { data, _ in NSImage(data: data) }
            .replaceError(with: nil)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] downloadedImage in
                guard let self else { return }
                let sized =
                    self.targetSize
                    .flatMap { downloadedImage?.resized(to: $0) }
                    ?? downloadedImage
                if let sized {
                    ImageCache.shared.setObject(sized, forKey: key)
                }
                self.image = sized
            }
    }
    
    deinit {
        cancellable?.cancel()
    }
}

// MARK: - NSImage Extension

extension NSImage {
    /// Returns a resized version of the image.
    /// - Parameter newSize: The target size.
    /// - Returns: A new NSImage resized to the given dimensions, or nil if resizing fails.
    func resized(to newSize: NSSize) -> NSImage? {
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        let rect = NSRect(origin: .zero, size: newSize)
        self.draw(in: rect, from: NSRect(origin: .zero, size: self.size), operation: .copy, fraction: 1.0)
        newImage.unlockFocus()
        newImage.size = newSize
        return newImage
    }
}

// MARK: - Rotate Animated Cached Image View

/// A view that displays a cached image with a rotation and blur animation when the image changes.
struct RotateAnimatedCachedImage<RotatingContent: View>: View {
    let url: URL?
    let targetSize: CGSize?
    /// Artwork the caller already has. `MediaRemote` returns the bytes rather
    /// than a link, so when this is set the loader is never asked for anything.
    let image: NSImage?
    
    @StateObject private var loader: ImageLoader
    @State private var displayedImage: NSImage?
    @State private var rotation: Double = 1
    let rotatingModifier: (Image) -> RotatingContent
    
    /// Initializes the view with a URL, optional target size, and a custom rotating modifier.
    init(
        url: URL?,
        image: NSImage? = nil,
        targetSize: CGSize? = nil,
        @ViewBuilder rotatingModifier: @escaping (Image) -> RotatingContent
    ) {
        self.url = url
        self.image = image
        self.targetSize = targetSize
        _loader = StateObject(wrappedValue: ImageLoader(url: url, targetSize: targetSize))
        self.rotatingModifier = rotatingModifier
    }
    
    /// Convenience initializer when no custom modifier is needed.
    init(url: URL?, image: NSImage? = nil, targetSize: CGSize? = nil)
    where RotatingContent == Image {
        self.init(url: url, image: image, targetSize: targetSize) { image in
            image
        }
    }
    
    var body: some View {
        Group {
            // What the caller handed over wins. Nothing to fetch, so the loader
            // is never started for it.
            if let image = image ?? displayedImage {
                rotatingModifier(Image(nsImage: image).resizable())
                    .blur(radius: abs(1 - rotation) * 5)
                    .scaleEffect(x: rotation)
            } else {
                Color.clear
            }
        }
        .onAppear { if image == nil { loader.load() } }
        .onReceive(loader.$image) { newImage in
            guard let newImage = newImage else { return }
            // If image is loading for the first time.
            if displayedImage == nil {
                displayedImage = newImage
            } else if displayedImage != newImage {
                // Animate the transition.
                withAnimation(.easeInOut(duration: 0.2)) { rotation = 0 }
                withAnimation(.easeOut(duration: 0.3).delay(0.2)) { rotation = 1 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    displayedImage = newImage
                }
            }
        }
        .onChange(of: url) { _, newURL in
            loader.url = newURL
            loader.load()
        }
    }
}

// MARK: - Fade Animated Cached Image View

/// A view that displays a cached image with a fade transition when the image changes.
struct FadeAnimatedCachedImage<Content: View>: View {
    let url: URL?
    let targetSize: CGSize?
    /// Artwork the caller already has, which wins over the URL.
    let image: NSImage?
    
    @StateObject private var loader: ImageLoader
    @State private var currentImage: NSImage?
    @State private var nextImage: NSImage?
    @State private var showNextImage: Bool = false
    let content: (Image) -> Content
    
    /// Initializes the view with a URL, optional target size, and a custom content modifier.
    init(
        url: URL?,
        image: NSImage? = nil,
        targetSize: CGSize? = nil,
        @ViewBuilder content: @escaping (Image) -> Content
    ) {
        self.url = url
        self.image = image
        self.targetSize = targetSize
        _loader = StateObject(wrappedValue: ImageLoader(url: url, targetSize: targetSize))
        self.content = content
    }
    
    /// Convenience initializer when no custom modifier is needed.
    init(url: URL?, image: NSImage? = nil, targetSize: CGSize? = nil)
    where Content == Image {
        self.init(url: url, image: image, targetSize: targetSize) { image in
            image
        }
    }
    
    var body: some View {
        ZStack {
            if let image {
                content(Image(nsImage: image))
            } else if let currentImage = currentImage {
                content(Image(nsImage: currentImage))
            }
            
            if image == nil, let nextImage = nextImage {
                content(Image(nsImage: nextImage))
                    .opacity(showNextImage ? 1 : 0)
            }
        }
        .onAppear { if image == nil { loader.load() } }
        .onReceive(loader.$image) { newImage in
            guard let newImage = newImage else { return }
            // Set the image for the first time.
            if currentImage == nil {
                currentImage = newImage
            } else if currentImage != newImage {
                // Animate the fade transition.
                nextImage = newImage
                withAnimation(.easeInOut(duration: 0.5)) {
                    showNextImage = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    currentImage = newImage
                    nextImage = nil
                    showNextImage = false
                }
            }
        }
        .onChange(of: url) { _, newURL in
            loader.url = newURL
            loader.load()
        }
    }
}
