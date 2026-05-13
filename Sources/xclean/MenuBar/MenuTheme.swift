import AppKit

/// Centralized design tokens for the menu-bar UI.
///
/// macOS's `systemYellow` looks great as a fill on dark surfaces but is
/// nearly invisible as **text** on a light menu background — so we map
/// our "warning" semantic to `systemOrange`, which holds contrast on
/// both appearances. Same idea for secondary text: we keep system label
/// colors (they auto-adapt to light/dark) but pick the level deliberately
/// to keep each line legible.
enum MenuTheme {

    // MARK: - semantic colors

    /// Colors for the safety-class dots in front of each consumer row.
    /// `data` uses systemOrange (not yellow) so it stays readable on
    /// light menus.
    static func safetyDot(_ klass: SafetyClass) -> NSColor {
        switch klass {
        case .cache:        return .systemGreen
        case .data:         return .systemOrange
        case .installation: return .systemRed
        case .userData:     return NSColor(white: 0.5, alpha: 1)
        }
    }

    /// Colors mirroring `DiskCapacity.Health` — used for the title tint,
    /// projection alert, sparkline, and the donut's Free segment.
    static func health(_ health: DiskCapacity.Health) -> NSColor {
        switch health {
        case .healthy:  return .systemGreen
        case .warning:  return .systemOrange   // not yellow — yellow text washes out
        case .critical: return .systemRed
        }
    }

    /// Recoverable-segment color in the donut. Stays amber because it's a
    /// filled arc (saturation reads fine), not text.
    static let recoverableFill: NSColor = .systemYellow

    /// Neutral mid-tone for the "other used" donut slice.
    static let otherUsedFill: NSColor = NSColor(white: 0.45, alpha: 1)

    // MARK: - text colors

    /// Primary text — entry labels, big totals.
    static let primary: NSColor = .labelColor

    /// Secondary — disabled rows, path strings shown in submenus.
    /// One step more visible than the macOS auto-disabled gray.
    static let secondary: NSColor = .secondaryLabelColor

    /// Tertiary — least prominent hints (e.g. "Last 7 days:" prefix).
    static let tertiary: NSColor = .tertiaryLabelColor

    /// Success accent — "Freed today" counter.
    static let success: NSColor = .systemGreen

    // MARK: - typography

    static var sectionTitleFont: NSFont {
        NSFont.systemFont(ofSize: 11, weight: .semibold)
    }

    static var sectionTitleColor: NSColor {
        // A nudge darker than secondaryLabelColor so the section breaks
        // read as headings rather than disappearing into the body.
        return NSColor.labelColor.withAlphaComponent(0.65)
    }

    static var smallSecondaryFont: NSFont {
        NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
    }

    static var monoDigitFont: NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    }
}
