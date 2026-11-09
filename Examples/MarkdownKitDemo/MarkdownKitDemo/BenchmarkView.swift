import SwiftUI
import MarkdownKit
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Auto-scrolls the 200-message chat and measures frame pacing (hitch time ratio), like Instruments'
/// scroll hitch metric. Run it on a device for real numbers.
struct BenchmarkView: View {
    @Environment(DemoSettings.self) private var settings
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var position = ScrollPosition(edge: .top)
    @State private var meter = FrameMeter()
    @State private var speed: Double = 2_500
    @State private var coldCache = true
    @State private var prefetch = UserDefaults.standard.object(forKey: "prefetch") == nil || UserDefaults.standard.bool(forKey: "prefetch")
    @State private var width: CGFloat?
    /// `-baseline YES`: scroll plain SwiftUI `Text` rows (no Markdown) to calibrate the device/simulator.
    private let baseline = UserDefaults.standard.bool(forKey: "baseline")

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                if baseline {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(SampleContent.conversation) { Text($0.text).padding(.horizontal) }
                    }
                } else {
                    ChatTranscript(flatten: settings.flattenBlocks)
                }
            }
            .scrollPosition($position)
            .scrollDisabled(meter.isRunning)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.width }) { width = $0 }
            results
        }
        .navigationTitle("Scroll benchmark")
        // `-autorun YES` starts a run on launch and logs the report (for automation).
        .task {
            guard UserDefaults.standard.bool(forKey: "autorun") else { return }
            try? await Task.sleep(for: .seconds(2))
            run()
        }
        .onChange(of: meter.report?.frames) {
            guard let report = meter.report else { return }
            print(String(format: "BENCHMARK baseline=%@ prefetch=%@ flatten=%@ renderer=%@ frames=%d hitchRatio=%.2fms/s dropped=%d worst=%.1fms refresh=%.0fHz",
                         baseline ? "yes" : "no", prefetch ? "yes" : "no", settings.flattenBlocks ? "yes" : "no", String(describing: settings.renderer), report.frames,
                         report.hitchRatio, report.droppedFrames, report.worstFrame, 1 / report.expectedInterval))
        }
    }

    private var results: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(Int(speed)) pt/s").monospacedDigit()
                Slider(value: $speed, in: 500...8_000)
            }
            Toggle("Start with cold caches", isOn: $coldCache)
            Toggle("Prefetch (parse + typeset in background first)", isOn: $prefetch)
            HStack {
                Button(meter.isRunning ? "Running…" : "Run 12 s scroll") { run() }
                    .buttonStyle(.borderedProminent)
                    .disabled(meter.isRunning)
                Spacer()
            }
            if let report = meter.report {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 2) {
                    GridRow { Text("Frames"); Text("\(report.frames)") }
                    GridRow { Text("Hitch time ratio"); Text(String(format: "%.1f ms/s (%@)", report.hitchRatio, report.verdict)) }
                    GridRow { Text("Dropped frames"); Text("\(report.droppedFrames)") }
                    GridRow { Text("Worst frame"); Text(String(format: "%.1f ms", report.worstFrame)) }
                    GridRow { Text("Refresh rate"); Text(String(format: "%.0f Hz", 1 / report.expectedInterval)) }
                }
                .font(.callout.monospacedDigit())
            }
        }
        .padding()
        .background(.bar)
    }

    private func run() {
        if coldCache { MarkdownCache.shared.removeAll() }
        position.scrollTo(edge: .top)
        Task {
            if prefetch {
                // What a chat app does when a conversation loads, before the user scrolls.
                await MarkdownPrefetcher.prefetch(SampleContent.conversation.filter { !$0.isUser }.map(\.text),
                                                  width: width.map { $0 - 2 * ChatTranscript.padding },
                                                  theme: settings.theme, colorScheme: colorScheme,
                                                  dynamicTypeSize: dynamicTypeSize, textRenderer: settings.renderer)
            }
            meter.start(duration: 12) { elapsed in
                position.scrollTo(y: elapsed * speed)
            }
        }
    }
}

/// Drives a per-frame callback with the display link and records frame intervals.
@Observable
final class FrameMeter {
    struct Report {
        var frames: Int
        var hitchRatio: Double      // ms of hitch per second
        var droppedFrames: Int
        var worstFrame: Double      // ms
        var expectedInterval: Double

        var verdict: String {
            switch hitchRatio {
            case ..<5: "good"
            case ..<10: "warning"
            default: "critical"
            }
        }
    }

    private(set) var isRunning = false
    private(set) var report: Report?

    @ObservationIgnored private var link: AnyObject?
    @ObservationIgnored private var startTime: CFTimeInterval = 0
    @ObservationIgnored private var lastTime: CFTimeInterval = 0
    @ObservationIgnored private var duration: Double = 0
    @ObservationIgnored private var intervals: [Double] = []
    @ObservationIgnored private var expected: Double = 1.0 / 60
    @ObservationIgnored private var onFrame: ((Double) -> Void)?

    func start(duration: Double, onFrame: @escaping (Double) -> Void) {
        self.duration = duration
        self.onFrame = onFrame
        intervals = []
        startTime = 0
        isRunning = true
        report = nil
        #if canImport(UIKit)
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
        #else
        if let link = NSScreen.main?.displayLink(target: self, selector: #selector(tick(_:))) {
            link.add(to: .main, forMode: .common)
            self.link = link
        }
        #endif
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        if startTime == 0 {
            startTime = now
            lastTime = now
            expected = max(link.targetTimestamp - link.timestamp, 1.0 / 120)
            return
        }
        if now - lastTime > expected * 1.5, UserDefaults.standard.bool(forKey: "log") {
            print(String(format: "HITCH %.3f %.1fms", now, (now - lastTime) * 1000))
        }
        intervals.append(now - lastTime)
        lastTime = now
        let elapsed = now - startTime
        onFrame?(elapsed)
        if elapsed >= duration { finish() }
    }

    private func finish() {
        (link as? CADisplayLink)?.invalidate()
        link = nil
        isRunning = false
        let total = intervals.reduce(0, +)
        let hitch = intervals.reduce(0) { $0 + max(0, $1 - expected * 1.5 > 0 ? $1 - expected : 0) }
        let dropped = intervals.reduce(0) { $0 + max(0, Int(($1 / expected).rounded()) - 1) }
        report = Report(frames: intervals.count, hitchRatio: total > 0 ? hitch * 1000 / total : 0,
                        droppedFrames: dropped, worstFrame: (intervals.max() ?? 0) * 1000, expectedInterval: expected)
    }
}
