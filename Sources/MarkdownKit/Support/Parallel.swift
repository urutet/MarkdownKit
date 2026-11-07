import Foundation

enum Parallel {
    /// Splits `0..<count` into up to `workers` contiguous chunks and runs `work` on them concurrently.
    /// Results are returned in chunk order. `work` must only read shared state.
    static func map<T>(_ count: Int, workers requested: Int, _ work: (Range<Int>) -> T) -> [T] {
        let workers = max(1, min(requested, count))
        guard workers > 1 else { return count > 0 ? [work(0..<count)] : [] }
        let chunk = (count + workers - 1) / workers
        let buffer = UnsafeMutableBufferPointer<T?>.allocate(capacity: workers)
        buffer.initialize(repeating: nil)
        defer { buffer.deinitialize(); buffer.deallocate() }
        withoutActuallyEscaping(work) { work in
            nonisolated(unsafe) let work = work
            nonisolated(unsafe) let buffer = buffer
            DispatchQueue.concurrentPerform(iterations: workers) { index in
                let start = index * chunk
                let end = min(count, start + chunk)
                if start < end { buffer[index] = work(start..<end) }
            }
        }
        return buffer.compactMap { $0 }
    }

    static var processorCount: Int { ProcessInfo.processInfo.activeProcessorCount }
}
