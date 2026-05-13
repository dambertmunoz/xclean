import AppKit

/// Composite menu-header view: donut chart + 3-row legend. Designed to be
/// dropped into an `NSMenuItem.view`. The view is flipped + manually
/// positions everything — NSMenu doesn't run a layout pass on embedded
/// views, and Auto Layout / NSStackView don't play nicely without
/// constraints, so we keep the geometry explicit.
final class DiskBreakdownView: NSView {

    // MARK: - layout constants
    private let totalWidth: CGFloat = 320
    private let totalHeight: CGFloat = 138

    private let donutSize: CGFloat = 112
    private let donutLeft: CGFloat = 12
    private let donutTop: CGFloat = 22

    private let legendLeft: CGFloat = 138
    private let legendTop: CGFloat = 36
    private let legendRowHeight: CGFloat = 22

    private let titleLabel = NSTextField(labelWithString: "Disk usage")
    private let donut = DonutChartView(frame: .zero)
    private var legendContainer = NSView(frame: .zero)

    // MARK: - init

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 320, height: 138))
        wantsLayer = true
        setupHierarchy()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
        setupHierarchy()
    }

    override var isFlipped: Bool { true }

    // MARK: - public API

    func set(free: UInt64, recoverable: UInt64, total: UInt64, health: DiskCapacity.Health) {
        let safeRecoverable = min(recoverable, total > free ? total - free : 0)
        let otherUsed = total > (free + safeRecoverable) ? total - free - safeRecoverable : 0

        // Free segment color tracks health (green / orange / red — orange
        // not yellow so it reads on any appearance).
        let freeColor = MenuTheme.health(health)
        let warnColor = MenuTheme.recoverableFill
        let otherColor = MenuTheme.otherUsedFill

        donut.segments = [
            DonutChartView.Segment(value: Double(free),            color: freeColor),
            DonutChartView.Segment(value: Double(safeRecoverable), color: warnColor),
            DonutChartView.Segment(value: Double(otherUsed),       color: otherColor)
        ]
        donut.centerTitle = ByteSize.human(free)
        donut.centerSubtitle = "free"

        rebuildLegend(rows: [
            (color: freeColor,  label: "Free",        bytes: free),
            (color: warnColor,  label: "Recoverable", bytes: safeRecoverable),
            (color: otherColor, label: "Other used",  bytes: otherUsed)
        ])

        // Title tint reflects health, with full color saturation so even
        // light menus surface the warning.
        switch health {
        case .healthy:  titleLabel.textColor = MenuTheme.secondary
        case .warning:  titleLabel.textColor = MenuTheme.health(.warning)
        case .critical: titleLabel.textColor = MenuTheme.health(.critical)
        }
    }

    // MARK: - hierarchy

    private func setupHierarchy() {
        frame = NSRect(x: 0, y: 0, width: totalWidth, height: totalHeight)

        // Title strip — semibold so it reads as a heading.
        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = MenuTheme.secondary
        titleLabel.stringValue = "Disk usage"
        titleLabel.frame = NSRect(x: 16, y: 8, width: 200, height: 14)
        addSubview(titleLabel)

        // Donut sits left, square area.
        donut.frame = NSRect(x: donutLeft, y: donutTop, width: donutSize, height: donutSize)
        addSubview(donut)

        // Legend container, manually laid out below.
        let legendW = totalWidth - legendLeft - 16
        let legendH = legendRowHeight * 3
        legendContainer.frame = NSRect(x: legendLeft, y: legendTop, width: legendW, height: legendH)
        addSubview(legendContainer)
    }

    private func rebuildLegend(rows: [(color: NSColor, label: String, bytes: UInt64)]) {
        legendContainer.subviews.forEach { $0.removeFromSuperview() }
        let w = legendContainer.bounds.width
        let valueWidth: CGFloat = 80
        let labelLeft: CGFloat = 16
        let labelWidth: CGFloat = w - labelLeft - valueWidth - 4

        for (i, r) in rows.enumerated() {
            let y = CGFloat(i) * legendRowHeight

            // Dot.
            let dot = NSView(frame: NSRect(x: 0, y: y + 7, width: 8, height: 8))
            dot.wantsLayer = true
            dot.layer?.backgroundColor = r.color.cgColor
            dot.layer?.cornerRadius = 4
            legendContainer.addSubview(dot)

            // Label.
            let label = NSTextField(labelWithString: r.label)
            label.font = NSFont.systemFont(ofSize: 12, weight: .regular)
            label.textColor = .labelColor
            label.lineBreakMode = .byTruncatingTail
            label.frame = NSRect(x: labelLeft, y: y + 3, width: labelWidth, height: 16)
            legendContainer.addSubview(label)

            // Value (right-aligned, monospaced digits).
            let value = NSTextField(labelWithString: ByteSize.human(r.bytes))
            value.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            value.textColor = .secondaryLabelColor
            value.alignment = .right
            value.frame = NSRect(x: w - valueWidth, y: y + 4, width: valueWidth, height: 15)
            legendContainer.addSubview(value)
        }
    }

    private func colorFor(_ health: DiskCapacity.Health) -> NSColor {
        switch health {
        case .healthy:  return .systemGreen
        case .warning:  return .systemYellow
        case .critical: return .systemRed
        }
    }
}
