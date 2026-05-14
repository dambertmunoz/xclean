import AppKit

/// Builds the NSMenu shown when the user clicks the status item.
///
/// Stateless renderer. All data and callbacks come in via `Inputs` /
/// `Callbacks` — the builder never touches the indexer, history store, or
/// preferences directly. Easy to unit-test and easy to extend.
final class MenuBuilder: NSObject {

    // MARK: - public types

    struct Inputs {
        let findings: [InspectFinding]
        let capacity: DiskCapacity?
        let sparkline: String?
        let state: IndexerService.State
        let freedToday: UInt64
        let bulkCount: Int
        let bulkPotentialBytes: UInt64
        let recentHistory: [HistoryEvent]
        /// Estimated seconds until free disk hits zero at the current rate.
        /// `nil` if disk is growing or we lack data.
        let projectionSeconds: TimeInterval?
        let autoReclaimEnabled: Bool
        let hasProjectArtifacts: Bool
    }

    struct Callbacks {
        let onReveal: (URL) -> Void
        let onCleanup: (InspectFinding, String) -> Void
        let onTrash: (InspectFinding) -> Void
        let onCopyCommand: (String) -> Void
        let onRefresh: () -> Void
        let onCancel: () -> Void
        let onBulk: () -> Void
        let onToggleCompact: () -> Void
        let onToggleDeltas: () -> Void
        let onToggleNotify: () -> Void
        let onEditCustomPaths: () -> Void
        let onClearHistory: () -> Void
        let onScanProjects: () -> Void
        let onClearProjects: () -> Void
        let onToggleAutoReclaim: () -> Void
        let onGrantFDA: () -> Void
        let onEnterLicense: () -> Void
        let onDeactivateLicense: () -> Void
    }

    // MARK: - state (re-captured on every build)

    private var callbacks: Callbacks?
    private var actionPayloads: [Any] = []

    // MARK: - entrypoint

    func build(_ inputs: Inputs, callbacks: Callbacks) -> NSMenu {
        self.callbacks = callbacks
        self.actionPayloads = []

        let menu = NSMenu()
        menu.autoenablesItems = false

        // 1. Donut + breakdown header (custom view).
        appendBreakdownHeader(to: menu,
                              capacity: inputs.capacity,
                              recoverable: totalBytes(inputs.findings))

        // 1b. Optional textual context: sparkline + predicted exhaustion.
        if let cap = inputs.capacity, let spark = inputs.sparkline, !spark.isEmpty {
            appendSparkline(to: menu, sparkline: spark, health: cap.health)
        }
        if let projection = inputs.projectionSeconds {
            appendProjectionAlert(to: menu, seconds: projection, health: inputs.capacity?.health)
        }

        // 2. Freed today.
        if inputs.freedToday > 0 {
            appendDisabled("Freed today: \(ByteSize.human(inputs.freedToday)) ✓",
                           to: menu, color: .systemGreen)
        }

        // 3. Bulk reclaim
        if inputs.bulkCount >= 2 && inputs.bulkPotentialBytes >= 1024 * 1024 * 1024 {
            menu.addItem(.separator())
            appendBulkButton(to: menu,
                             count: inputs.bulkCount,
                             potential: inputs.bulkPotentialBytes,
                             state: inputs.state)
        }

        menu.addItem(.separator())

        // 4. Current status
        appendDisabled(statusLabel(for: inputs.state), to: menu)
        menu.addItem(.separator())

        // 5. Findings
        if inputs.findings.isEmpty {
            appendDisabled("No data yet — refreshing…", to: menu)
        } else {
            appendTopConsumers(to: menu, findings: inputs.findings)
            menu.addItem(.separator())
            appendCategories(to: menu, findings: inputs.findings)
        }

        menu.addItem(.separator())

        // 6. History
        appendHistorySubmenu(to: menu, events: inputs.recentHistory)
        menu.addItem(.separator())

        // 7. Footer: actions + prefs
        currentAutoReclaimState = inputs.autoReclaimEnabled ? .on : .off
        appendFooter(to: menu, state: inputs.state, hasProjectArtifacts: inputs.hasProjectArtifacts)
        return menu
    }

    // MARK: - section 1: capacity header

