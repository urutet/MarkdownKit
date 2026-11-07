import SwiftUI

/// Paragraphs, headings and other inline-content blocks: a single `Text` per block.
struct TextBlockView: View {
    let text: PreparedText
    let role: TextRole
    let theme: ResolvedTheme

    var body: some View {
        let view = InlineTextView(text: text, theme: theme)
            .lineSpacing(text.lineSpacing)
            .tint(Color(theme.linkColor))
        switch role {
        case .heading(let level):
            VStack(alignment: .leading, spacing: theme.length(.em(0.3))) {
                view.accessibilityAddTraits(.isHeader)
                    .accessibilityHeading(Self.headingLevel(level))
                if theme.theme.heading(level).divider {
                    Rectangle().fill(Color(theme.ruleColor)).frame(height: 1)
                }
            }
            .padding(.bottom, theme.length(theme.theme.heading(level).spacingAfter))
        case .paragraph, .html:
            view
        }
    }

    static func headingLevel(_ level: Int) -> AccessibilityHeadingLevel {
        switch level {
        case 1: .h1
        case 2: .h2
        case 3: .h3
        case 4: .h4
        case 5: .h5
        default: .h6
        }
    }
}

/// Composes inline segments (attributed text and attachments) into one `Text`.
struct InlineTextView: View {
    let text: PreparedText
    let theme: ResolvedTheme

    var body: some View {
        Self.compose(text.segments) { segment in
            switch segment {
            case .text(let string):
                return Text(string)
            case .math(let math):
                return InlineAttachments.math(math)
            case .image(let image):
                return Text(image.fallback)
            case .emoji(let emoji):
                return Text(emoji.fallback)
            }
        }
    }

    static func compose(_ segments: [InlineSegment], _ transform: (InlineSegment) -> Text) -> Text {
        switch segments.count {
        case 0: return Text(verbatim: "")
        case 1: return transform(segments[0])
        default:
            var result = transform(segments[0])
            for segment in segments.dropFirst() {
                let next = transform(segment)
                result = Text("\(result)\(next)")
            }
            return result
        }
    }
}

enum InlineAttachments {
    static func math(_ math: PreparedMath) -> Text {
        guard let image = math.image else { return Text(math.fallback) }
        return Text(Image(decorative: image.cgImage, scale: image.scale))
            .baselineOffset(-math.descent)
            .accessibilityLabel(math.latex)
    }
}

/// Block-level image (a paragraph that contains only an image).
struct BlockImageView: View {
    let image: PreparedImage
    let theme: ResolvedTheme

    var body: some View {
        RoundedRectangle(cornerRadius: theme.length(theme.theme.image.cornerRadius))
            .fill(Color(theme.imagePlaceholder))
            .frame(height: theme.length(theme.theme.image.placeholderHeight))
            .overlay { Text(image.alt).foregroundStyle(.secondary) }
            .accessibilityLabel(image.alt)
    }
}
