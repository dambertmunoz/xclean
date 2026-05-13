import Foundation
import UserNotifications

/// Posts a local notification when the disk health *degrades* (healthy →
/// warning → critical). Doesn't re-notify for the same health, doesn't
/// notify for recoveries (those go up to "all good", which is just noise).
///
/// First call also requests authorization. Without permission everything
/// turns into a no-op.
enum ThresholdNotifier {

    /// `UNUserNotificationCenter.current()` crashes when called from a
    /// process whose main bundle has no identifier — i.e. a loose
    /// SwiftPM binary in `/opt/homebrew/bin`. Until xclean ships as a
    /// proper `.app` bundle we detect that and silently skip notifications.
    /// All `notifyEnabled` bookkeeping still happens (health tracking,
    /// preference state) — only the system notification is suppressed.
    private static let isAvailable: Bool = Bundle.main.bundleIdentifier != nil

    /// Call once at app launch.
    static func requestAuthorizationIfNeeded() {
        guard isAvailable else { return }
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in /* ignore */ }
    }

    /// Evaluates the new capacity, fires a notification if health worsened
    /// since last seen. Persists the new health in Preferences so the next
    /// call has a baseline.
    static func evaluate(_ capacity: DiskCapacity) {
        guard Preferences.shared.notifyEnabled else { return }

        let previous = Preferences.shared.lastHealth
        Preferences.shared.lastHealth = capacity.health

        guard isAvailable else { return }
        guard let previous = previous else { return }
        guard severity(capacity.health) > severity(previous) else { return }

        post(title: titleFor(capacity.health), body: bodyFor(capacity))
    }

    // MARK: - helpers

    private static func severity(_ h: DiskCapacity.Health) -> Int {
        switch h { case .healthy: return 0; case .warning: return 1; case .critical: return 2 }
    }

    private static func titleFor(_ h: DiskCapacity.Health) -> String {
        switch h {
        case .healthy:  return "Disk healthy"
        case .warning:  return "Disk getting low"
        case .critical: return "Disk almost full"
        }
    }

    private static func bodyFor(_ cap: DiskCapacity) -> String {
        let pct = Int(cap.freeRatio * 100 + 0.5)
        return "\(ByteSize.human(cap.availableBytes)) free · \(pct)% of \(ByteSize.human(cap.totalBytes))"
    }

    private static func post(title: String, body: String) {
        guard isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "xclean.health.\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { _ in /* ignore */ }
    }
}
