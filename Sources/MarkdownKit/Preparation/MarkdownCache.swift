import Foundation

/// Thread-safe cost-limited cache built on `NSCache`.
final class SendableCache<Key: Hashable & Sendable, Value: Sendable>: @unchecked Sendable {
    private final class KeyBox: NSObject {
        let key: Key
        init(_ key: Key) { self.key = key }
        override var hash: Int { key.hashValue }
        override func isEqual(_ object: Any?) -> Bool { (object as? KeyBox)?.key == key }
    }

    private final class ValueBox {
        let value: Value
        init(_ value: Value) { self.value = value }
    }

    private let cache = NSCache<KeyBox, ValueBox>()

    init(totalCostLimit: Int, countLimit: Int = 0) {
        cache.totalCostLimit = totalCostLimit
        cache.countLimit = countLimit
    }

    subscript(key: Key) -> Value? {
        get { cache.object(forKey: KeyBox(key))?.value }
    }

    func set(_ value: Value, for key: Key, cost: Int) {
        cache.setObject(ValueBox(value), forKey: KeyBox(key), cost: cost)
    }

    func removeAll() {
        cache.removeAllObjects()
    }
}

/// Caches prepared blocks by content + theme, so streaming updates and repeated blocks are not
/// prepared twice.
final class PreparedBlockCache: @unchecked Sendable {
    struct Entry: Sendable {
        var content: PreparedContent
        var spacingBefore: CGFloat
        var cost: Int
    }

    static let shared = PreparedBlockCache()

    private let storage = SendableCache<Int, Entry>(totalCostLimit: 64 << 20)

    subscript(key: Int) -> Entry? {
        get { storage[key] }
        set { if let newValue { storage.set(newValue, for: key, cost: newValue.cost) } }
    }

    func removeAll() { storage.removeAll() }
}

/// Process-wide cache of fully prepared documents keyed by source text, theme and options.
/// Lets cells in a lazy chat list render instantly when they scroll back into view, and lets the host
/// app warm the cache ahead of time with ``MarkdownPrefetcher``.
public final class MarkdownCache: @unchecked Sendable {
    struct Key: Hashable, Sendable {
        var text: SourceText
        var theme: ResolvedTheme
        var options: MarkdownParseOptions
    }

    public static let shared = MarkdownCache()

    private let storage = SendableCache<Key, PreparedDocument>(totalCostLimit: 48 << 20)

    subscript(key: Key) -> PreparedDocument? {
        get { storage[key] }
        set { if let newValue { storage.set(newValue, for: key, cost: key.text.byteCount * 4) } }
    }

    /// Removes all cached documents, blocks, table cells and highlighted code (e.g. on memory warnings).
    /// Rendered formulas and decoded images have their own caches.
    public func removeAll() {
        storage.removeAll()
        PreparedBlockCache.shared.removeAll()
        TableLayoutEngine.removeCachedCells()
        CodeHighlighting.removeCachedChunks()
    }
}
