import Foundation

/// What a `:shortcode:` resolves to.
public enum MarkdownEmoji: Sendable, Hashable {
    /// Unicode text (e.g. "🎉").
    case text(String)
    /// A remote or local image (static or animated), loaded with the current ``MarkdownImageLoader``.
    case image(URL)
    /// An SF Symbol.
    case systemImage(String)
}

/// Resolves `:shortcode:` names to emoji. Return `nil` to leave the shortcode as literal text.
public typealias MarkdownEmojiProvider = @Sendable (String) -> MarkdownEmoji?

public enum MarkdownEmojiShortcodes {
    /// A small table of common GitHub/Slack-style shortcodes, used when no provider resolves a name.
    public static let common: [String: String] = [
        "smile": "😄", "smiley": "😃", "grin": "😁", "laughing": "😆", "joy": "😂", "wink": "😉", "blush": "😊",
        "heart_eyes": "😍", "thinking": "🤔", "neutral_face": "😐", "sweat_smile": "😅", "cry": "😢", "sob": "😭",
        "angry": "😠", "scream": "😱", "sunglasses": "😎", "nerd_face": "🤓", "party": "🥳", "partying_face": "🥳",
        "thumbsup": "👍", "+1": "👍", "thumbsdown": "👎", "-1": "👎", "clap": "👏", "wave": "👋", "pray": "🙏",
        "muscle": "💪", "ok_hand": "👌", "point_right": "👉", "raised_hands": "🙌", "eyes": "👀",
        "heart": "❤️", "broken_heart": "💔", "sparkles": "✨", "star": "⭐", "fire": "🔥", "rocket": "🚀",
        "tada": "🎉", "100": "💯", "boom": "💥", "zap": "⚡", "bulb": "💡", "warning": "⚠️", "x": "❌",
        "white_check_mark": "✅", "check": "✔️", "heavy_check_mark": "✔️", "question": "❓", "exclamation": "❗",
        "memo": "📝", "book": "📖", "bug": "🐛", "wrench": "🔧", "hammer": "🔨", "gear": "⚙️", "lock": "🔒",
        "key": "🔑", "chart_with_upwards_trend": "📈", "chart_with_downwards_trend": "📉", "calendar": "📅",
        "hourglass": "⌛", "coffee": "☕", "pizza": "🍕", "computer": "💻", "iphone": "📱", "robot": "🤖",
        "brain": "🧠", "test_tube": "🧪", "package": "📦", "link": "🔗", "pushpin": "📌", "trophy": "🏆",
        "sun": "☀️", "moon": "🌙", "cloud": "☁️", "rainbow": "🌈", "snowflake": "❄️", "earth": "🌍",
    ]
}
