import SwiftUI
import QuartzCore

/// Plays animated images with Core Animation keyframe animations.
///
/// A SwiftUI `TimelineView` re-evaluates and re-renders its content on the main thread for every frame
/// of every visible animation, which showed up as scroll hitches in chats with animated emoji. A
/// keyframe animation on a layer's `contents` is played by the render server instead, with no per-frame
/// main-thread work. This is the one place where MarkdownKit drops below SwiftUI.
struct AnimatedLayerView: View {
    struct Item {
        let animation: AnimatedImage
        /// Where to show the animation, for the view's size.
        let frame: (CGSize) -> CGRect
    }

    let items: [Item]

    var body: some View {
        Representable(items: items)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

#if canImport(UIKit)
import UIKit

private struct Representable: UIViewRepresentable {
    let items: [AnimatedLayerView.Item]

    func makeUIView(context: Context) -> AnimationHostView {
        let view = AnimationHostView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ view: AnimationHostView, context: Context) {
        view.update(items)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: AnimationHostView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }
}

final class AnimationHostView: UIView {
    private let host = AnimationLayers()

    func update(_ items: [AnimatedLayerView.Item]) {
        host.update(items, in: layer, size: bounds.size)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        host.layout(size: bounds.size)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { host.restartAnimations() }
    }
}
#else
import AppKit

private struct Representable: NSViewRepresentable {
    let items: [AnimatedLayerView.Item]

    func makeNSView(context: Context) -> AnimationHostView {
        AnimationHostView()
    }

    func updateNSView(_ view: AnimationHostView, context: Context) {
        view.update(items)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: AnimationHostView, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 0, height: proposal.height ?? 0)
    }
}

final class AnimationHostView: NSView {
    private let host = AnimationLayers()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func update(_ items: [AnimatedLayerView.Item]) {
        guard let layer else { return }
        host.update(items, in: layer, size: bounds.size)
    }

    override func layout() {
        super.layout()
        host.layout(size: bounds.size)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil { host.restartAnimations() }
    }
}
#endif

/// One sublayer per animated image.
@MainActor
private final class AnimationLayers {
    private var items: [AnimatedLayerView.Item] = []
    private var layers: [CALayer] = []

    func update(_ items: [AnimatedLayerView.Item], in parent: CALayer, size: CGSize) {
        let unchanged = items.count == self.items.count
            && zip(items, self.items).allSatisfy { $0.animation === $1.animation }
        self.items = items
        if !unchanged {
            layers.forEach { $0.removeFromSuperlayer() }
            layers = items.map { item in
                let layer = CALayer()
                layer.contentsGravity = .resize
                layer.contents = item.animation.frame(index: 0)
                parent.addSublayer(layer)
                return layer
            }
            restartAnimations()
        }
        layout(size: size)
    }

    func layout(size: CGSize) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (item, layer) in zip(items, layers) {
            layer.frame = item.frame(size)
        }
        CATransaction.commit()
    }

    /// (Re)installs the animations, phase-aligned to the media clock so every copy of the same image shows
    /// the same frame.
    func restartAnimations() {
        let now = CACurrentMediaTime()
        for (item, layer) in zip(items, layers) {
            guard let animation = item.animation.makeContentsAnimation() else { continue }
            animation.beginTime = layer.convertTime(now, from: nil) - now.truncatingRemainder(dividingBy: animation.duration)
            layer.add(animation, forKey: "frames")
        }
    }
}
