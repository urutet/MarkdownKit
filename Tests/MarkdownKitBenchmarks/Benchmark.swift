import Foundation
import Testing

/// Timing statistics for a benchmark.
struct BenchmarkResult: CustomStringConvertible {
    var name: String
    var samples: [Duration]
    var peakMemoryMB: Double

    private var sorted: [Double] { samples.map(\.milliseconds).sorted() }

    var median: Double { percentile(0.5) }
    var p95: Double { percentile(0.95) }
    var p99: Double { percentile(0.99) }
    var max: Double { sorted.last ?? 0 }
    var min: Double { sorted.first ?? 0 }
    var mean: Double { samples.isEmpty ? 0 : samples.map(\.milliseconds).reduce(0, +) / Double(samples.count) }
    var total: Double { samples.map(\.milliseconds).reduce(0, +) }

    func percentile(_ p: Double) -> Double {
        let values = sorted
        guard !values.isEmpty else { return 0 }
        let index = Swift.min(values.count - 1, Int((Double(values.count - 1) * p).rounded(.up)))
        return values[index]
    }

    var description: String {
        String(format: "%-52@ n=%4d  min %8.3f  median %8.3f  p95 %8.3f  p99 %8.3f  max %8.3f ms  mem %6.1f MB",
               name as NSString, samples.count, min, median, p95, p99, max, peakMemoryMB)
    }
}

extension Duration {
    var milliseconds: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) * 1000 + Double(attoseconds) / 1e15
    }
}

enum Benchmark {
    /// `true` in optimized builds, where budgets are enforced. Debug builds only report numbers.
    static var enforcesBudgets: Bool {
        #if DEBUG
        false
        #else
        true
        #endif
    }

    /// Scales iteration counts down in debug builds.
    static func iterations(_ release: Int) -> Int {
        enforcesBudgets ? release : Swift.max(2, release / 5)
    }

    /// Runs `body` `warmup + iterations` times and records the timed iterations.
    /// `setup` runs before each iteration and is not timed.
    @discardableResult
    static func measure(_ name: String, warmup: Int = 1, iterations: Int = 10,
                        setup: () -> Void = {}, _ body: () throws -> Void) rethrows -> BenchmarkResult {
        let clock = ContinuousClock()
        for _ in 0..<warmup { setup(); try body() }
        var samples: [Duration] = []
        samples.reserveCapacity(iterations)
        for _ in 0..<iterations {
            setup()
            let start = clock.now
            try body()
            samples.append(clock.now - start)
        }
        let result = BenchmarkResult(name: name, samples: samples, peakMemoryMB: Memory.residentMB)
        report(result)
        return result
    }

    /// Records externally measured samples (e.g. per-update timings during a streaming replay).
    @discardableResult
    static func record(_ name: String, samples: [Duration]) -> BenchmarkResult {
        let result = BenchmarkResult(name: name, samples: samples, peakMemoryMB: Memory.residentMB)
        report(result)
        return result
    }

    /// Checks a budget (in milliseconds) in release builds; always prints the comparison.
    static func expect(_ value: Double, lessThan budget: Double, _ label: String,
                       sourceLocation: SourceLocation = #_sourceLocation) {
        let verdict = value < budget ? "OK  " : "OVER"
        print(String(format: "  [%@] %@: %.3f ms (budget %.1f ms)", verdict, label, value, budget))
        if enforcesBudgets {
            #expect(value < budget, "\(label): \(value) ms exceeds budget \(budget) ms", sourceLocation: sourceLocation)
        }
    }

    private static let lock = NSLock()

    private static func report(_ result: BenchmarkResult) {
        lock.lock()
        defer { lock.unlock() }
        print("⏱ \(result)")
        if let path = ProcessInfo.processInfo.environment["MARKDOWNKIT_BENCHMARK_OUTPUT"],
           let data = (result.description + "\n").data(using: .utf8) {
            if let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                FileManager.default.createFile(atPath: path, contents: data)
            }
        }
    }
}

enum Memory {
    /// Current resident memory of the process in megabytes.
    static var residentMB: Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : 0
    }
}
