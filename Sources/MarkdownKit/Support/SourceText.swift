import Foundation

/// Markdown source with a precomputed byte-level hash.
///
/// `String` hashing and equality go through Unicode normalization, which costs ~1 ms for a 200 KB
/// message with emoji. This wrapper hashes and compares raw UTF-8 bytes instead.
struct SourceText: Hashable, Sendable {
    let string: String
    let byteHash: UInt64
    let byteCount: Int

    init(_ string: String) {
        var string = string
        string.makeContiguousUTF8()
        self.string = string
        byteCount = string.utf8.count
        byteHash = string.utf8.withContiguousStorageIfAvailable { FastHash.hash($0) } ?? FastHash.hash(Array(string.utf8))
    }

    static func == (lhs: SourceText, rhs: SourceText) -> Bool {
        guard lhs.byteCount == rhs.byteCount, lhs.byteHash == rhs.byteHash else { return false }
        return lhs.string.utf8.withContiguousStorageIfAvailable { a in
            rhs.string.utf8.withContiguousStorageIfAvailable { b in
                a.count == 0 || memcmp(a.baseAddress!, b.baseAddress!, a.count) == 0
            }
        }.flatMap { $0 } ?? lhs.string.utf8.elementsEqual(rhs.string.utf8)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(byteHash)
        hasher.combine(byteCount)
    }
}

/// 64-bit non-cryptographic hash over bytes (8 bytes per step, multiply-xorshift mixing).
enum FastHash {
    static func hash<C: Collection>(_ bytes: C) -> UInt64 where C.Element == UInt8 {
        if let result = bytes.withContiguousStorageIfAvailable({ hash(UnsafeRawBufferPointer($0)) }) {
            return result
        }
        return Array(bytes).withUnsafeBytes { hash($0) }
    }

    static func hash(_ buffer: UnsafeRawBufferPointer) -> UInt64 {
        var h: UInt64 = 0x9E37_79B9_7F4A_7C15 ^ UInt64(buffer.count)
        var index = 0
        let count = buffer.count
        while index + 8 <= count {
            let word = buffer.loadUnaligned(fromByteOffset: index, as: UInt64.self)
            h = mix(h ^ word)
            index += 8
        }
        var tail: UInt64 = 0
        var shift: UInt64 = 0
        while index < count {
            tail |= UInt64(buffer[index]) << shift
            shift += 8
            index += 1
        }
        return mix(h ^ tail)
    }

    @inline(__always)
    private static func mix(_ value: UInt64) -> UInt64 {
        var z = value &* 0xBF58_476D_1CE4_E5B9
        z ^= z >> 31
        z = z &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 29)
    }
}