    /// Donut breakdown view — replaces the old single-line capacity header
    /// with a visual ring plus legend (Free · Recoverable · Other used).
    private func appendBreakdownHeader(to menu: NSMenu, capacity: DiskCapacity?, recoverable: UInt64) {
        guard let cap = capacity else {
            appendDisabled("Disk: measuring…", to: menu)
            return
        }
        let view = DiskBreakdownView()
        view.set(free: cap.availableBytes,
                 recoverable: recoverable,
                 total: cap.totalBytes,
                 health: cap.health)
        let item = NSMenuItem()
        item.view = view
        item.isEnabled = false
        menu.addItem(item)

        // Keep a glanceable text line below for the percentage.
        let percentFree = Int(cap.freeRatio * 100 + 0.5)
        appendDisabled("\(percentFree)% free of \(ByteSize.human(cap.totalBytes))", to: menu)
    }

    /// 7-day free-space trend rendered with Unicode block chars.
    /// Spark color tracks health; the prefix uses `secondary` instead of
    /// `tertiary` so the row doesn't visually vanish on light menus.
    private func appendSparkline(to menu: NSMenu, sparkline: String, health: DiskCapacity.Health) {
        let label = NSMutableAttributedString(string: "Last 7 days  ", attributes: [
            .foregroundColor: MenuTheme.secondary,
            .font: MenuTheme.smallSecondaryFont
        ])
        label.append(NSAttributedString(string: sparkline, attributes: [
            .foregroundColor: sparklineColor(for: health),
            .font: NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        ]))
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.attributedTitle = label
        item.isEnabled = false
        menu.addItem(item)
    }

    /// "At current rate, disk fills in N days" — only shown when the trend
    /// projects exhaustion inside a window worth caring about (<= 30 days).
    private func appendProjectionAlert(to menu: NSMenu, seconds: TimeInterval, health: DiskCapacity.Health?) {
        let days = Int((seconds / 86_400).rounded())
        guard days <= 30 else { return }

        let urgent = days <= 7
        let labelColor: NSColor = urgent ? .systemRed : .systemOrange
        let humanWindow: String
        if days < 1 {
            humanWindow = "< 1 day"
        } else if days == 1 {
            humanWindow = "1 day"
        } else {
            humanWindow = "\(days) days"
        }
        let label = "⚠︎ At current rate, disk fills in \(humanWindow)"
        let item = NSMenuItem(title: label, action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(string: label, attributes: [.foregroundColor: labelColor])
        item.isEnabled = false
        item.toolTip = "Based on linear regression over the last week of free-space samples."
        menu.addItem(item)
        // Implicit silence warning: health is unused but kept for future per-health styling.
        _ = health
    }

    // MARK: - section 3: bulk

    private func appendBulkButton(to menu: NSMenu, count: Int, potential: UInt64, state: IndexerService.State) {
        let title = "⚡ Reclaim ~\(ByteSize.human(potential)) (\(count) safe actions)"
        let item = NSMenuItem(title: title,
                              action: #selector(handleBulk(_:)),
                              keyEquivalent: "")
        item.target = self
        item.isEnabled = isInteractive(state)
        // Bold the action so it stands out.
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.menuBarFont(ofSize: 0).withTraits(.boldFontMask) ?? NSFont.menuBarFont(ofSize: 0)
        ]
        item.attributedTitle = NSAttributedString(string: title, attributes: attrs)
        menu.addItem(item)
    }

    // MARK: - section 5: findings

    private func appendTopConsumers(to menu: NSMenu, findings: [InspectFinding]) {
        appendSectionHeader("Top consumers", to: menu)
        for f in findings.prefix(10) {
            menu.addItem(makeFindingItem(f))
        }
    }

    /// Section title that reads as a header — semibold weight, ~65% black,
    /// so headings don't disappear into the body text the way the macOS
    /// default disabled-item gray does.
    private func appendSectionHeader(_ title: String, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(string: title, attributes: [
            .font: MenuTheme.sectionTitleFont,
            .foregroundColor: MenuTheme.sectionTitleColor
        ])
        item.isEnabled = false
        menu.addItem(item)
    }

    private func appendCategories(to menu: NSMenu, findings: [InspectFinding]) {
        let item = NSMenuItem(title: "By category", action: nil, keyEquivalent: "")
        item.submenu = buildCategoriesSubmenu(findings: findings)
        menu.addItem(item)
    }

