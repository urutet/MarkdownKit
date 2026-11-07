import Foundation

/// Lexical description of a programming language for the highlighter.
struct LanguageGrammar: Sendable {
    var name: String
    var aliases: [String]
    var keywords: Set<String> = []
    var types: Set<String> = []
    var literals: Set<String> = []
    var builtins: Set<String> = []
    var lineComments: [String] = []
    var blockComments: [(open: String, close: String)] = []
    /// Single-byte string delimiters, e.g. `"` and `'`.
    var stringDelimiters: [UInt8] = [UInt8(ascii: "\""), UInt8(ascii: "'")]
    /// `"""`-style triple-quoted strings.
    var tripleQuotes = false
    /// Backtick template strings that may span lines (JavaScript).
    var multilineBacktick = false
    /// Identifiers starting with an uppercase letter are types.
    var capitalizedTypes = true
    /// `@name` attributes / decorators / annotations.
    var attributePrefix: UInt8? = nil
    /// `#directive` at line start.
    var preprocessor = false
    /// `$variable`.
    var variablePrefix: UInt8? = nil
    /// Characters (besides alphanumerics and `_`) allowed inside identifiers.
    var identifierExtras: Set<UInt8> = []
    /// Keywords are case-insensitive (SQL).
    var caseInsensitive = false
    var mode: Mode = .code

    enum Mode: Sendable {
        case code
        case markup   // HTML / XML
        case diff
        case json
        case yaml
        case css
    }
}

extension LanguageGrammar {
    static func lookup(_ name: String?) -> LanguageGrammar? {
        guard let name else { return nil }
        let key = name.lowercased().trimmingCharacters(in: .whitespaces)
        return registry[key]
    }

    private static let registry: [String: LanguageGrammar] = {
        var map: [String: LanguageGrammar] = [:]
        for grammar in all {
            map[grammar.name] = grammar
            for alias in grammar.aliases { map[alias] = grammar }
        }
        return map
    }()

    static let cLikeOperators = "+-*/%=<>!&|^~?:"

    static let all: [LanguageGrammar] = [
        swift, python, javascript, typescript, json, kotlin, java, c, cpp, csharp, go, rust, ruby, php,
        shell, sql, html, css, yaml, markdown, diff, objectiveC, dart, scala,
    ]

    static let swift = LanguageGrammar(
        name: "swift", aliases: [],
        keywords: ["associatedtype", "class", "deinit", "enum", "extension", "fileprivate", "func", "import", "init",
                   "inout", "internal", "let", "open", "operator", "private", "protocol", "public", "rethrows", "static",
                   "struct", "subscript", "typealias", "var", "break", "case", "continue", "default", "defer", "do",
                   "else", "fallthrough", "for", "guard", "if", "in", "repeat", "return", "switch", "where", "while",
                   "as", "catch", "is", "super", "self", "Self", "throw", "throws", "try", "async", "await", "actor",
                   "some", "any", "final", "override", "mutating", "nonmutating", "lazy", "weak", "unowned",
                   "convenience", "required", "optional", "indirect", "nonisolated", "isolated", "consuming",
                   "borrowing", "sending", "macro", "package", "get", "set", "willSet", "didSet"],
        types: ["Int", "Double", "Float", "String", "Bool", "Character", "Array", "Dictionary", "Set", "Optional", "Void"],
        literals: ["true", "false", "nil"],
        lineComments: ["//"], blockComments: [("/*", "*/")],
        stringDelimiters: [UInt8(ascii: "\"")], tripleQuotes: true,
        attributePrefix: UInt8(ascii: "@"), preprocessor: true
    )

    static let python = LanguageGrammar(
        name: "python", aliases: ["py", "python3"],
        keywords: ["and", "as", "assert", "async", "await", "break", "class", "continue", "def", "del", "elif", "else",
                   "except", "finally", "for", "from", "global", "if", "import", "in", "is", "lambda", "nonlocal",
                   "not", "or", "pass", "raise", "return", "try", "while", "with", "yield", "match", "case", "self"],
        types: ["int", "float", "str", "bool", "list", "dict", "set", "tuple", "bytes", "object"],
        literals: ["True", "False", "None"],
        builtins: ["print", "len", "range", "enumerate", "zip", "map", "filter", "open", "super", "isinstance"],
        lineComments: ["#"], tripleQuotes: true, attributePrefix: UInt8(ascii: "@")
    )

    static let jsKeywords: Set<String> = [
        "break", "case", "catch", "class", "const", "continue", "debugger", "default", "delete", "do", "else",
        "export", "extends", "finally", "for", "function", "if", "import", "in", "instanceof", "let", "new",
        "return", "super", "switch", "this", "throw", "try", "typeof", "var", "void", "while", "with", "yield",
        "async", "await", "of", "static", "get", "set", "from", "as",
    ]

