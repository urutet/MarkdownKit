import SwiftUI

/// Result of rendering a TeX formula.
struct RenderedMath: Sendable {
    var image: SendableImage
    /// Distance from the baseline to the bottom of the image, in points.
    var descent: CGFloat
}

/// Abstraction over math renderers so alternatives can be benchmarked side by side.
protocol MathRendering: Sendable {
    func render(latex: String, display: Bool, fontSize: CGFloat, color: Color.Resolved, font: MathFontName) -> RenderedMath?
}