    private func makeFindingItem(_ f: InspectFinding) -> NSMenuItem {
        // Title:  "● 27.92 GB   uv cache   +2.1 GB ▲"
        //         ^ safety dot (colored)
        let attr = NSMutableAttributedString()
        attr.append(safetyDot(for: f.entry.safetyClass))
        attr.append(NSAttributedString(string: "  "))
        attr.append(NSAttributedString(
            string: pad(ByteSize.human(f.sizeBytes), to: 10) + "   ",
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)]
        ))
        attr.append(NSAttributedString(string: f.entry.label))
        if Preferences.shared.showDeltas, let deltaAttr = deltaAttributedString(for: f.delta) {
            attr.append(NSAttributedString(string: "   "))
            attr.append(deltaAttr)
        }

        let item = NSMenuItem(title: f.entry.label, action: nil, keyEquivalent: "")
        item.attributedTitle = attr
        item.submenu = buildEntrySubmenu(for: f)
        item.toolTip = "[\(f.entry.safetyClass.label)] " + (f.entry.note ?? f.entry.path.path)
        return item
    }

    /// Colored dot communicating delete safety at a glance:
    ///   🟢 cache · 🟠 data · 🔴 install · ⚫ user data.
    /// Uses `MenuTheme.safetyDot` so the warning hue is orange, not the
    /// washed-out yellow.
    private func safetyDot(for safety: SafetyClass) -> NSAttributedString {
        return NSAttributedString(string: "●", attributes: [
            .foregroundColor: MenuTheme.safetyDot(safety),
            .font: NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        ])
    }

    private func deltaAttributedString(for delta: Int64?) -> NSAttributedString? {
        guard let delta = delta else { return nil }
        let threshold: Int64 = 50 * 1024 * 1024
        guard abs(delta) >= threshold else { return nil }
        let magnitude = ByteSize.human(UInt64(abs(delta)))
        let arrow = delta > 0 ? "▲" : "▼"
        let sign = delta > 0 ? "+" : "−"
        let color: NSColor = (delta > 0) ? .systemOrange : .systemGreen
        return NSAttributedString(string: "\(sign)\(magnitude) \(arrow)", attributes: [
            .foregroundColor: color,
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        ])
    }

    private func buildEntrySubmenu(for finding: InspectFinding) -> NSMenu {
        let menu = NSMenu()

        // Reveal
        let reveal = NSMenuItem(title: "Reveal in Finder",
                                action: #selector(handleReveal(_:)), keyEquivalent: "")
        reveal.target = self
        reveal.representedObject = finding.entry.path
        menu.addItem(reveal)

        if let cmd = finding.entry.cleanup {
            menu.addItem(.separator())

            // Free
            let freeTitle = "Free \(ByteSize.human(finding.sizeBytes))  ·  \(cmd)"
            let freeItem = NSMenuItem(title: freeTitle, action: #selector(handleCleanup(_:)),
                                      keyEquivalent: "")
            freeItem.target = self
            let payload = CleanupPayload(finding: finding, command: cmd)
            actionPayloads.append(payload)
            freeItem.representedObject = payload
            menu.addItem(freeItem)

            // Copy command
            let copyItem = NSMenuItem(title: "Copy command to clipboard",
                                      action: #selector(handleCopyCommand(_:)),
                                      keyEquivalent: "")
            copyItem.target = self
            copyItem.representedObject = cmd
            menu.addItem(copyItem)
        }

        if !finding.entry.dangerToTrash {
            if finding.entry.cleanup == nil { menu.addItem(.separator()) }
            let trashItem = NSMenuItem(
                title: "Move \(ByteSize.human(finding.sizeBytes)) to Trash",
                action: #selector(handleTrash(_:)), keyEquivalent: "")
            trashItem.target = self
            actionPayloads.append(finding)
            trashItem.representedObject = finding
            menu.addItem(trashItem)
        }

        if let note = finding.entry.note {
            menu.addItem(.separator())
            appendDisabled("ⓘ \(note)", to: menu)
        }

        menu.addItem(.separator())
        appendDisabled(displayPath(finding.entry.path), to: menu)
        return menu
    }

    private func buildCategoriesSubmenu(findings: [InspectFinding]) -> NSMenu {
        let menu = NSMenu()
        let grouped = Dictionary(grouping: findings) { $0.entry.category }
        for cat in InspectCategory.allCases {
            guard let items = grouped[cat], !items.isEmpty else { continue }
            let catTotal = items.reduce(UInt64(0)) { $0 + $1.sizeBytes }
            let catItem = NSMenuItem(title: "\(cat.rawValue) — \(ByteSize.human(catTotal))",
                                     action: nil, keyEquivalent: "")
            catItem.submenu = buildCategoryDetailMenu(items: items)
            menu.addItem(catItem)
        }
        return menu
    }

    private func buildCategoryDetailMenu(items: [InspectFinding]) -> NSMenu {
        let menu = NSMenu()
        for f in items.sorted(by: { $0.sizeBytes > $1.sizeBytes }) {
            menu.addItem(makeFindingItem(f))
        }
        return menu
    }

    // MARK: - section 6: history

    private func appendHistorySubmenu(to menu: NSMenu, events: [HistoryEvent]) {
        let parent = NSMenuItem(title: "History", action: nil, keyEquivalent: "")
        let sub = NSMenu()

        if events.isEmpty {
            let empty = NSMenuItem(title: "no actions yet", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            sub.addItem(empty)
        } else {
            for e in events.prefix(20) {
                let icon = e.success ? "✓" : "✗"
                let stamp = formatHistoryTimestamp(e.timestamp)
                let detail = e.bytesFreed > 0 ? "  ·  \(ByteSize.human(e.bytesFreed))" : ""
                let line = "\(icon) \(stamp)  \(e.label)\(detail)"
                let item = NSMenuItem(title: line, action: nil, keyEquivalent: "")
                item.toolTip = e.failureMessage ?? e.pathString
                item.isEnabled = false
                sub.addItem(item)
            }
            sub.addItem(.separator())
            let clear = NSMenuItem(title: "Clear history",
                                   action: #selector(handleClearHistory(_:)),
                                   keyEquivalent: "")
            clear.target = self
            sub.addItem(clear)
        }
        parent.submenu = sub
        menu.addItem(parent)
    }

    private func formatHistoryTimestamp(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "MMM d, HH:mm"
        return f.string(from: d)
    }

    // MARK: - section 7: footer

    private func appendFooter(to menu: NSMenu, state: IndexerService.State, hasProjectArtifacts: Bool) {
        // Cancel only visible during a destructive op.
        if case .running = state {
            let cancelItem = NSMenuItem(title: "Cancel running operation",
                                        action: #selector(handleCancel(_:)),
                                        keyEquivalent: ".")
            cancelItem.target = self
            menu.addItem(cancelItem)
            menu.addItem(.separator())
        }

        let refreshItem = NSMenuItem(title: "Refresh now",
                                     action: #selector(handleRefresh(_:)),
                                     keyEquivalent: "r")
        refreshItem.target = self
        refreshItem.isEnabled = isInteractive(state)
        menu.addItem(refreshItem)

        // Project scan
        let scanProjects = NSMenuItem(
            title: hasProjectArtifacts ? "Rescan projects for artifacts" : "Scan projects for artifacts",
            action: #selector(handleScanProjects(_:)),
            keyEquivalent: ""
        )
        scanProjects.target = self
        scanProjects.isEnabled = isInteractive(state)
        scanProjects.toolTip = "Walks ~/code, ~/Projects, ~/Documents, … for node_modules, .next, target/, Pods/, etc."
        menu.addItem(scanProjects)

        if hasProjectArtifacts {
            let clearProjects = NSMenuItem(title: "Clear scanned project list",
                                           action: #selector(handleClearProjects(_:)),
                                           keyEquivalent: "")
            clearProjects.target = self
            menu.addItem(clearProjects)
        }

        // Preferences submenu
        let prefs = NSMenuItem(title: "Preferences", action: nil, keyEquivalent: "")
        prefs.submenu = buildPreferencesSubmenu()
        menu.addItem(prefs)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit xclean",
                              action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func buildPreferencesSubmenu() -> NSMenu {
        let menu = NSMenu()

        let compact = NSMenuItem(title: "Compact mode (hide < 1 GB)",
                                 action: #selector(handleToggleCompact(_:)),
                                 keyEquivalent: "")
        compact.target = self
        compact.state = Preferences.shared.compactMode ? .on : .off
        menu.addItem(compact)

        let deltas = NSMenuItem(title: "Show size deltas",
                                action: #selector(handleToggleDeltas(_:)),
                                keyEquivalent: "")
        deltas.target = self
        deltas.state = Preferences.shared.showDeltas ? .on : .off
        menu.addItem(deltas)

        let notify = NSMenuItem(title: "Notify on low disk",
                                action: #selector(handleToggleNotify(_:)),
                                keyEquivalent: "")
        notify.target = self
        notify.state = Preferences.shared.notifyEnabled ? .on : .off
        menu.addItem(notify)

        menu.addItem(.separator())

        let autoReclaim = NSMenuItem(title: "Auto-reclaim every Sunday 3am",
                                     action: #selector(handleToggleAutoReclaim(_:)),
                                     keyEquivalent: "")
        autoReclaim.target = self
        autoReclaim.state = currentAutoReclaimState
        menu.addItem(autoReclaim)

        menu.addItem(.separator())

        let editPaths = NSMenuItem(title: "Edit custom paths…",
                                   action: #selector(handleEditCustomPaths(_:)),
                                   keyEquivalent: "")
        editPaths.target = self
        menu.addItem(editPaths)

        let showCache = NSMenuItem(title: "Show xclean folder in Finder",
                                   action: #selector(handleShowCacheFolder(_:)),
                                   keyEquivalent: "")
        showCache.target = self
        menu.addItem(showCache)

        menu.addItem(.separator())

        // Full Disk Access — shows a ✓ when granted, otherwise opens both
        // System Settings (FDA pane) and Finder with xclean.app preselected
        // so the user can drag it straight into the FDA list.
        let hasFDA = RuntimeProbe.hasFullDiskAccess()
        let fda = NSMenuItem(
            title: hasFDA ? "Full Disk Access  ✓" : "Grant Full Disk Access…",
            action: #selector(handleGrantFDA(_:)),
            keyEquivalent: ""
        )
        fda.target = self
        fda.state = hasFDA ? .on : .off
        fda.toolTip = hasFDA
            ? "xclean can already modify sandboxed paths."
            : "Required to Move sandboxed folders (Docker, etc.) to Trash."
        menu.addItem(fda)

        menu.addItem(.separator())
        appendLicenseItems(to: menu)

        return menu
    }

    private func appendLicenseItems(to menu: NSMenu) {
        let state = LicenseManager.shared.currentState()
        switch state {
        case .active(let exp):
            let days = max(0, Int(exp.timeIntervalSinceNow / 86_400))
            let header = NSMenuItem(title: "License: active · \(days) days left", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            let off = NSMenuItem(title: "Deactivate this Mac…",
                                 action: #selector(handleDeactivateLicense(_:)),
                                 keyEquivalent: "")
            off.target = self
            menu.addItem(off)
        case .grace(_, let deadline):
            let daysToDeadline = max(0, Int(deadline.timeIntervalSinceNow / 86_400))
            let header = NSMenuItem(title: "License: offline grace · \(daysToDeadline)d to revalidate",
                                    action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            let off = NSMenuItem(title: "Deactivate this Mac…",
                                 action: #selector(handleDeactivateLicense(_:)),
                                 keyEquivalent: "")
            off.target = self
            menu.addItem(off)
        case .unactivated:
            let header = NSMenuItem(title: "License: not activated", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            let enter = NSMenuItem(title: "Enter license key…",
                                   action: #selector(handleEnterLicense(_:)),
                                   keyEquivalent: "")
            enter.target = self
            menu.addItem(enter)
        case .invalid(let reason):
            let header = NSMenuItem(title: "License: invalid (\(reason))",
                                    action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            let enter = NSMenuItem(title: "Re-enter license key…",
                                   action: #selector(handleEnterLicense(_:)),
                                   keyEquivalent: "")
            enter.target = self
            menu.addItem(enter)
        }
    }

    /// Captured at build time so the checkmark reflects the live state.
    /// The AppDelegate writes this before each rebuild.
    private var currentAutoReclaimState: NSControl.StateValue = .off

    // MARK: - actions

    @objc private func handleReveal(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        callbacks?.onReveal(url)
    }

    @objc private func handleCleanup(_ sender: NSMenuItem) {
        guard let p = sender.representedObject as? CleanupPayload else { return }
        callbacks?.onCleanup(p.finding, p.command)
    }

    @objc private func handleTrash(_ sender: NSMenuItem) {
        guard let f = sender.representedObject as? InspectFinding else { return }
        callbacks?.onTrash(f)
    }

    @objc private func handleCopyCommand(_ sender: NSMenuItem) {
        guard let s = sender.representedObject as? String else { return }
        callbacks?.onCopyCommand(s)
    }

    @objc private func handleRefresh(_ sender: NSMenuItem) { callbacks?.onRefresh() }
    @objc private func handleCancel(_ sender: NSMenuItem) { callbacks?.onCancel() }
    @objc private func handleBulk(_ sender: NSMenuItem) { callbacks?.onBulk() }
    @objc private func handleClearHistory(_ sender: NSMenuItem) { callbacks?.onClearHistory() }
    @objc private func handleToggleCompact(_ sender: NSMenuItem) { callbacks?.onToggleCompact() }
    @objc private func handleToggleDeltas(_ sender: NSMenuItem) { callbacks?.onToggleDeltas() }
    @objc private func handleToggleNotify(_ sender: NSMenuItem) { callbacks?.onToggleNotify() }
    @objc private func handleEditCustomPaths(_ sender: NSMenuItem) { callbacks?.onEditCustomPaths() }
    @objc private func handleShowCacheFolder(_ sender: NSMenuItem) {
        callbacks?.onReveal(IndexStore.defaultDirectory)
    }

    @objc private func handleScanProjects(_ sender: NSMenuItem) { callbacks?.onScanProjects() }
    @objc private func handleClearProjects(_ sender: NSMenuItem) { callbacks?.onClearProjects() }
    @objc private func handleToggleAutoReclaim(_ sender: NSMenuItem) { callbacks?.onToggleAutoReclaim() }
    @objc private func handleGrantFDA(_ sender: NSMenuItem) { callbacks?.onGrantFDA() }
    @objc private func handleEnterLicense(_ sender: NSMenuItem) { callbacks?.onEnterLicense() }
    @objc private func handleDeactivateLicense(_ sender: NSMenuItem) { callbacks?.onDeactivateLicense() }

    // MARK: - small helpers

    private func appendDisabled(_ title: String, to menu: NSMenu, color: NSColor? = nil) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        if let color = color {
            item.attributedTitle = NSAttributedString(string: title, attributes: [.foregroundColor: color])
        }
        item.isEnabled = false
        menu.addItem(item)
    }

    private func totalBytes(_ findings: [InspectFinding]) -> UInt64 {
        return findings.reduce(UInt64(0)) { $0 + $1.sizeBytes }
    }

    private func pad(_ s: String, to width: Int) -> String {
        return s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
    }

    private func healthDot(for health: DiskCapacity.Health) -> NSAttributedString {
        return NSAttributedString(string: "●", attributes: [
            .foregroundColor: MenuTheme.health(health),
            .font: NSFont.menuBarFont(ofSize: 0)
        ])
    }

    /// Sparkline color: a readable mid-tone in healthy state, then orange
    /// / red as the disk degrades. Yellow text gets lost on light menus.
    private func sparklineColor(for health: DiskCapacity.Health) -> NSColor {
        switch health {
        case .healthy:  return MenuTheme.secondary
        case .warning:  return MenuTheme.health(.warning)
        case .critical: return MenuTheme.health(.critical)
        }
    }

    private func isInteractive(_ state: IndexerService.State) -> Bool {
        switch state {
        case .indexing, .running: return false
        case .idle, .ready:       return true
        }
    }

    private func statusLabel(for state: IndexerService.State) -> String {
        switch state {
        case .idle:               return "Status: idle"
        case .indexing:           return "Status: indexing…"
        case .running(let label, let startedAt):
            return "Running: \(label) (\(formatElapsed(startedAt)))"
        case .ready(let date):    return "Last scan: \(relativeTime(since: date))"
        }
    }

    private func formatElapsed(_ startedAt: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(startedAt)))
        if seconds < 60 { return "\(seconds)s" }
        let m = seconds / 60
        let s = seconds % 60
        if m < 60 { return String(format: "%dm %02ds", m, s) }
        let h = m / 60
        let rm = m % 60
        return String(format: "%dh %02dm %02ds", h, rm, s)
    }

    private func relativeTime(since date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60   { return "\(seconds)s ago" }
        if seconds < 3600 { return "\(seconds / 60) min ago" }
        return "\(seconds / 3600) h ago"
    }

    private func displayPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if url.path.hasPrefix(home) { return "~" + url.path.dropFirst(home.count) }
        return url.path
    }
}

private final class CleanupPayload {
    let finding: InspectFinding
    let command: String
    init(finding: InspectFinding, command: String) {
        self.finding = finding
        self.command = command
    }
}

private extension NSFont {
    func withTraits(_ traits: NSFontTraitMask) -> NSFont? {
        return NSFontManager.shared.font(withFamily: self.familyName ?? "Helvetica",
                                         traits: traits,
                                         weight: 5,
                                         size: self.pointSize)
    }
}
