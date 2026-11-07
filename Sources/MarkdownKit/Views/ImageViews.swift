import SwiftUI

/// Plays an animated image with a `TimelineView`, pausing when off screen, in the background, with
/// Reduce Motion, or when animations are disabled.
struct AnimatedImageView: View {
    let animation: AnimatedImage

    @State private var isVisible = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.markdownAnimatesImages) private var animates
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let paused = !animates || reduceMotion || !isVisible || scenePhase == .background
        TimelineView(.animation(minimumInterval: max(animation.minimumDelay, 1.0 / 60), paused: paused)) { context in
            let time = paused ? 0 : context.date.timeIntervalSinceReferenceDate
            Image(decorative: animation.frame(at: time), scale: displayScale)
                .resizable()
        }
        .onScrollVisibilityChange(threshold: 0.01) { isVisible = $0 }
    }
}

/// Block-level image (a paragraph containing only an image).
struct BlockImageView: View {
    let image: PreparedImage
    let theme: ResolvedTheme

    @Environment(\.markdownImageLoader) private var loader
    @Environment(\.displayScale) private var displayScale
    @State private var loaded: MarkdownImage?
    @State private var failed = false

    private static let maxPixelSize: CGFloat = 1600

    var body: some View {
        let style = theme.theme.image
        let radius = theme.length(style.cornerRadius)
        let maxHeight = theme.length(style.maxHeight)
        let current = loaded ?? image.url.flatMap { loader.cachedImage(for: $0, maxPixelSize: Self.maxPixelSize) }

        Group {
            if let current {
                let size = current.pixelSize
                let pointSize = CGSize(width: size.width / displayScale, height: size.height / displayScale)
                imageContent(current)
                    .aspectRatio(size, contentMode: .fit)
                    .frame(maxWidth: max(pointSize.width, 1), maxHeight: maxHeight, alignment: .leading)
            } else if failed {
                Label(image.alt.isEmpty ? "Image unavailable" : image.alt, systemImage: "photo")
                    .foregroundStyle(Color(theme.secondaryColor))
                    .font(.system(size: theme.baseSize * 0.9))
            } else {
                placeholder(maxHeight: maxHeight, radius: radius)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel(image.alt.isEmpty ? "Image" : image.alt)
        .accessibilityAddTraits(.isImage)
        .task(id: image.url) {
            guard current == nil, let url = image.url else {
                if image.url == nil { failed = true }
                return
            }
            do {
                loaded = try await loader.loadImage(from: url, maxPixelSize: Self.maxPixelSize)
            } catch {
                failed = true
            }
        }
    }

    @ViewBuilder private func imageContent(_ image: MarkdownImage) -> some View {
        switch image.content {
        case .still(let still):
            Image(decorative: still.cgImage, scale: displayScale).resizable()
        case .animated(let animation):
            AnimatedImageView(animation: animation)
        }
    }

    @ViewBuilder private func placeholder(maxHeight: CGFloat, radius: CGFloat) -> some View {
        let color = Color(theme.imagePlaceholder)
        if let url = image.url, let known = loader.knownPixelSize(for: url) {
            color.aspectRatio(known, contentMode: .fit)
                .frame(maxWidth: known.width / displayScale, maxHeight: maxHeight, alignment: .leading)
        } else {
            color.frame(height: theme.length(theme.theme.image.placeholderHeight))
                .overlay { ProgressView() }
        }
    }
}
