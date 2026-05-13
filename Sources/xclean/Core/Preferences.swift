import Foundation

/// Thin wrapper over `UserDefaults` for the menu-bar app's persistent
/// toggles. No observers — call sites read every time they need the value
/// (UserDefaults reads are an in-memory plist lookup, no cost).
final class Preferences {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    // MARK: - keys

    private enum Key {
        static let compactMode    = "xclean.compactMode"
        static let showDeltas     = "xclean.showDeltas"
        static let notifyEnabled  = "xclean.notifyEnabled"
        static let minMB          = "xclean.minMB"            // Int — entries below are hidden
        static let lastHealthRaw  = "xclean.lastHealth"       // String — last seen health for notif edge-trigger
    }

    // MARK: - getters / setters

    /// Hides entries smaller than the threshold (default 100 MB).
    var minMB: UInt64 {
        get {
            let raw = defaults.integer(forKey: Key.minMB)
            return raw <= 0 ? 100 : UInt64(raw)
        }
        set { defaults.set(Int(newValue), forKey: Key.minMB) }
    }

    /// If true, the UI raises the floor to 1 GB to keep the menu short.
    var compactMode: Bool {
        get { defaults.bool(forKey: Key.compactMode) }
        set { defaults.set(newValue, forKey: Key.compactMode) }
    }

    /// If true, entries show a `+X / −X` delta versus their last scan size.
    var showDeltas: Bool {
        get {
            if defaults.object(forKey: Key.showDeltas) == nil { return true }
            return defaults.bool(forKey: Key.showDeltas)
        }
        set { defaults.set(newValue, forKey: Key.showDeltas) }
    }

    /// If true, we fire a notification when the disk health degrades.
    var notifyEnabled: Bool {
        get {
            if defaults.object(forKey: Key.notifyEnabled) == nil { return true }
            return defaults.bool(forKey: Key.notifyEnabled)
        }
        set { defaults.set(newValue, forKey: Key.notifyEnabled) }
    }

    var lastHealth: DiskCapacity.Health? {
        get {
            guard let raw = defaults.string(forKey: Key.lastHealthRaw) else { return nil }
            switch raw {
            case "healthy":  return .healthy
            case "warning":  return .warning
            case "critical": return .critical
            default: return nil
            }
        }
        set {
            switch newValue {
            case .none: defaults.removeObject(forKey: Key.lastHealthRaw)
            case .healthy?:  defaults.set("healthy",  forKey: Key.lastHealthRaw)
            case .warning?:  defaults.set("warning",  forKey: Key.lastHealthRaw)
            case .critical?: defaults.set("critical", forKey: Key.lastHealthRaw)
            }
        }
    }

    /// Threshold the menu actually applies (in bytes) — combines compactMode
    /// with the configured minimum.
    var effectiveMinBytes: UInt64 {
        let mb = compactMode ? max(minMB, 1000) : minMB
        return mb * 1024 * 1024
    }
}
