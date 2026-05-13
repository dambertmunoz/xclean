import AppKit

/// Observes macOS sleep/wake notifications so the indexer can refresh after
/// a long sleep where FSEvents miss filesystem changes.
final class SystemEvents {

    var onWake: (() -> Void)?

    private var wakeToken: NSObjectProtocol?

    func start() {
        let nc = NSWorkspace.shared.notificationCenter
        wakeToken = nc.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.onWake?()
        }
    }

    func stop() {
        if let token = wakeToken {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
            wakeToken = nil
        }
    }

    deinit { stop() }
}
