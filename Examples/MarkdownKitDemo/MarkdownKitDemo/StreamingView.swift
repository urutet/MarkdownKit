import SwiftUI
import MarkdownKit

/// Simulates a model streaming tokens into a reply.
struct StreamingView: View {
    @State private var text = ""
    @State private var isStreaming = false
    @State private var task: Task<Void, Never>?
    @State private var charactersPerSecond: Double = 400
    @State private var elapsed: Duration = .zero

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                MarkdownView(text, isStreaming: isStreaming)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .defaultScrollAnchor(.bottom)
        .safeAreaInset(edge: .bottom) { controls }
        .navigationTitle("Streaming")
        .onDisappear { task?.cancel() }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            HStack {
                Text("\(Int(charactersPerSecond)) chars/s")
                    .monospacedDigit()
                Slider(value: $charactersPerSecond, in: 50...4_000)
            }
            HStack {
                Button(isStreaming ? "Stop" : "Stream answer") { isStreaming ? stop() : start() }
                    .buttonStyle(.borderedProminent)
                Spacer()
                Text("\(text.count) / \(SampleContent.streamingAnswer.count) · \(elapsed.formatted(.units(allowed: [.seconds, .milliseconds], width: .narrow)))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.bar)
    }

    private func start() {
        text = ""
        isStreaming = true
        let answer = SampleContent.streamingAnswer
        task = Task {
            let clock = ContinuousClock()
            let start = clock.now
            var index = answer.startIndex
            var rng = SampleContent.Random(state: 1)
            while index < answer.endIndex, !Task.isCancelled {
                // Tokens of 2–6 characters, like a model's output.
                let next = answer.index(index, offsetBy: rng.int(2..<7), limitedBy: answer.endIndex) ?? answer.endIndex
                text += answer[index..<next]
                index = next
                elapsed = clock.now - start
                let delay = Double(next.utf16Offset(in: answer) - index.utf16Offset(in: answer) + 4) / charactersPerSecond
                try? await Task.sleep(for: .seconds(max(delay, 0.004)))
            }
            isStreaming = false
        }
    }

    private func stop() {
        task?.cancel()
        isStreaming = false
    }
}
