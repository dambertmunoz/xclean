import AppKit

enum MenuBarApp {
    static func run() -> Never {
        let app = NSApplication.shared
        let delegate = MenuBarAppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        exit(0)
    }
}

/// Top-level coordinator. Owns:
/// * `NSStatusItem` (the menu bar icon)
/// * `IndexerService` (scan loop + capacity history + FSWatcher hook)
/// * `MenuBuilder` (NSMenu construction)
/// * `BulkCleaner` (sequential reclaim orchestrator)
///
/// Memory profile: the only growing pieces are the index dictionary
/// (tens of KB), capacity history (~3 KB), and history log (~40 KB at max).
/// Everything else is rebuilt fresh on each menu open.
final class MenuBarAppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var indexer: IndexerService!
    private let menuBuilder = MenuBuilder()

    // Latest broadcasts from the indexer.
    private var latestFindings: [InspectFinding] = []
    private var latestState: IndexerService.State = .idle
    private var latestCapacity: DiskCapacity?
    private var latestSparkline: String?

    private var currentJob: RunningJob?
    private var elapsedTimer: DispatchSourceTimer?
    private var bulkCleaner: BulkCleaner?
    private let systemEvents = SystemEvents()

    // MARK: - lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        configureIndexer()
        configureSystemEvents()
        ThresholdNotifier.requestAuthorizationIfNeeded()
        rebuildMenu()
    }

    private func configureSystemEvents() {
        systemEvents.onWake = { [weak self] in
            // After a long sleep FSEvents may have missed changes; refresh.
            self?.indexer.refreshNow()
        }
        systemEvents.start()
    }

    /// Prefer the bundled xclean glyph (`Resources/menubar.png` /
    /// `menubar@2x.png`) so the status bar matches the web brand. Falls
    /// back to the SF Symbol when running the SPM binary directly
    /// (no .app bundle, no Resources dir).
    private static func loadStatusItemImage() -> NSImage? {
        if let url = Bundle.main.url(forResource: "menubar", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            img.size = NSSize(width: 18, height: 18)
            return img
        }
        return NSImage(systemSymbolName: "internaldrive", accessibilityDescription: "xclean")
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }

        if let image = Self.loadStatusItemImage() {
            image.isTemplate = true
            button.image = image
        } else {
            button.title = "xclean"
        }
        button.imagePosition = .imageLeft
        button.toolTip = "xclean — disk pressure monitor"
    }

    private func configureIndexer() {
        indexer = IndexerService()
        indexer.onFindings = { [weak self] findings in
            self?.latestFindings = findings
            self?.rebuildMenu()
        }
        indexer.onState = { [weak self] state in
            self?.latestState = state
            self?.updateStatusItemTitle()
            self?.updateIconAppearance()
            self?.rebuildMenu()
        }
        indexer.onCapacity = { [weak self] cap, spark in
            self?.latestCapacity = cap
            self?.latestSparkline = spark
            self?.updateStatusItemTitle()
            self?.rebuildMenu()
        }
        indexer.start()
    }

    // MARK: - menu rebuild

    private func rebuildMenu() {
        let bulkCandidates = latestFindings.filter { $0.entry.cleanup != nil }
        let bulkPotential = bulkCandidates.reduce(UInt64(0)) { $0 + $1.sizeBytes }

        // Projection from capacity history (nil when growing / not enough data).
        let projection: TimeInterval? = {
            guard let cap = latestCapacity, let h = indexer?.capacityHistory else { return nil }
            return h.projectedExhaustionSeconds(currentAvailable: cap.availableBytes)
        }()

        let hasProjects = latestFindings.contains { $0.entry.category == .projectArtifacts }

        let inputs = MenuBuilder.Inputs(
            findings: latestFindings,
            capacity: latestCapacity,
            sparkline: latestSparkline,
            state: latestState,
            freedToday: indexer?.history.bytesFreedToday() ?? 0,
            bulkCount: bulkCandidates.count,
            bulkPotentialBytes: bulkPotential,
            recentHistory: indexer?.history.recent(limit: 20) ?? [],
            projectionSeconds: projection,
            autoReclaimEnabled: Scheduler.isInstalled,
            hasProjectArtifacts: hasProjects
        )
        let callbacks = MenuBuilder.Callbacks(
            onReveal: { [weak self] url in self?.reveal(url) },
            onCleanup: { [weak self] f, cmd in self?.confirmCleanup(finding: f, command: cmd) },
            onTrash: { [weak self] f in self?.confirmTrash(f) },
            onCopyCommand: { [weak self] s in self?.copyToClipboard(s) },
            onRefresh: { [weak self] in self?.indexer.refreshNow() },
            onCancel: { [weak self] in self?.cancelCurrentJob() },
            onBulk: { [weak self] in self?.confirmAndRunBulk() },
            onToggleCompact: { [weak self] in self?.toggleCompact() },
            onToggleDeltas: { [weak self] in self?.toggleDeltas() },
            onToggleNotify: { [weak self] in self?.toggleNotify() },
            onEditCustomPaths: { [weak self] in self?.openCustomPaths() },
            onClearHistory: { [weak self] in self?.clearHistory() },
            onScanProjects: { [weak self] in self?.scanProjects() },
            onClearProjects: { [weak self] in self?.clearProjects() },
            onToggleAutoReclaim: { [weak self] in self?.toggleAutoReclaim() },
            onGrantFDA: { [weak self] in self?.grantFullDiskAccess() },
            onEnterLicense: { [weak self] in self?.openLicenseKeyEntry() },
            onDeactivateLicense: { [weak self] in self?.deactivateLicense() }
        )
        let menu = menuBuilder.build(inputs, callbacks: callbacks)
        menu.delegate = self
        statusItem.menu = menu
    }

    // MARK: - status item title (with trend arrow)

    /// Menu-bar title rules:
    ///   * Healthy   → just the recoverable size. No noise.
    ///   * Warning   → yellow dot + free amount.
    ///   * Critical  → red dot + free amount.
    /// Plus a trend arrow when free space moved >= 500 MB in the last hour.
    private func updateStatusItemTitle() {
        guard let button = statusItem.button else { return }
        let recoverable = latestFindings.reduce(UInt64(0)) { $0 + $1.sizeBytes }

        guard let cap = latestCapacity else {
            button.attributedTitle = NSAttributedString(string: "  " + ByteSize.human(recoverable))
            button.imagePosition = .imageLeft
            return
        }

        let title = NSMutableAttributedString()

        switch cap.health {
        case .healthy:
            title.append(NSAttributedString(string: "  " + ByteSize.human(recoverable)))
        case .warning, .critical:
            let dotColor: NSColor = (cap.health == .critical) ? .systemRed : .systemYellow
            title.append(NSAttributedString(string: "  ●", attributes: [.foregroundColor: dotColor]))
            title.append(NSAttributedString(string: " " + ByteSize.human(cap.availableBytes) + " free"))
        }

        if let arrow = trendArrow(cap: cap) { title.append(arrow) }

        button.attributedTitle = title
        button.imagePosition = .imageLeft
    }

    private func trendArrow(cap: DiskCapacity) -> NSAttributedString? {
        guard let history = indexer?.capacityHistory else { return nil }
        guard let lastHour = history.availableBytes(secondsAgo: 3600) else { return nil }
        let delta = Int64(cap.availableBytes) - Int64(lastHour)
        let threshold: Int64 = 500 * 1024 * 1024
        guard abs(delta) >= threshold else { return nil }
        let arrow = delta > 0 ? " ↑" : " ↓"
        let color: NSColor = delta > 0 ? .systemGreen : .systemOrange
        return NSAttributedString(string: arrow, attributes: [.foregroundColor: color])
    }

    /// Animates the status-bar icon while a scan or destructive command is
    /// running. We pulse the layer's opacity via CABasicAnimation so it
    /// stays smooth without our timer waking up every frame — Core Animation
    /// drives the GPU compositor instead.
    private func updateIconAppearance() {
        guard let button = statusItem.button else { return }
        button.wantsLayer = true
        let layer = button.layer
        switch latestState {
        case .indexing, .running:
            if layer?.animation(forKey: "xclean.pulse") == nil {
                let pulse = CABasicAnimation(keyPath: "opacity")
                pulse.fromValue = 1.0
                pulse.toValue = 0.45
                pulse.duration = 0.85
                pulse.autoreverses = true
                pulse.repeatCount = .infinity
                pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                layer?.add(pulse, forKey: "xclean.pulse")
            }
        case .idle, .ready:
            layer?.removeAnimation(forKey: "xclean.pulse")
            layer?.opacity = 1.0
        }
    }

    // MARK: - action handlers

    private func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func copyToClipboard(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
    }

    private func cancelCurrentJob() {
        currentJob?.cancel()
        bulkCleaner?.cancel()
    }

    private func toggleCompact() {
        Preferences.shared.compactMode.toggle()
        indexer.refreshNow()
    }

    private func toggleDeltas() {
        Preferences.shared.showDeltas.toggle()
        rebuildMenu()
    }

    private func toggleNotify() {
        Preferences.shared.notifyEnabled.toggle()
        rebuildMenu()
    }

    private func openCustomPaths() {
        CustomPaths.ensureExampleExists()
        NSWorkspace.shared.open(CustomPaths.configURL)
    }

    private func clearHistory() {
        let url = IndexStore.defaultDirectory.appendingPathComponent("history.json")
        try? FileManager.default.removeItem(at: url)
        indexer.refreshNow()
        rebuildMenu()
    }

    // MARK: - project scan

    private func scanProjects() {
        beforeDestructiveOperation(label: "Scanning projects…")
        indexer.scanProjects { [weak self] count in
            self?.stopElapsedTimer()
            self?.indexer.reconfigureFSWatcher()
            self?.activateForModal()
            let alert = NSAlert()
            if count == 0 {
                alert.messageText = "No project artifacts found"
                alert.informativeText = "Searched the default roots (~/code, ~/Projects, ~/Documents, ~/Developer, …). To add custom roots, edit custom-paths.json."
            } else {
                alert.messageText = "Found \(count) project artifact\(count == 1 ? "" : "s")"
                alert.informativeText = "They appear under \"Project artifacts\" in the By-category submenu. Sizes will populate as the indexer measures them."
            }
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")
            _ = alert.runModal()
        }
    }

    private func clearProjects() {
        ProjectScanner.clearCache()
        indexer.refreshNow()
        rebuildMenu()
    }

    // MARK: - Full Disk Access onboarding

    /// macOS forbids an app from granting itself FDA — only the user can
    /// drag the binary into System Settings → Privacy → Full Disk Access.
    /// This handler does **everything else** for them:
    ///
    ///   1. If FDA is already granted, surface a small confirmation.
    ///   2. Otherwise open System Settings on the FDA pane *and* reveal
    ///      `xclean.app` in Finder, so the user can drag the icon directly
    ///      from one window into the other in a single motion.
    ///   3. Show step-by-step instructions in an alert.
    private func grantFullDiskAccess() {
        if RuntimeProbe.hasFullDiskAccess() {
            activateForModal()
            let ok = NSAlert()
            ok.messageText = "Full Disk Access already granted"
            ok.informativeText = "xclean can already modify sandboxed paths like ~/Library/Containers."
            ok.alertStyle = .informational
            ok.addButton(withTitle: "OK")
            _ = ok.runModal()
            return
        }

        // Open both windows back-to-back. The activate calls make sure
        // System Settings gains focus after Finder, so the user lands on
        // the privacy pane with Finder visible behind it ready for a drag.
        let appURL = URL(fileURLWithPath: "/Applications/xclean.app")
        if FileManager.default.fileExists(atPath: appURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([appURL])
        }
        openFullDiskAccessSettings()

        activateForModal()
        let alert = NSAlert()
        alert.messageText = "Grant Full Disk Access to xclean"
        alert.informativeText =
            "I opened two windows for you:\n\n"
            + "  1. System Settings → Privacy & Security → Full Disk Access\n"
            + "  2. Finder showing /Applications/xclean.app\n\n"
            + "Drag xclean.app from Finder into the FDA list and turn the switch on.\n"
            + "macOS may ask you to quit xclean — it will relaunch from launchd."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Got it")
        alert.addButton(withTitle: "Reopen both windows")
        if alert.runModal() == .alertSecondButtonReturn {
            grantFullDiskAccess()
        }
    }

    // MARK: - license

    /// Hard gate for destructive operations from the menu bar. Returns true
    /// if the user may proceed; false (and shows an alert with a path
    /// forward) otherwise. Reads cached license state — no network call,
    /// so it's safe to call at the start of every destructive handler.
    @discardableResult
    private func ensureLicensedOperation() -> Bool {
        if ProcessInfo.processInfo.environment["XCLEAN_LICENSE_SKIP_GATE"] != nil {
            return true
        }
        switch LicenseManager.shared.currentState() {
        case .active, .grace:
            return true
        case .unactivated, .invalid:
            promptForLicenseActivation()
            return false
        }
    }

    private func promptForLicenseActivation() {
        activateForModal()
        let alert = NSAlert()
        if case .invalid(let reason) = LicenseManager.shared.currentState() {
            alert.messageText = "License invalid (\(reason))"
            alert.informativeText = "Re-enter your license key or get a new one to continue using destructive operations."
        } else {
            alert.messageText = "Activate xclean to free space"
            alert.informativeText = "Destructive operations are gated to license holders. Activate this Mac with your key, or grab one for $10/year."
        }
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Enter license key…")
        alert.addButton(withTitle: "Buy a key")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            openLicenseKeyEntry()
        case .alertSecondButtonReturn:
            if let url = URL(string: "https://xclean-seven.vercel.app/comprar") {
                NSWorkspace.shared.open(url)
            }
        default:
            break
        }
    }

    private func openLicenseKeyEntry() {
        activateForModal()
        let alert = NSAlert()
        alert.messageText = "Activate xclean"
        alert.informativeText = "Paste your license key. One Mac per key."
        alert.alertStyle = .informational
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 22))
        field.placeholderString = "XCL-AAAA-BBBB-CCCC-DDDD"
        alert.accessoryView = field
        alert.addButton(withTitle: "Activate")
        alert.addButton(withTitle: "Cancel")
        field.becomeFirstResponder()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let key = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { [weak self] in
            do {
                let state = try await LicenseManager.shared.activate(key: key)
                await MainActor.run { [weak self] in
                    self?.showLicenseResult(state: state, error: nil)
                }
            } catch let e as LicenseManager.LicenseError {
                await MainActor.run { [weak self] in
                    self?.showLicenseResult(state: .unactivated, error: e.errorDescription ?? "activation failed")
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.showLicenseResult(state: .unactivated, error: error.localizedDescription)
                }
            }
        }
    }

    private func showLicenseResult(state: LicenseManager.State, error: String?) {
        activateForModal()
        let alert = NSAlert()
        if let err = error {
            alert.messageText = "Activation failed"
            alert.informativeText = err
            alert.alertStyle = .critical
        } else if case .active(let exp) = state {
            let days = max(0, Int(exp.timeIntervalSinceNow / 86_400))
            alert.messageText = "Activated ✓"
            alert.informativeText = "Valid for \(days) more days."
            alert.alertStyle = .informational
        } else {
            alert.messageText = "Activation completed"
            alert.alertStyle = .informational
        }
        alert.addButton(withTitle: "OK")
        _ = alert.runModal()
        rebuildMenu()
    }

    private func deactivateLicense() {
        let state = LicenseManager.shared.currentState()
        let isActive: Bool
        switch state {
        case .active, .grace: isActive = true
        default: isActive = false
        }
        guard isActive else { return }
        activateForModal()
        let alert = NSAlert()
        alert.messageText = "Release this Mac from the license?"
        alert.informativeText = "After deactivation you can activate this key on another machine. Re-activations are limited to 2 per rolling 30 days."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Deactivate")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { [weak self] in
            do {
                try await LicenseManager.shared.deactivate()
                await MainActor.run { [weak self] in
                    self?.activateForModal()
                    let done = NSAlert()
                    done.messageText = "Deactivated ✓"
                    done.informativeText = "This Mac no longer holds the activation slot."
                    done.alertStyle = .informational
                    done.addButton(withTitle: "OK")
                    _ = done.runModal()
                    self?.rebuildMenu()
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.activateForModal()
                    let err = NSAlert()
                    err.messageText = "Deactivation failed"
                    err.informativeText = error.localizedDescription
                    err.alertStyle = .critical
                    err.addButton(withTitle: "OK")
                    _ = err.runModal()
                }
            }
        }
    }

    // MARK: - auto-reclaim

    private func toggleAutoReclaim() {
        if Scheduler.isInstalled {
            _ = Scheduler.remove()
        } else {
            let ok = Scheduler.install()
            if !ok {
                activateForModal()
                let alert = NSAlert()
                alert.messageText = "Couldn't install schedule"
                alert.informativeText = "Make sure xclean is installed at /opt/homebrew/bin/xclean or /Applications/xclean.app."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                _ = alert.runModal()
            }
        }
        rebuildMenu()
    }

    // MARK: - single-entry cleanup

    private func confirmCleanup(finding: InspectFinding, command: String) {
        guard ensureLicensedOperation() else { return }
        activateForModal()
        let alert = NSAlert()
        alert.messageText = "Free \(ByteSize.human(finding.sizeBytes))?"
        alert.informativeText = "Will run:\n\n    \(command)\n\nfor \(finding.entry.label)."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Free space")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        runCleanup(finding: finding, command: command)
    }

    private func runCleanup(finding: InspectFinding, command: String) {
        beforeDestructiveOperation(label: command)
        let pathToRefresh = finding.entry.path
        let priorSize = finding.sizeBytes
        let label = finding.entry.label
        let freeBefore = latestCapacity?.availableBytes ?? 0
        currentJob = CleanupRunner.runShell(command) { [weak self] outcome in
            self?.currentJob = nil
            self?.recordHistory(kind: .cleanup, label: command, path: pathToRefresh,
                                priorSize: priorSize, outcome: outcome, displayLabel: label)
            self?.afterDestructiveOperation(outcome: outcome,
                                            affectedPath: pathToRefresh,
                                            label: command,
                                            priorSize: priorSize,
                                            freeBefore: freeBefore)
        }
    }

    private func confirmTrash(_ finding: InspectFinding) {
        guard ensureLicensedOperation() else { return }
        activateForModal()
        let alert = NSAlert()
        alert.messageText = "Move \(ByteSize.human(finding.sizeBytes)) to Trash?"
        alert.informativeText = "Will move \(finding.entry.path.path) to the Trash. Recover from Finder → Put Back."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let label = "Move to Trash: \(finding.entry.label)"
        beforeDestructiveOperation(label: label)
        let pathToRefresh = finding.entry.path
        let priorSize = finding.sizeBytes
        let displayLabel = finding.entry.label
        let freeBefore = latestCapacity?.availableBytes ?? 0
        CleanupRunner.trash(finding.entry.path) { [weak self] outcome in
            self?.recordHistory(kind: .trash, label: label, path: pathToRefresh,
                                priorSize: priorSize, outcome: outcome, displayLabel: displayLabel)
            self?.afterDestructiveOperation(outcome: outcome,
                                            affectedPath: pathToRefresh,
                                            label: label,
                                            priorSize: priorSize,
                                            freeBefore: freeBefore)
        }
    }

    // MARK: - bulk cleanup

    private func confirmAndRunBulk() {
        guard ensureLicensedOperation() else { return }
        let candidates = latestFindings.filter { $0.entry.cleanup != nil }
        let total = candidates.reduce(UInt64(0)) { $0 + $1.sizeBytes }

        activateForModal()
        let alert = NSAlert()
        alert.messageText = "Reclaim ~\(ByteSize.human(total))?"
        alert.informativeText = "Will run \(candidates.count) official cleanup commands in sequence. Progress shown in the menu; cancellable anytime."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reclaim")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        runBulk(candidates)
    }

    private func runBulk(_ candidates: [InspectFinding]) {
        let cleaner = BulkCleaner()
        bulkCleaner = cleaner

        cleaner.onProgress = { [weak self] p in
            let label = "Reclaim \(p.completed + 1)/\(p.total): \(p.currentLabel)"
            self?.indexer.setRunning(label: label, startedAt: Date())
            self?.startElapsedTimer()
            self?.rebuildMenu()
        }
        cleaner.onStepFinished = { [weak self] finding, estimatedFreed in
            // Refresh just the entry we touched so the menu reflects new sizes.
            self?.indexer.refreshEntry(path: finding.entry.path)
            let event = HistoryEvent(
                timestamp: Date(),
                kind: .bulk,
                label: finding.entry.cleanup ?? "(bulk step)",
                pathString: finding.entry.path.path,
                bytesFreed: estimatedFreed,
                success: estimatedFreed > 0,
                failureMessage: nil
            )
            self?.indexer.history.append(event)
        }
        cleaner.onComplete = { [weak self] outcome in
            self?.bulkCleaner = nil
            self?.stopElapsedTimer()
            self?.indexer.refreshNow()
            self?.activateForModal()

            let alert = NSAlert()
            if outcome.canceled {
                alert.messageText = "Bulk reclaim canceled"
                alert.informativeText = "Completed \(outcome.completed)/\(outcome.total). Freed approximately \(ByteSize.human(outcome.bytesFreed))."
            } else if outcome.failures.isEmpty {
                alert.messageText = "Reclaim complete"
                alert.informativeText = "Ran \(outcome.completed) of \(outcome.total) cleanups. Freed approximately \(ByteSize.human(outcome.bytesFreed))."
                alert.alertStyle = .informational
            } else {
                alert.messageText = "Reclaim finished with errors"
                let detail = outcome.failures
                    .prefix(5)
                    .map { "• \($0.label): \($0.message)" }
                    .joined(separator: "\n")
                alert.informativeText = "Freed approximately \(ByteSize.human(outcome.bytesFreed)).\n\nFailures:\n\(detail)"
                alert.alertStyle = .warning
            }
            alert.addButton(withTitle: "OK")
            _ = alert.runModal()
        }

        // Start it. State + UI updates happen via onProgress.
        beforeDestructiveOperation(label: "Bulk reclaim (\(candidates.count) actions)")
        cleaner.run(candidates)
    }

    // MARK: - operation lifecycle

    private func beforeDestructiveOperation(label: String) {
        indexer.setRunning(label: label, startedAt: Date())
        statusItem.button?.title = "  …"
        startElapsedTimer()
    }

    private func afterDestructiveOperation(outcome: CleanupRunner.Outcome,
                                           affectedPath: URL,
                                           label: String,
                                           priorSize: UInt64 = 0,
                                           freeBefore: UInt64 = 0) {
        stopElapsedTimer()
        switch outcome {
        case .success:
            indexer.refreshEntry(path: affectedPath)
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.indexer.refreshNow()
            }
            // Disk-pressure sanity check — if the kernel didn't free what
            // we expected, processes are holding ghost FDs. Detect & offer.
            if priorSize > 200 * 1024 * 1024 {
                checkForGhostFiles(after: 2.5,
                                   path: affectedPath,
                                   priorSize: priorSize,
                                   freeBefore: freeBefore)
            }
        case .canceled:
            indexer.refreshEntry(path: affectedPath)
        case .failure(let message):
            presentFailureAlert(error: message, command: label, affectedPath: affectedPath)
            indexer.refreshEntry(path: affectedPath)
        }
    }

    /// Presents the right failure UI for the kind of error we just got.
    /// Specialised paths exist for the most common "the user is now stuck"
    /// failures so each one offers a concrete next action instead of a
    /// dead-end "Operation failed" dialog.
    private func presentFailureAlert(error: String, command: String, affectedPath: URL) {
        activateForModal()
        if Self.isSandboxPermissionError(error) {
            presentSandboxPermissionAlert(error: error, affectedPath: affectedPath)
            return
        }
        let alert = NSAlert()
        let humanized = Self.humanize(error: error, command: command)
        alert.messageText = humanized.title
        alert.informativeText = humanized.body
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        _ = alert.runModal()
    }

    /// macOS App Sandbox blocks third-party apps from touching another
    /// app's `~/Library/Containers/<bundle>` directory, regardless of POSIX
    /// ownership. The fix is Full Disk Access in System Settings → Privacy
    /// → Full Disk Access, after which xclean can trash those folders.
    ///
    /// Detected by either NSCocoa error 513 phrasing or the underlying
    /// AFP error string.
    private static func isSandboxPermissionError(_ msg: String) -> Bool {
        let lower = msg.lowercased()
        if lower.contains("afpaccessdenied") { return true }
        if lower.contains("insufficient access privileges") { return true }
        if lower.contains("nscocoaerrordomain") && lower.contains("513") { return true }
        if lower.contains("couldn't be moved to the trash because you don't have permission") { return true }
        return false
    }

    private func presentSandboxPermissionAlert(error: String, affectedPath: URL) {
        let alert = NSAlert()
        alert.messageText = "macOS blocked this delete"
        let shortPath = affectedPath.path.replacingOccurrences(
            of: NSHomeDirectory(), with: "~"
        )
        alert.informativeText =
            "\(shortPath)\n\nis protected by macOS App Sandbox. Even though you own the files, "
            + "third-party apps can't modify `~/Library/Containers/*` without **Full Disk Access**.\n\n"
            + "Pick one:\n"
            + "  • Grant FDA to xclean (one-time setup, then retry)\n"
            + "  • Move the folder to Trash yourself via Finder\n"
            + "  • Run `rm -rf` in Terminal as your own user"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Privacy Settings")
        alert.addButton(withTitle: "Show in Finder")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            openFullDiskAccessSettings()
        case .alertSecondButtonReturn:
            NSWorkspace.shared.activateFileViewerSelecting([affectedPath])
        default:
            break
        }
        _ = error  // kept for future telemetry; we already showed the path
    }

    /// Open System Settings directly on the Full Disk Access pane.
    private func openFullDiskAccessSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles")
            ?? URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
    }

    /// Translates raw stderr into something a human can act on. We keep
    /// the original error attached at the bottom so power users still see
    /// exactly what the subprocess said.
    private static func humanize(error: String, command: String) -> (title: String, body: String) {
        let lower = error.lowercased()
        if lower.contains("docker.sock") || lower.contains("docker daemon")
            || lower.contains("cannot connect to the docker daemon") {
            return (
                title: "Docker isn't running",
                body: "`\(command)` needs the Docker daemon to be up.\n\n"
                    + "Open Docker Desktop, wait until the whale icon settles, then retry the cleanup.\n\n"
                    + "— original error —\n\(error)"
            )
        }
        if lower.contains("command not found") {
            return (
                title: "Tool not installed",
                body: "The cleanup command refers to a tool that isn't on PATH.\n\n"
                    + "Install it (or remove the entry from custom-paths.json) and retry.\n\n"
                    + "— original error —\n\(error)"
            )
        }
        if lower.contains("permission denied") || lower.contains("operation not permitted") {
            return (
                title: "Permission denied",
                body: "macOS blocked the deletion. If the target is inside Library, give xclean Full Disk Access in System Settings → Privacy & Security.\n\n"
                    + "— original error —\n\(error)"
            )
        }
        if lower.contains("no such file") || lower.contains("does not exist") {
            return (
                title: "Already gone",
                body: "The target path doesn't exist anymore — probably already cleaned. Refreshing the index.\n\n"
                    + "— original error —\n\(error)"
            )
        }
        return (
            title: "Operation failed",
            body: "\(command)\n\n\(error)"
        )
    }

    private func recordHistory(kind: HistoryEvent.Kind,
                               label: String,
                               path: URL,
                               priorSize: UInt64,
                               outcome: CleanupRunner.Outcome,
                               displayLabel: String) {
        let success: Bool
        let failure: String?
        switch outcome {
        case .success:        success = true;  failure = nil
        case .canceled:       success = false; failure = "canceled by user"
        case .failure(let m): success = false; failure = m
        }
        // Conservative estimate; the indexer's next refresh will land the
        // real delta on the *next* run.
        let freed = success ? priorSize : 0
        indexer.history.append(HistoryEvent(
            timestamp: Date(),
            kind: kind,
            label: displayLabel,
            pathString: path.path,
            bytesFreed: freed,
            success: success,
            failureMessage: failure
        ))
    }

    // MARK: - ghost file recovery

    /// Compares the disk delta against the expected one and, if the kernel
    /// hasn't released the bytes (background processes hold deleted file
    /// descriptors), surfaces the offending PIDs and offers to send them
    /// SIGTERM so the kernel can finalise the reclaim.
    private func checkForGhostFiles(after delay: TimeInterval,
                                    path: URL,
                                    priorSize: UInt64,
                                    freeBefore: UInt64) {
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            guard let cap = DiskInspector.current() else { return }
            let actualFreed = cap.availableBytes > freeBefore
                ? cap.availableBytes - freeBefore
                : 0
            // Treat anything below half the expected reclaim as "ghosted".
            let threshold = priorSize / 2
            guard actualFreed < threshold else { return }

            let holders = GhostFileDetector.holdersOfDeletedFiles(in: path)
            guard !holders.isEmpty else { return }

            DispatchQueue.main.async {
                self.presentGhostFilesAlert(path: path,
                                            holders: holders,
                                            expected: priorSize,
                                            actualFreed: actualFreed)
            }
        }
    }

    private func presentGhostFilesAlert(path: URL,
                                        holders: [GhostFileDetector.Holder],
                                        expected: UInt64,
                                        actualFreed: UInt64) {
        activateForModal()
        let alert = NSAlert()
        alert.messageText = "Disk space still held"
        let stillHeld = expected > actualFreed ? expected - actualFreed : 0
        let list = holders.prefix(12)
            .map { "  • \($0.command) (pid \($0.pid))" }
            .joined(separator: "\n")
        let more = holders.count > 12 ? "\n  …and \(holders.count - 12) more" : ""
        alert.informativeText =
            "We freed ~\(ByteSize.human(actualFreed)) but ~\(ByteSize.human(stillHeld)) is still held by "
            + "background processes with open file descriptors. macOS won't release the bytes until those "
            + "processes restart.\n\n\(list)\(more)\n\n"
            + "Terminate them now? They'll be respawned by their parents (Claude Code, your shell, …)."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Terminate \(holders.count) process\(holders.count == 1 ? "" : "es")")
        alert.addButton(withTitle: "Leave them")

        if alert.runModal() == .alertFirstButtonReturn {
            let killed = GhostFileDetector.terminate(holders)
            // Give the kernel a moment to settle, then refresh capacity.
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.indexer.refreshEntry(path: path)
                self?.indexer.refreshNow()
                DispatchQueue.main.async {
                    let done = NSAlert()
                    done.messageText = "Sent SIGTERM to \(killed) of \(holders.count)"
                    done.informativeText = "Disk space should release within a few seconds. The menu will refresh once the kernel finalises."
                    done.alertStyle = .informational
                    done.addButton(withTitle: "OK")
                    _ = done.runModal()
                }
            }
        }
    }

    // MARK: - elapsed timer

    private func startElapsedTimer() {
        elapsedTimer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + 1, repeating: 1)
        t.setEventHandler { [weak self] in self?.rebuildMenu() }
        t.resume()
        elapsedTimer = t
    }

    private func stopElapsedTimer() {
        elapsedTimer?.cancel()
        elapsedTimer = nil
    }

    // MARK: - modal helper

    private func activateForModal() {
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - NSMenuDelegate (menu-open refresh)

extension MenuBarAppDelegate: NSMenuDelegate {
    /// If the cache is older than 5 minutes when the user opens the menu,
    /// kick off a refresh in the background. The user sees current data
    /// now and fresher data on their next interaction. Cheap thanks to
    /// the mtime cache.
    func menuWillOpen(_ menu: NSMenu) {
        if case .ready(let date) = latestState,
           Date().timeIntervalSince(date) > 300 {
            indexer.refreshNow()
        }
    }
}
