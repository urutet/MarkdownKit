import CoreGraphics

/// A length that is either absolute or relative to the current font size.
///
/// Relative (`em`) lengths scale with the theme's base font size, which itself follows Dynamic Type,
/// so padding, indentation and spacing stay proportional to the text at every accessibility size.
public enum MarkdownLength: Hashable, Sendable {
    /// Multiple of the font size the length is resolved against.
    case em(CGFloat)
    /// Absolute points.
    case pt(CGFloat)

    public static let zero = MarkdownLength.pt(0)

    public func resolve(fontSize: CGFloat) -> CGFloat {
        switch self {
        case .em(let value): value * fontSize
        case .pt(let value): value
        }
    }
}

extension MarkdownLength: ExpressibleByFloatLiteral, ExpressibleByIntegerLiteral {
    /// Literal values are interpreted as points.
    public init(floatLiteral value: Double) { self = .pt(CGFloat(value)) }
    public init(integerLiteral value: Int) { self = .pt(CGFloat(value)) }
}