    static let javascript = LanguageGrammar(
        name: "javascript", aliases: ["js", "jsx", "mjs", "cjs", "node"],
        keywords: jsKeywords,
        literals: ["true", "false", "null", "undefined", "NaN", "Infinity"],
        builtins: ["console", "window", "document", "Math", "JSON", "Promise", "Object", "Array"],
        lineComments: ["//"], blockComments: [("/*", "*/")],
        stringDelimiters: [UInt8(ascii: "\""), UInt8(ascii: "'"), UInt8(ascii: "`")], multilineBacktick: true,
        attributePrefix: UInt8(ascii: "@"), identifierExtras: [UInt8(ascii: "$")]
    )

    static let typescript: LanguageGrammar = {
        var g = javascript
        g.name = "typescript"
        g.aliases = ["ts", "tsx"]
        g.keywords.formUnion(["interface", "type", "enum", "implements", "namespace", "declare", "readonly", "abstract",
                              "private", "public", "protected", "keyof", "infer", "is", "satisfies"])
        g.types = ["string", "number", "boolean", "any", "unknown", "never", "void", "object", "bigint", "symbol"]
        return g
    }()

    static let json = LanguageGrammar(
        name: "json", aliases: ["jsonc", "json5"],
        literals: ["true", "false", "null"],
        lineComments: ["//"], blockComments: [("/*", "*/")],
        stringDelimiters: [UInt8(ascii: "\"")], capitalizedTypes: false, mode: .json
    )

    static let kotlin = LanguageGrammar(
        name: "kotlin", aliases: ["kt", "kts"],
        keywords: ["as", "break", "class", "continue", "do", "else", "for", "fun", "if", "in", "interface", "is",
                   "object", "package", "return", "super", "this", "throw", "try", "typealias", "val", "var", "when",
                   "while", "by", "catch", "constructor", "finally", "get", "import", "init", "set", "where",
                   "abstract", "data", "enum", "final", "inline", "internal", "lateinit", "open", "override",
                   "private", "protected", "public", "sealed", "suspend", "companion", "const"],
        literals: ["true", "false", "null"],
        lineComments: ["//"], blockComments: [("/*", "*/")], tripleQuotes: true, attributePrefix: UInt8(ascii: "@")
    )

    static let java = LanguageGrammar(
        name: "java", aliases: [],
        keywords: ["abstract", "assert", "break", "case", "catch", "class", "const", "continue", "default", "do",
                   "else", "enum", "extends", "final", "finally", "for", "goto", "if", "implements", "import",
                   "instanceof", "interface", "native", "new", "package", "private", "protected", "public", "return",
                   "static", "strictfp", "super", "switch", "synchronized", "this", "throw", "throws", "transient",
                   "try", "volatile", "while", "var", "record", "sealed", "permits", "yield"],
        types: ["int", "long", "short", "byte", "char", "float", "double", "boolean", "void"],
        literals: ["true", "false", "null"],
        lineComments: ["//"], blockComments: [("/*", "*/")], tripleQuotes: true, attributePrefix: UInt8(ascii: "@")
    )

    static let cKeywords: Set<String> = [
        "auto", "break", "case", "const", "continue", "default", "do", "else", "enum", "extern", "for", "goto",
        "if", "inline", "register", "restrict", "return", "sizeof", "static", "struct", "switch", "typedef",
        "union", "volatile", "while",
    ]
    static let cTypes: Set<String> = [
        "int", "long", "short", "char", "float", "double", "void", "signed", "unsigned", "bool", "size_t",
        "uint8_t", "uint16_t", "uint32_t", "uint64_t", "int8_t", "int16_t", "int32_t", "int64_t",
    ]

    static let c = LanguageGrammar(
        name: "c", aliases: ["h"],
        keywords: cKeywords, types: cTypes, literals: ["NULL", "true", "false"],
        lineComments: ["//"], blockComments: [("/*", "*/")], capitalizedTypes: false, preprocessor: true
    )

    static let cpp: LanguageGrammar = {
        var g = c
        g.name = "cpp"
        g.aliases = ["c++", "cc", "cxx", "hpp", "hh"]
        g.keywords.formUnion(["class", "namespace", "template", "typename", "using", "public", "private", "protected",
                              "virtual", "override", "final", "new", "delete", "this", "throw", "try", "catch",
                              "constexpr", "noexcept", "operator", "explicit", "friend", "mutable", "static_cast",
                              "dynamic_cast", "reinterpret_cast", "const_cast", "co_await", "co_return", "concept",
                              "requires", "decltype", "auto"])
        g.types.formUnion(["std", "string", "vector", "map", "unique_ptr", "shared_ptr"])
        g.literals.formUnion(["nullptr"])
        g.capitalizedTypes = true
        return g
    }()

