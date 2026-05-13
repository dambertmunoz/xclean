import AppKit

/// A donut (ring) chart drawn entirely with CoreGraphics — no images, no
/// nested views. One `CAShapeLayer` per segment, plus a single text label
/// in the centre. Setting `segments` interpolates each slice with a
/// CABasicAnimation so values morph smoothly when the data refreshes.
///
/// Memory budget: O(segments) — typically 3-5 layers, a few KB total.
/// CPU budget: redraws only when `segments` changes, then GPU-compositing
/// after.
final class DonutChartView: NSView {

    struct Segment {
        let value: Double            // raw weight; segments are normalised by sum
        let color: NSColor
    }

    // MARK: - public state

    var segments: [Segment] = [] {
        didSet { rebuildLayers(animated: true) }
    }

    var centerTitle: String = "" {
        didSet { centerTitleLayer.string = centerTitle }
    }
    var centerSubtitle: String = "" {
        didSet { centerSubtitleLayer.string = centerSubtitle }
    }

    // MARK: - layer-backed

    private var sliceLayers: [CAShapeLayer] = []
    private let centerTitleLayer = CATextLayer()
    private let centerSubtitleLayer = CATextLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.masksToBounds = false
        setupCenterText()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        layer = CALayer()
        layer?.masksToBounds = false
        setupCenterText()
    }

    // MARK: - layout

    override func layout() {
        super.layout()
        positionLayers()
    }

    override var isFlipped: Bool { true }

    // MARK: - setup

    private func setupCenterText() {
        for tl in [centerTitleLayer, centerSubtitleLayer] {
            tl.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
            tl.alignmentMode = .center
            tl.truncationMode = .end
            tl.foregroundColor = NSColor.labelColor.cgColor
        }
        centerTitleLayer.font = NSFont.systemFont(ofSize: 17, weight: .semibold)
        centerTitleLayer.fontSize = 17
        centerSubtitleLayer.font = NSFont.systemFont(ofSize: 10, weight: .regular)
        centerSubtitleLayer.fontSize = 10
        centerSubtitleLayer.foregroundColor = NSColor.secondaryLabelColor.cgColor
        layer?.addSublayer(centerTitleLayer)
        layer?.addSublayer(centerSubtitleLayer)
    }

    // MARK: - drawing

    private var chartCenter: CGPoint {
        // Chart lives on the left half of the frame; layout assumes a
        // legend to the right.
        let h = bounds.height
        return CGPoint(x: h / 2 + 8, y: h / 2)
    }
    private var chartRadius: CGFloat { (bounds.height - 16) / 2 }
    private var chartThickness: CGFloat { 11 }

    private func positionLayers() {
        let textW: CGFloat = max(40, chartRadius * 2 - 12)
        let titleH: CGFloat = 22
        let subH: CGFloat = 14
        centerTitleLayer.frame = CGRect(
            x: chartCenter.x - textW / 2,
            y: chartCenter.y - titleH / 2 - 4,
            width: textW, height: titleH
        )
        centerSubtitleLayer.frame = CGRect(
            x: chartCenter.x - textW / 2,
            y: chartCenter.y + 8,
            width: textW, height: subH
        )
        for (i, slice) in sliceLayers.enumerated() {
            slice.frame = bounds
            slice.path = pathFor(index: i)?.cgPath
        }
    }

    /// Recreate one shape layer per segment. Cheap — segments are tiny in
    /// count, and reusing layer pool would barely save anything.
    private func rebuildLayers(animated: Bool) {
        for old in sliceLayers { old.removeFromSuperlayer() }
        sliceLayers.removeAll()

        guard !segments.isEmpty else { needsDisplay = true; return }

        for (i, seg) in segments.enumerated() {
            let shape = CAShapeLayer()
            shape.frame = bounds
            shape.fillColor = NSColor.clear.cgColor
            shape.strokeColor = seg.color.cgColor
            shape.lineWidth = chartThickness
            shape.lineCap = .butt
            shape.path = pathFor(index: i)?.cgPath
            layer?.insertSublayer(shape, below: centerTitleLayer)
            sliceLayers.append(shape)
        }

        if animated {
            for shape in sliceLayers {
                let anim = CABasicAnimation(keyPath: "strokeEnd")
                anim.fromValue = 0
                anim.toValue = 1
                anim.duration = 0.45
                anim.timingFunction = CAMediaTimingFunction(name: .easeOut)
                shape.add(anim, forKey: "stroke")
            }
        }
    }

    private func pathFor(index: Int) -> NSBezierPath? {
        let total = segments.reduce(0.0) { $0 + max(0, $1.value) }
        guard total > 0 else { return nil }
        var accumulated = 0.0
        for i in 0..<index {
            accumulated += max(0, segments[i].value)
        }
        let startFrac = accumulated / total
        let endFrac = (accumulated + max(0, segments[index].value)) / total
        let twoPi = 2 * Double.pi
        // Start at 12 o'clock, go clockwise
        let startAngle = CGFloat(-twoPi / 4 + startFrac * twoPi)
        let endAngle   = CGFloat(-twoPi / 4 + endFrac * twoPi)

        let path = NSBezierPath()
        path.appendArc(
            withCenter: chartCenter,
            radius: chartRadius - chartThickness / 2,
            startAngle: startAngle * 180 / .pi,
            endAngle: endAngle * 180 / .pi,
            clockwise: false
        )
        return path
    }
}

/// NSBezierPath → CGPath shim. Used in cross-platform projects too often
/// to inline every time.
private extension NSBezierPath {
    var cgPath: CGPath {
        let path = CGMutablePath()
        var points = [CGPoint](repeating: .zero, count: 3)
        for i in 0..<elementCount {
            switch element(at: i, associatedPoints: &points) {
            case .moveTo:        path.move(to: points[0])
            case .lineTo:        path.addLine(to: points[0])
            case .curveTo:       path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .cubicCurveTo:  path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .quadraticCurveTo: path.addQuadCurve(to: points[1], control: points[0])
            case .closePath:     path.closeSubpath()
            @unknown default:    break
            }
        }
        return path
    }
}
