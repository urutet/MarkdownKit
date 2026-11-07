import SwiftUI
import CoreGraphics

/// Render-ready document: everything expensive (attributed strings, table layout, highlighting,
/// math rasterization) is already computed, off the main thread.
struct PreparedDocument: Sendable, Equatable {
    var blocks: [PreparedBlock]
    /// Identity of the source + theme, for cheap equality.
    var key: Int

    static func == (lhs: PreparedDocument, rhs: PreparedDocument) -> Bool {
        lhs.key == rhs.key && lhs.blocks == rhs.blocks
    }

    static let empty = PreparedDocument(blocks: [], key: 0)
}

struct PreparedBlock: Identifiable, Sendable, Equatable {
    /// Position of the block in its container. Stable while streaming, so SwiftUI updates the
    /// growing last block in place instead of recreating it.
    let id: Int
    /// Hash of the block content and theme. Equal keys mean an identical rendering.
    let key: Int
    let content: PreparedContent
    /// Extra space above the block (headings), in points.
    let spacingBefore: CGFloat

    static func == (lhs: PreparedBlock, rhs: PreparedBlock) -> Bool {
        lhs.id == rhs.id && lhs.key == rhs.key
    }
}

indirect enum PreparedContent: Sendable {
    case text(PreparedText, TextRole)
    case blockquote([PreparedBlock])
    case list(PreparedList)
    case table(TableLayout)
    case math(PreparedMath)
    case image(PreparedImage)
    case thematicBreak
}

enum TextRole: Sendable, Equatable {
    case paragraph
    case heading(Int)
    case html
}

/// Inline content of a text block.
struct PreparedText: Sendable {
    var segments: [InlineSegment]
    var plainText: String
    var lineSpacing: CGFloat
    /// Font size the text is set in; attachments size relative to it.
    var fontSize: CGFloat

    var hasAttachments: Bool {
        segments.contains { if case .text = $0 { return false }; return true }
    }

    var imageURLs: [URL] {
        segments.compactMap { if case .image(let image) = $0 { return image.url }; return nil }
    }

    var emojiNames: [String] {
        segments.compactMap { if case .emoji(let emoji) = $0 { return emoji.name }; return nil }
    }
}

enum InlineSegment: Sendable {
    case text(AttributedString)
    case math(PreparedMath)
    case image(InlineImage)
    case emoji(InlineEmoji)
}

struct InlineImage: Sendable, Hashable {
    var url: URL?
    var alt: String
    /// Height of the attachment in points (font-relative).
    var height: CGFloat
    var fallback: AttributedString
}

struct InlineEmoji: Sendable, Hashable {
    var name: String
    var size: CGFloat
    var fallback: AttributedString
}

struct PreparedList: Sendable {
    var items: [PreparedListItem]
    var markerWidth: CGFloat
    var markerSpacing: CGFloat
    var itemSpacing: CGFloat
}

struct PreparedListItem: Sendable, Identifiable {
    var id: Int
    var marker: ListMarker
    var blocks: [PreparedBlock]
}

enum ListMarker: Sendable {
    case text(AttributedString)
    case checkbox(Bool, size: CGFloat, color: Color.Resolved)
}

struct PreparedImage: Sendable, Hashable {
    var url: URL?
    var alt: String
    var title: String?
}

/// A CGImage that can cross concurrency domains (immutable once created).
struct SendableImage: @unchecked Sendable, Hashable {
    let cgImage: CGImage
    let scale: CGFloat

    var size: CGSize {
        CGSize(width: CGFloat(cgImage.width) / scale, height: CGFloat(cgImage.height) / scale)
    }

    static func == (lhs: SendableImage, rhs: SendableImage) -> Bool { lhs.cgImage === rhs.cgImage }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(cgImage)) }
}

struct PreparedMath: Sendable {
    var latex: String
    var isDisplay: Bool
    var image: SendableImage?
    /// Distance from the baseline to the bottom of the image.
    var descent: CGFloat
    /// Shown when the formula fails to render.
    var fallback: AttributedString
}