    static let objectiveC: LanguageGrammar = {
        var g = c
        g.name = "objective-c"
        g.aliases = ["objc", "objectivec", "m", "mm"]
        g.keywords.formUnion(["@interface", "@implementation", "@end", "@property", "@synthesize", "@protocol",
                              "self", "super", "nonatomic", "strong", "weak", "copy", "assign", "readonly"])
        g.types.formUnion(["id", "BOOL", "NSInteger", "NSUInteger", "CGFloat", "instancetype"])
        g.literals.formUnion(["YES", "NO", "nil", "Nil"])
        g.capitalizedTypes = true
        g.attributePrefix = UInt8(ascii: "@")
        return g
    }()

    static let csharp = LanguageGrammar(
        name: "csharp", aliases: ["cs", "c#"],
        keywords: ["abstract", "as", "base", "break", "case", "catch", "checked", "class", "const", "continue",
                   "default", "delegate", "do", "else", "enum", "event", "explicit", "extern", "finally", "fixed",
                   "for", "foreach", "goto", "if", "implicit", "in", "interface", "internal", "is", "lock",
                   "namespace", "new", "operator", "out", "override", "params", "private", "protected", "public",
                   "readonly", "ref", "return", "sealed", "sizeof", "stackalloc", "static", "struct", "switch",
                   "this", "throw", "try", "typeof", "unchecked", "unsafe", "using", "virtual", "volatile", "while",
                   "async", "await", "var", "record", "get", "set", "init", "yield"],
        types: ["int", "long", "short", "byte", "char", "float", "double", "decimal", "bool", "string", "object", "void"],
        literals: ["true", "false", "null"],
        lineComments: ["//"], blockComments: [("/*", "*/")], preprocessor: true
    )

    static let go = LanguageGrammar(
        name: "go", aliases: ["golang"],
        keywords: ["break", "case", "chan", "const", "continue", "default", "defer", "else", "fallthrough", "for",
                   "func", "go", "goto", "if", "import", "interface", "map", "package", "range", "return", "select",
                   "struct", "switch", "type", "var"],
        types: ["int", "int8", "int16", "int32", "int64", "uint", "uint8", "uint16", "uint32", "uint64", "float32",
                "float64", "string", "bool", "byte", "rune", "error", "any"],
        literals: ["true", "false", "nil", "iota"],
        builtins: ["make", "new", "len", "cap", "append", "copy", "delete", "panic", "recover", "fmt"],
        lineComments: ["//"], blockComments: [("/*", "*/")],
        stringDelimiters: [UInt8(ascii: "\""), UInt8(ascii: "'"), UInt8(ascii: "`")], capitalizedTypes: false
    )

    static let rust = LanguageGrammar(
        name: "rust", aliases: ["rs"],
        keywords: ["as", "async", "await", "break", "const", "continue", "crate", "dyn", "else", "enum", "extern",
                   "fn", "for", "if", "impl", "in", "let", "loop", "match", "mod", "move", "mut", "pub", "ref",
                   "return", "self", "Self", "static", "struct", "super", "trait", "type", "unsafe", "use", "where",
                   "while"],
        types: ["i8", "i16", "i32", "i64", "i128", "isize", "u8", "u16", "u32", "u64", "u128", "usize", "f32",
                "f64", "bool", "char", "str", "String", "Vec", "Option", "Result", "Box"],
        literals: ["true", "false", "None", "Some", "Ok", "Err"],
        lineComments: ["//"], blockComments: [("/*", "*/")],
        stringDelimiters: [UInt8(ascii: "\"")], attributePrefix: UInt8(ascii: "#")
    )

    static let ruby = LanguageGrammar(
        name: "ruby", aliases: ["rb"],
        keywords: ["alias", "and", "begin", "break", "case", "class", "def", "defined?", "do", "else", "elsif", "end",
                   "ensure", "for", "if", "in", "module", "next", "not", "or", "redo", "rescue", "retry", "return",
                   "self", "super", "then", "undef", "unless", "until", "when", "while", "yield", "require", "attr_accessor"],
        literals: ["true", "false", "nil"],
        lineComments: ["#"], attributePrefix: UInt8(ascii: "@"), identifierExtras: [UInt8(ascii: "?"), UInt8(ascii: "!")]
    )

    static let php = LanguageGrammar(
        name: "php", aliases: [],
        keywords: ["abstract", "and", "as", "break", "case", "catch", "class", "clone", "const", "continue",
                   "declare", "default", "do", "echo", "else", "elseif", "extends", "final", "finally", "fn", "for",
                   "foreach", "function", "global", "if", "implements", "include", "instanceof", "interface",
                   "namespace", "new", "or", "private", "protected", "public", "require", "return", "static",
                   "switch", "throw", "trait", "try", "use", "var", "while", "yield", "match"],
        literals: ["true", "false", "null", "TRUE", "FALSE", "NULL"],
        lineComments: ["//", "#"], blockComments: [("/*", "*/")], variablePrefix: UInt8(ascii: "$")
    )

