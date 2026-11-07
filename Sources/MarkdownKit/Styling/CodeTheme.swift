import SwiftUI

/// Kinds of tokens produced by the syntax highlighter.
public enum CodeTokenKind: UInt8, Hashable, Sendable, CaseIterable {
    case plain
    case keyword
    case type
    case string
    case number
    case comment
    case function
    case attribute
    case property
    case `operator`
    case punctuation
    case literal
    case tag
    case variable
    case preprocessor
    case regex
}

/// Colors for syntax-highlighted code.
public struct CodeTheme: Hashable, Sendable {
    public var name: String
    public var plain: Color
    public var keyword: Color
    public var type: Color
    public var string: Color
    public var number: Color
    public var comment: Color
    public var function: Color
    public var attribute: Color
    public var property: Color
    public var `operator`: Color
    public var punctuation: Color
    public var literal: Color
    public var tag: Color
    public var variable: Color
    public var preprocessor: Color
    public var regex: Color
    /// Overrides the code block background when set.
    public var background: Color?
    /// Bold keywords.
    public var boldKeywords: Bool

    public init(name: String, plain: Color, keyword: Color, type: Color, string: Color, number: Color,
                comment: Color, function: Color, attribute: Color, property: Color? = nil,
                operator: Color? = nil, punctuation: Color? = nil, literal: Color? = nil, tag: Color? = nil,
                variable: Color? = nil, preprocessor: Color? = nil, regex: Color? = nil,
                background: Color? = nil, boldKeywords: Bool = false) {
        self.name = name
        self.plain = plain
        self.keyword = keyword
        self.type = type
        self.string = string
        self.number = number
        self.comment = comment
        self.function = function
        self.attribute = attribute
        self.property = property ?? function
        self.operator = `operator` ?? plain
        self.punctuation = punctuation ?? plain
        self.literal = literal ?? keyword
        self.tag = tag ?? keyword
        self.variable = variable ?? plain
        self.preprocessor = preprocessor ?? attribute
        self.regex = regex ?? string
        self.background = background
        self.boldKeywords = boldKeywords
    }

    public func color(for kind: CodeTokenKind) -> Color {
        switch kind {
        case .plain: plain
        case .keyword: keyword
        case .type: type
        case .string: string
        case .number: number
        case .comment: comment
        case .function: function
        case .attribute: attribute
        case .property: property
        case .operator: `operator`
        case .punctuation: punctuation
        case .literal: literal
        case .tag: tag
        case .variable: variable
        case .preprocessor: preprocessor
        case .regex: regex
        }
    }

    private static func d(_ light: UInt32, _ dark: UInt32) -> Color {
        .dynamic(light: Color(hex: light), dark: Color(hex: dark))
    }

    /// Xcode default colors, adapting to light and dark appearance.
    public static let xcode = CodeTheme(
        name: "Xcode",
        plain: d(0x1F1F24, 0xDFDFE0),
        keyword: d(0x9B2393, 0xFF7AB2),
        type: d(0x0B4F79, 0x6BDFFF),
        string: d(0xC41A16, 0xFF8170),
        number: d(0x1C00CF, 0xD9C97C),
        comment: d(0x5D6C79, 0x7F8C98),
        function: d(0x326D74, 0x67B7A4),
        attribute: d(0x815F03, 0xCC9768),
        property: d(0x326D74, 0x4EB0CC),
        literal: d(0x9B2393, 0xFF7AB2),
        tag: d(0x9B2393, 0xFF7AB2),
        preprocessor: d(0x643820, 0xFD8F3F),
        boldKeywords: true
    )

    /// GitHub colors, adapting to light and dark appearance.
    public static let github = CodeTheme(
        name: "GitHub",
        plain: d(0x24292F, 0xC9D1D9),
        keyword: d(0xCF222E, 0xFF7B72),
        type: d(0x953800, 0xFFA657),
        string: d(0x0A3069, 0xA5D6FF),
        number: d(0x0550AE, 0x79C0FF),
        comment: d(0x6E7781, 0x8B949E),
        function: d(0x8250DF, 0xD2A8FF),
        attribute: d(0x0550AE, 0x79C0FF),
        property: d(0x0550AE, 0x79C0FF),
        literal: d(0x0550AE, 0x79C0FF),
        tag: d(0x116329, 0x7EE787),
        variable: d(0x953800, 0xFFA657)
    )

    /// Monokai (dark).
    public static let monokai = CodeTheme(
        name: "Monokai",
        plain: Color(hex: 0xF8F8F2),
        keyword: Color(hex: 0xF92672),
        type: Color(hex: 0x66D9EF),
        string: Color(hex: 0xE6DB74),
        number: Color(hex: 0xAE81FF),
        comment: Color(hex: 0x75715E),
        function: Color(hex: 0xA6E22E),
        attribute: Color(hex: 0xA6E22E),
        literal: Color(hex: 0xAE81FF),
        tag: Color(hex: 0xF92672),
        variable: Color(hex: 0xFD971F),
        background: Color(hex: 0x272822)
    )

    /// Dracula (dark).
    public static let dracula = CodeTheme(
        name: "Dracula",
        plain: Color(hex: 0xF8F8F2),
        keyword: Color(hex: 0xFF79C6),
        type: Color(hex: 0x8BE9FD),
        string: Color(hex: 0xF1FA8C),
        number: Color(hex: 0xBD93F9),
        comment: Color(hex: 0x6272A4),
        function: Color(hex: 0x50FA7B),
        attribute: Color(hex: 0x50FA7B),
        literal: Color(hex: 0xBD93F9),
        tag: Color(hex: 0xFF79C6),
        variable: Color(hex: 0xFFB86C),
        background: Color(hex: 0x282A36)
    )

    /// Solarized, adapting to light and dark appearance.
    public static let solarized = CodeTheme(
        name: "Solarized",
        plain: d(0x586E75, 0x93A1A1),
        keyword: d(0x859900, 0x859900),
        type: d(0xB58900, 0xB58900),
        string: d(0x2AA198, 0x2AA198),
        number: d(0xD33682, 0xD33682),
        comment: d(0x93A1A1, 0x586E75),
        function: d(0x268BD2, 0x268BD2),
        attribute: d(0xCB4B16, 0xCB4B16),
        literal: d(0x6C71C4, 0x6C71C4),
        background: d(0xFDF6E3, 0x002B36)
    )

    public static let allBuiltIn: [CodeTheme] = [.xcode, .github, .monokai, .dracula, .solarized]
}