    static let shell = LanguageGrammar(
        name: "shell", aliases: ["sh", "bash", "zsh", "console", "terminal", "shell-session", "fish"],
        keywords: ["if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done", "case", "esac", "in",
                   "function", "return", "local", "export", "readonly", "select", "time"],
        builtins: ["echo", "cd", "ls", "cat", "grep", "sed", "awk", "git", "npm", "swift", "xcodebuild", "brew",
                   "curl", "mkdir", "rm", "cp", "mv", "sudo", "pip", "python", "source", "set", "unset", "printf"],
        lineComments: ["#"], capitalizedTypes: false, variablePrefix: UInt8(ascii: "$"),
        identifierExtras: [UInt8(ascii: "-")]
    )

    static let sql = LanguageGrammar(
        name: "sql", aliases: ["mysql", "postgresql", "postgres", "sqlite", "plsql"],
        keywords: ["select", "from", "where", "insert", "into", "values", "update", "set", "delete", "create",
                   "table", "drop", "alter", "add", "index", "view", "join", "inner", "left", "right", "outer", "full",
                   "on", "as", "and", "or", "not", "null", "is", "in", "between", "like", "group", "by", "order",
                   "having", "limit", "offset", "distinct", "union", "all", "case", "when", "then", "else", "end",
                   "primary", "key", "foreign", "references", "default", "unique", "exists", "with", "returning",
                   "asc", "desc", "count", "sum", "avg", "min", "max"],
        types: ["int", "integer", "bigint", "smallint", "varchar", "char", "text", "boolean", "date", "timestamp",
                "decimal", "numeric", "real", "float", "serial", "uuid", "json", "jsonb"],
        literals: ["true", "false"],
        lineComments: ["--"], blockComments: [("/*", "*/")], capitalizedTypes: false, caseInsensitive: true
    )

    static let html = LanguageGrammar(
        name: "html", aliases: ["xml", "xhtml", "svg", "plist", "vue", "htm"],
        blockComments: [("<!--", "-->")], capitalizedTypes: false, mode: .markup
    )

    static let css = LanguageGrammar(
        name: "css", aliases: ["scss", "sass", "less"],
        keywords: ["important", "media", "import", "keyframes", "font-face", "supports", "root"],
        lineComments: ["//"], blockComments: [("/*", "*/")], capitalizedTypes: false,
        attributePrefix: UInt8(ascii: "@"), identifierExtras: [UInt8(ascii: "-")], mode: .css
    )

    static let yaml = LanguageGrammar(
        name: "yaml", aliases: ["yml", "toml", "ini"],
        literals: ["true", "false", "null", "yes", "no", "on", "off", "~"],
        lineComments: ["#"], capitalizedTypes: false, identifierExtras: [UInt8(ascii: "-"), UInt8(ascii: ".")],
        mode: .yaml
    )

    static let markdown = LanguageGrammar(
        name: "markdown", aliases: ["md"],
        stringDelimiters: [UInt8(ascii: "`")], capitalizedTypes: false
    )

    static let diff = LanguageGrammar(name: "diff", aliases: ["patch"], capitalizedTypes: false, mode: .diff)

    static let dart = LanguageGrammar(
        name: "dart", aliases: ["flutter"],
        keywords: ["abstract", "as", "assert", "async", "await", "break", "case", "catch", "class", "const",
                   "continue", "default", "do", "else", "enum", "export", "extends", "extension", "factory",
                   "final", "finally", "for", "get", "if", "implements", "import", "in", "is", "late", "library",
                   "mixin", "new", "on", "operator", "part", "required", "rethrow", "return", "set", "static",
                   "super", "switch", "this", "throw", "try", "var", "void", "while", "with", "yield"],
        types: ["int", "double", "num", "String", "bool", "List", "Map", "Set", "dynamic", "Object"],
        literals: ["true", "false", "null"],
        lineComments: ["//"], blockComments: [("/*", "*/")], tripleQuotes: true, attributePrefix: UInt8(ascii: "@")
    )

    static let scala = LanguageGrammar(
        name: "scala", aliases: ["sc"],
        keywords: ["abstract", "case", "catch", "class", "def", "do", "else", "extends", "final", "finally", "for",
                   "forSome", "if", "implicit", "import", "lazy", "match", "new", "object", "override", "package",
                   "private", "protected", "return", "sealed", "super", "this", "throw", "trait", "try", "type",
                   "val", "var", "while", "with", "yield", "given", "using", "enum", "then"],
        literals: ["true", "false", "null"],
        lineComments: ["//"], blockComments: [("/*", "*/")], tripleQuotes: true, attributePrefix: UInt8(ascii: "@")
    )
}
